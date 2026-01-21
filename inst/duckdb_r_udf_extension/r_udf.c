/**
 * DuckDB R UDF Extension v3 - Channel-Based Architecture
 * 
 * A DuckDB extension that allows calling R functions from SQL queries.
 * Uses Go-like channels for thread-safe R callbacks from DuckDB worker threads.
 * 
 * Architecture:
 *   - Global request channel: workers send r_request_t*, main thread receives
 *   - Per-request response: each request has its own completion signaling
 *   - Channel integrates with R's event loop via signal pipe
 *   - Uses R_ToplevelExec for safe R API calls with longjmp protection
 *
 * Threading Model:
 *   1. Worker thread creates request, sends to g_request_chan
 *   2. Channel's signal pipe wakes R's input handler
 *   3. Main thread receives from channel, processes request
 *   4. Main thread signals completion via request's condition variable
 *   5. Worker thread wakes and retrieves result
 *
 * Inspired by c_chan (Paul J. Lucas, GPL-3) but simplified for this use case.
 *
 * Copyright (c) 2026 RBCFTools Authors
 * Licensed under MIT License
 */

#define DUCKDB_EXTENSION_NAME r_udf

#include "duckdb_extension.h"
#include "r_chan.h"

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <pthread.h>
#include <errno.h>
#include <stdatomic.h>

#ifndef _WIN32
#include <unistd.h>
#include <sys/select.h>
#include <fcntl.h>
#endif

// R headers
#define R_NO_REMAP
#define STRICT_R_HEADERS
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Parse.h>
#ifndef _WIN32
#include <R_ext/eventloop.h>
#endif

DUCKDB_EXTENSION_EXTERN

// =============================================================================
// Configuration
// =============================================================================

#define R_UDF_MAX_RESULT_SIZE 8192
#define R_UDF_MAX_ERROR_SIZE 256
#define R_UDF_QUEUE_SIZE 256
#define R_UDF_POLL_TIMEOUT_MS 100

// Debug flag - set to 1 to enable debug output
#define R_UDF_DEBUG 1

#if R_UDF_DEBUG
#define DEBUG_LOG(...) do { fprintf(stderr, "[r_udf] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); fflush(stderr); } while(0)
#else
#define DEBUG_LOG(...) ((void)0)
#endif

// =============================================================================
// Type Declarations - inspired by quickr::declare()
// 
// Syntax: R_TYPE(mode, length)
//   mode: DOUBLE, INTEGER, LOGICAL, CHARACTER, RAW
//   length: 1 for scalar, NA for vector of any length, N for fixed length
// =============================================================================

typedef enum {
    R_TYPE_NULL = 0,
    R_TYPE_DOUBLE_1,      // double(1) - scalar double
    R_TYPE_INTEGER_1,     // integer(1) - scalar integer  
    R_TYPE_LOGICAL_1,     // logical(1) - scalar logical
    R_TYPE_CHARACTER_1,   // character(1) - scalar string
    R_TYPE_RAW_NA,        // raw(NA) - raw bytes of any length
    R_TYPE_DOUBLE_NA,     // double(NA) - double vector
    R_TYPE_INTEGER_NA,    // integer(NA) - integer vector
    R_TYPE_LOGICAL_NA,    // logical(NA) - logical vector
    R_TYPE_CHARACTER_NA,  // character(NA) - character vector
    R_TYPE_ERROR,         // Error result
} r_type_t;

// Result value union
typedef union {
    double double_val;
    int int_val;
    int logical_val;
    char* string_val;
    struct { unsigned char* data; size_t len; } raw;
    struct { double* data; size_t len; } double_vec;
    struct { int* data; size_t len; } int_vec;
    struct { int* data; size_t len; } logical_vec;
    struct { char** data; size_t len; } string_vec;
} r_value_t;

// Typed R result
typedef struct {
    r_type_t type;
    r_value_t value;
    int is_na;
    char error_msg[R_UDF_MAX_ERROR_SIZE];
} r_result_t;

// =============================================================================
// Request Queue for Worker-to-Main-Thread Communication (via r_chan)
// =============================================================================

// Request types
typedef enum {
    R_REQ_EVAL,           // Simple eval returning string
    R_REQ_EVAL_TYPED,     // Typed eval with expected return type
    R_REQ_EVAL_WITH_X,    // Eval with numeric .x parameter
    R_REQ_EVAL_WITH_STR,  // Eval with string .x parameter
} r_request_type_t;

// A queued R request
typedef struct r_request {
    // Request parameters
    r_request_type_t req_type;
    char* r_code;
    r_type_t expected_type;
    
    // Optional .x parameter for scalar functions
    union {
        struct { double val; int is_null; } x_double;
        struct { char* val; int is_null; } x_string;
    } x_param;
    
    // Result storage
    r_result_t result;
    
    // Per-request synchronization (for worker to wait on completion)
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    atomic_int completed;
} r_request_t;

// =============================================================================
// Global State
// =============================================================================

// Thread identification
static pthread_t g_main_thread_id;
static atomic_int g_initialized = ATOMIC_VAR_INIT(0);
static atomic_int g_in_r_call = ATOMIC_VAR_INIT(0);

// Request channel: workers send requests, main thread receives
static r_chan_t g_request_chan;
static atomic_int g_chan_initialized = ATOMIC_VAR_INIT(0);

#ifndef _WIN32
static InputHandler* g_input_handler = NULL;
#endif

// =============================================================================
// Thread Safety Utilities
// =============================================================================

static inline int is_main_thread(void) {
    return atomic_load(&g_initialized) && 
           pthread_equal(pthread_self(), g_main_thread_id);
}

// =============================================================================
// Result Memory Management
// =============================================================================

static void r_result_free(r_result_t* res) {
    if (!res) return;
    
    switch (res->type) {
        case R_TYPE_CHARACTER_1:
            free(res->value.string_val);
            break;
        case R_TYPE_RAW_NA:
            free(res->value.raw.data);
            break;
        case R_TYPE_DOUBLE_NA:
            free(res->value.double_vec.data);
            break;
        case R_TYPE_INTEGER_NA:
            free(res->value.int_vec.data);
            break;
        case R_TYPE_LOGICAL_NA:
            free(res->value.logical_vec.data);
            break;
        case R_TYPE_CHARACTER_NA:
            for (size_t i = 0; i < res->value.string_vec.len; i++) {
                free(res->value.string_vec.data[i]);
            }
            free(res->value.string_vec.data);
            break;
        default:
            break;
    }
    memset(res, 0, sizeof(r_result_t));
}

// =============================================================================
// Request Operations (no queue linkage needed - channel handles it)
// =============================================================================

static r_request_t* request_create(r_request_type_t type, const char* r_code) {
    r_request_t* req = calloc(1, sizeof(r_request_t));
    if (!req) return NULL;
    
    req->req_type = type;
    req->r_code = strdup(r_code);
    atomic_init(&req->completed, 0);
    pthread_mutex_init(&req->mutex, NULL);
    pthread_cond_init(&req->cond, NULL);
    
    return req;
}

static void request_destroy(r_request_t* req) {
    if (!req) return;
    free(req->r_code);
    if (req->req_type == R_REQ_EVAL_WITH_STR && req->x_param.x_string.val) {
        free(req->x_param.x_string.val);
    }
    pthread_mutex_destroy(&req->mutex);
    pthread_cond_destroy(&req->cond);
    free(req);
}

// =============================================================================
// R Evaluation Callbacks (run on main thread via R_ToplevelExec)
// =============================================================================

typedef struct {
    const char* r_code;
    double x_val;
    int x_is_null;
    const char* x_str;
    r_result_t* result;
    r_type_t expected_type;
} r_eval_callback_data_t;

// Convert SEXP to r_result_t based on expected type
static void sexp_to_result(SEXP sexp, r_type_t expected, r_result_t* result) {
    result->is_na = 0;
    
    if (sexp == R_NilValue) {
        result->type = R_TYPE_NULL;
        return;
    }
    
    int sexp_type = TYPEOF(sexp);
    int len = Rf_length(sexp);
    
    // Handle based on expected type
    switch (expected) {
        case R_TYPE_DOUBLE_1:
            result->type = R_TYPE_DOUBLE_1;
            if (sexp_type == REALSXP && len >= 1) {
                double val = REAL(sexp)[0];
                if (ISNA(val) || ISNAN(val)) {
                    result->is_na = 1;
                } else {
                    result->value.double_val = val;
                }
            } else if (sexp_type == INTSXP && len >= 1) {
                int val = INTEGER(sexp)[0];
                if (val == NA_INTEGER) {
                    result->is_na = 1;
                } else {
                    result->value.double_val = (double)val;
                }
            } else {
                result->type = R_TYPE_ERROR;
                snprintf(result->error_msg, sizeof(result->error_msg),
                         "Expected double(1), got type %d len %d", sexp_type, len);
            }
            break;
            
        case R_TYPE_INTEGER_1:
            result->type = R_TYPE_INTEGER_1;
            if (sexp_type == INTSXP && len >= 1) {
                int val = INTEGER(sexp)[0];
                if (val == NA_INTEGER) {
                    result->is_na = 1;
                } else {
                    result->value.int_val = val;
                }
            } else if (sexp_type == REALSXP && len >= 1) {
                double val = REAL(sexp)[0];
                if (ISNA(val) || ISNAN(val)) {
                    result->is_na = 1;
                } else {
                    result->value.int_val = (int)val;
                }
            } else {
                result->type = R_TYPE_ERROR;
                snprintf(result->error_msg, sizeof(result->error_msg),
                         "Expected integer(1), got type %d", sexp_type);
            }
            break;
            
        case R_TYPE_LOGICAL_1:
            result->type = R_TYPE_LOGICAL_1;
            if (sexp_type == LGLSXP && len >= 1) {
                int val = LOGICAL(sexp)[0];
                if (val == NA_LOGICAL) {
                    result->is_na = 1;
                } else {
                    result->value.logical_val = val;
                }
            } else {
                result->type = R_TYPE_ERROR;
                snprintf(result->error_msg, sizeof(result->error_msg),
                         "Expected logical(1), got type %d", sexp_type);
            }
            break;
            
        case R_TYPE_CHARACTER_1:
            result->type = R_TYPE_CHARACTER_1;
            if (sexp_type == STRSXP && len >= 1) {
                SEXP str = STRING_ELT(sexp, 0);
                if (str == NA_STRING) {
                    result->is_na = 1;
                } else {
                    result->value.string_val = strdup(CHAR(str));
                }
            } else {
                // Try to coerce to string
                char buf[256];
                if (sexp_type == REALSXP && len >= 1) {
                    snprintf(buf, sizeof(buf), "%g", REAL(sexp)[0]);
                    result->value.string_val = strdup(buf);
                } else if (sexp_type == INTSXP && len >= 1) {
                    snprintf(buf, sizeof(buf), "%d", INTEGER(sexp)[0]);
                    result->value.string_val = strdup(buf);
                } else if (sexp_type == LGLSXP && len >= 1) {
                    int val = LOGICAL(sexp)[0];
                    result->value.string_val = strdup(val == NA_LOGICAL ? "NA" : 
                                                       (val ? "TRUE" : "FALSE"));
                } else {
                    snprintf(buf, sizeof(buf), "<R:%d>", sexp_type);
                    result->value.string_val = strdup(buf);
                }
            }
            break;
            
        case R_TYPE_DOUBLE_NA:
            result->type = R_TYPE_DOUBLE_NA;
            if (sexp_type == REALSXP) {
                result->value.double_vec.len = len;
                result->value.double_vec.data = malloc(len * sizeof(double));
                memcpy(result->value.double_vec.data, REAL(sexp), len * sizeof(double));
            } else if (sexp_type == INTSXP) {
                result->value.double_vec.len = len;
                result->value.double_vec.data = malloc(len * sizeof(double));
                for (int i = 0; i < len; i++) {
                    int val = INTEGER(sexp)[i];
                    result->value.double_vec.data[i] = (val == NA_INTEGER) ? NA_REAL : (double)val;
                }
            } else {
                result->type = R_TYPE_ERROR;
                snprintf(result->error_msg, sizeof(result->error_msg),
                         "Expected double(NA), got type %d", sexp_type);
            }
            break;
            
        case R_TYPE_INTEGER_NA:
            result->type = R_TYPE_INTEGER_NA;
            if (sexp_type == INTSXP) {
                result->value.int_vec.len = len;
                result->value.int_vec.data = malloc(len * sizeof(int));
                memcpy(result->value.int_vec.data, INTEGER(sexp), len * sizeof(int));
            } else {
                result->type = R_TYPE_ERROR;
                snprintf(result->error_msg, sizeof(result->error_msg),
                         "Expected integer(NA), got type %d", sexp_type);
            }
            break;
            
        case R_TYPE_LOGICAL_NA:
            result->type = R_TYPE_LOGICAL_NA;
            if (sexp_type == LGLSXP) {
                result->value.logical_vec.len = len;
                result->value.logical_vec.data = malloc(len * sizeof(int));
                memcpy(result->value.logical_vec.data, LOGICAL(sexp), len * sizeof(int));
            } else {
                result->type = R_TYPE_ERROR;
                snprintf(result->error_msg, sizeof(result->error_msg),
                         "Expected logical(NA), got type %d", sexp_type);
            }
            break;
            
        case R_TYPE_CHARACTER_NA:
            result->type = R_TYPE_CHARACTER_NA;
            if (sexp_type == STRSXP) {
                result->value.string_vec.len = len;
                result->value.string_vec.data = malloc(len * sizeof(char*));
                for (int i = 0; i < len; i++) {
                    SEXP str = STRING_ELT(sexp, i);
                    if (str == NA_STRING) {
                        result->value.string_vec.data[i] = NULL;
                    } else {
                        result->value.string_vec.data[i] = strdup(CHAR(str));
                    }
                }
            } else {
                result->type = R_TYPE_ERROR;
                snprintf(result->error_msg, sizeof(result->error_msg),
                         "Expected character(NA), got type %d", sexp_type);
            }
            break;
            
        case R_TYPE_RAW_NA:
            result->type = R_TYPE_RAW_NA;
            if (sexp_type == RAWSXP) {
                result->value.raw.len = len;
                result->value.raw.data = malloc(len);
                memcpy(result->value.raw.data, RAW(sexp), len);
            } else {
                result->type = R_TYPE_ERROR;
                snprintf(result->error_msg, sizeof(result->error_msg),
                         "Expected raw(NA), got type %d", sexp_type);
            }
            break;
            
        default:
            // Auto-detect type
            if (sexp_type == REALSXP && len == 1) {
                result->type = R_TYPE_DOUBLE_1;
                double val = REAL(sexp)[0];
                if (ISNA(val) || ISNAN(val)) {
                    result->is_na = 1;
                } else {
                    result->value.double_val = val;
                }
            } else if (sexp_type == INTSXP && len == 1) {
                result->type = R_TYPE_INTEGER_1;
                int val = INTEGER(sexp)[0];
                if (val == NA_INTEGER) {
                    result->is_na = 1;
                } else {
                    result->value.int_val = val;
                }
            } else if (sexp_type == LGLSXP && len == 1) {
                result->type = R_TYPE_LOGICAL_1;
                int val = LOGICAL(sexp)[0];
                if (val == NA_LOGICAL) {
                    result->is_na = 1;
                } else {
                    result->value.logical_val = val;
                }
            } else if (sexp_type == STRSXP && len == 1) {
                result->type = R_TYPE_CHARACTER_1;
                SEXP str = STRING_ELT(sexp, 0);
                if (str == NA_STRING) {
                    result->is_na = 1;
                } else {
                    result->value.string_val = strdup(CHAR(str));
                }
            } else {
                // Fall back to string representation
                result->type = R_TYPE_CHARACTER_1;
                char buf[64];
                snprintf(buf, sizeof(buf), "<R:%d len=%d>", sexp_type, len);
                result->value.string_val = strdup(buf);
            }
            break;
    }
}

// Inner callback for R_ToplevelExec - evaluates R code with optional .x
static void r_eval_inner_callback(void* data) {
    r_eval_callback_data_t* cb = (r_eval_callback_data_t*)data;
    r_result_t* result = cb->result;
    
    memset(result, 0, sizeof(r_result_t));
    result->type = R_TYPE_NULL;
    
    // Set up .x if provided
    if (cb->x_val != 0.0 || cb->x_is_null || cb->x_str) {
        if (cb->x_str) {
            // String .x
            if (cb->x_is_null) {
                Rf_defineVar(Rf_install(".x"), R_NaString, R_GlobalEnv);
            } else {
                SEXP x_val = PROTECT(Rf_mkString(cb->x_str));
                Rf_defineVar(Rf_install(".x"), x_val, R_GlobalEnv);
                UNPROTECT(1);
            }
        } else {
            // Numeric .x
            if (cb->x_is_null) {
                SEXP na_val = PROTECT(Rf_ScalarReal(NA_REAL));
                Rf_defineVar(Rf_install(".x"), na_val, R_GlobalEnv);
                UNPROTECT(1);
            } else {
                SEXP x_val = PROTECT(Rf_ScalarReal(cb->x_val));
                Rf_defineVar(Rf_install(".x"), x_val, R_GlobalEnv);
                UNPROTECT(1);
            }
        }
    }
    
    // Parse R code
    ParseStatus parse_status;
    SEXP code_str = PROTECT(Rf_mkString(cb->r_code));
    SEXP parsed = PROTECT(R_ParseVector(code_str, -1, &parse_status, R_NilValue));
    
    if (parse_status != PARSE_OK || TYPEOF(parsed) != EXPRSXP) {
        result->type = R_TYPE_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "Parse error in: %.100s", cb->r_code);
        UNPROTECT(2);
        return;
    }
    
    // Evaluate each expression
    int error = 0;
    SEXP sexp_result = R_NilValue;
    
    for (int i = 0; i < Rf_length(parsed); i++) {
        sexp_result = R_tryEval(VECTOR_ELT(parsed, i), R_GlobalEnv, &error);
        if (error) {
            result->type = R_TYPE_ERROR;
            snprintf(result->error_msg, sizeof(result->error_msg), "Eval error in: %.100s", cb->r_code);
            UNPROTECT(2);
            return;
        }
    }
    
    // Protect result before accessing
    PROTECT(sexp_result);
    
    // Convert to typed result
    sexp_to_result(sexp_result, cb->expected_type, result);
    
    UNPROTECT(3);
}

// =============================================================================
// Process a Single Request (called on main thread)
// =============================================================================

static void process_request(r_request_t* req) {
    if (!req) return;
    
    // Mark that we're in an R call (re-entrance guard)
    atomic_store(&g_in_r_call, 1);
    
    r_eval_callback_data_t cb_data = {0};
    cb_data.r_code = req->r_code;
    cb_data.result = &req->result;
    cb_data.expected_type = req->expected_type;
    
    // Set up .x parameter if applicable
    if (req->req_type == R_REQ_EVAL_WITH_X) {
        cb_data.x_val = req->x_param.x_double.val;
        cb_data.x_is_null = req->x_param.x_double.is_null;
    } else if (req->req_type == R_REQ_EVAL_WITH_STR) {
        cb_data.x_str = req->x_param.x_string.val;
        cb_data.x_is_null = req->x_param.x_string.is_null;
    }
    
    // Execute with longjmp protection
    Rboolean success = R_ToplevelExec(r_eval_inner_callback, &cb_data);
    
    if (!success) {
        req->result.type = R_TYPE_ERROR;
        snprintf(req->result.error_msg, sizeof(req->result.error_msg),
                 "R_ToplevelExec failed (longjmp)");
    }
    
    atomic_store(&g_in_r_call, 0);
    
    // Signal completion
    pthread_mutex_lock(&req->mutex);
    atomic_store(&req->completed, 1);
    pthread_cond_signal(&req->cond);
    pthread_mutex_unlock(&req->mutex);
}

// =============================================================================
// Channel Processing - Called from main R thread to receive/process requests
// =============================================================================

static atomic_int g_main_thread_calls = ATOMIC_VAR_INIT(0);
static atomic_int g_worker_thread_calls = ATOMIC_VAR_INIT(0);
static atomic_int g_chan_processed = ATOMIC_VAR_INIT(0);

/**
 * Process all pending requests from the channel.
 * Called on main R thread - tries to receive without blocking.
 */
static void process_pending_requests(void) {
    if (!is_main_thread()) return;
    if (!atomic_load(&g_chan_initialized)) return;
    
    // Drain the signal pipe
    r_chan_drain_signal(&g_request_chan);
    
    // Process all pending requests from other threads
    r_request_t* req = NULL;
    while (r_chan_try_recv(&g_request_chan, (void**)&req) == 0) {
        process_request(req);
        atomic_fetch_add(&g_chan_processed, 1);
    }
}

// =============================================================================
// Input Handler - Called by R event loop when channel's signal pipe is readable
// This fires on the MAIN R thread when:
// 1. R is in its event loop (interactive mode)
// 2. R_CheckUserInterrupt is called (e.g., by duckdb during long queries)
// 3. Sys.sleep or other blocking R calls that process events
// =============================================================================

#ifndef _WIN32
static void input_handler_callback(void* data) {
    (void)data;
    process_pending_requests();
}
#endif

// =============================================================================
// Public API: Submit R Evaluation Request
//
// Architecture:
// - Main thread: execute directly AND drain pending worker requests
// - Worker threads: send request via channel, wait on per-request condvar
// - Main thread input handler: receives from channel, processes, signals completion
//
// Workers NEVER call any R API functions - only send to channel and wait!
// =============================================================================

static int r_eval_submit(r_request_t* req) {
    static atomic_int call_count = ATOMIC_VAR_INIT(0);
    int my_call = atomic_fetch_add(&call_count, 1) + 1;
    
    if (!atomic_load(&g_initialized)) {
        req->result.type = R_TYPE_ERROR;
        snprintf(req->result.error_msg, sizeof(req->result.error_msg),
                 "R UDF not initialized - call r_init() first");
        return -1;
    }
    
    if (is_main_thread()) {
        DEBUG_LOG("call %d: main thread, processing", my_call);
        atomic_fetch_add(&g_main_thread_calls, 1);
        
        // First, drain any pending requests from workers via channel
        process_pending_requests();
        
        // Then execute our own request directly
        process_request(req);
        DEBUG_LOG("call %d: main thread done", my_call);
        return 0;
    }
    
    // --- Worker thread path ---
    DEBUG_LOG("call %d: worker thread, sending to channel", my_call);
    atomic_fetch_add(&g_worker_thread_calls, 1);
    
    // Send request to channel (this will signal the main thread via pipe)
    // The channel blocks until the main thread receives
    int send_rc = r_chan_send(&g_request_chan, req, R_CHAN_NO_TIMEOUT);
    
    if (send_rc != 0) {
        req->result.type = R_TYPE_ERROR;
        snprintf(req->result.error_msg, sizeof(req->result.error_msg),
                 "Channel send failed: %s", 
                 send_rc == EPIPE ? "channel closed" : "unknown error");
        return -1;
    }
    
    DEBUG_LOG("call %d: worker waiting for completion", my_call);
    // Request has been handed off - now wait for completion
    // The main thread will call process_request() which signals req->cond
    pthread_mutex_lock(&req->mutex);
    
    int attempts = 0;
    const int max_attempts = 30000; // 30000 * 10ms = 5 minutes max
    
    while (!atomic_load(&req->completed)) {
        // Short timeout so we can check for errors
        struct timespec timeout;
        clock_gettime(CLOCK_REALTIME, &timeout);
        timeout.tv_nsec += 10000000; // 10ms
        if (timeout.tv_nsec >= 1000000000) {
            timeout.tv_nsec -= 1000000000;
            timeout.tv_sec += 1;
        }
        
        pthread_cond_timedwait(&req->cond, &req->mutex, &timeout);
        
        attempts++;
        if (attempts % 100 == 0) {
            DEBUG_LOG("call %d: still waiting, attempts=%d", my_call, attempts);
        }
        if (attempts >= max_attempts) {
            pthread_mutex_unlock(&req->mutex);
            req->result.type = R_TYPE_ERROR;
            snprintf(req->result.error_msg, sizeof(req->result.error_msg),
                     "Timeout waiting for R evaluation");
            return -1;
        }
    }
    pthread_mutex_unlock(&req->mutex);
    
    DEBUG_LOG("call %d: worker completed", my_call);
    return (req->result.type == R_TYPE_ERROR) ? -1 : 0;
}

// =============================================================================
// Convenience Wrappers
// =============================================================================

// Evaluate R code and return typed result
static int r_eval_typed(const char* r_code, r_type_t expected, r_result_t* result) {
    r_request_t* req = request_create(R_REQ_EVAL_TYPED, r_code);
    if (!req) {
        result->type = R_TYPE_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "Failed to allocate request");
        return -1;
    }
    
    req->expected_type = expected;
    int rc = r_eval_submit(req);
    
    // Copy result
    *result = req->result;
    memset(&req->result, 0, sizeof(r_result_t)); // Prevent double-free
    request_destroy(req);
    
    return rc;
}

// Evaluate with numeric .x
static int r_eval_with_x(const char* r_code, double x_val, int x_is_null, 
                          r_type_t expected, r_result_t* result) {
    r_request_t* req = request_create(R_REQ_EVAL_WITH_X, r_code);
    if (!req) {
        result->type = R_TYPE_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "Failed to allocate request");
        return -1;
    }
    
    req->expected_type = expected;
    req->x_param.x_double.val = x_val;
    req->x_param.x_double.is_null = x_is_null;
    
    int rc = r_eval_submit(req);
    *result = req->result;
    memset(&req->result, 0, sizeof(r_result_t));
    request_destroy(req);
    
    return rc;
}

// Evaluate with string .x
static int r_eval_with_str(const char* r_code, const char* x_str, int x_is_null,
                            r_type_t expected, r_result_t* result) {
    r_request_t* req = request_create(R_REQ_EVAL_WITH_STR, r_code);
    if (!req) {
        result->type = R_TYPE_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "Failed to allocate request");
        return -1;
    }
    
    req->expected_type = expected;
    req->x_param.x_string.val = x_str ? strdup(x_str) : NULL;
    req->x_param.x_string.is_null = x_is_null;
    
    int rc = r_eval_submit(req);
    *result = req->result;
    memset(&req->result, 0, sizeof(r_result_t));
    request_destroy(req);
    
    return rc;
}

// =============================================================================
// Initialization
// =============================================================================

static int r_udf_init_internal(void) {
    if (atomic_load(&g_initialized)) {
        return 0; // Already initialized
    }
    
    // Initialize the request channel
    if (r_chan_init(&g_request_chan) != 0) {
        return -1;
    }
    atomic_store(&g_chan_initialized, 1);
    
#ifndef _WIN32
    // Initialize the channel's signal pipe (for R event loop integration)
    int signal_fd = r_chan_init_signal_pipe(&g_request_chan);
    if (signal_fd < 0) {
        r_chan_cleanup(&g_request_chan);
        atomic_store(&g_chan_initialized, 0);
        return -1;
    }
    
    // Register R input handler on the channel's signal pipe
    g_input_handler = addInputHandler(R_InputHandlers, signal_fd,
                                       input_handler_callback, 31);
    if (!g_input_handler) {
        r_chan_cleanup(&g_request_chan);
        atomic_store(&g_chan_initialized, 0);
        return -1;
    }
#endif
    
    // Record main thread ID
    g_main_thread_id = pthread_self();
    atomic_store(&g_initialized, 1);
    
    return 0;
}

// =============================================================================
// DuckDB UDF Declarations using Macros
// =============================================================================

// Helper to extract DuckDB string
static char* duckdb_string_extract(duckdb_string_t* s) {
    if (s->value.inlined.length <= 12) {
        return strndup(s->value.inlined.inlined, s->value.inlined.length);
    }
    return strndup(s->value.pointer.ptr, s->value.pointer.length);
}

// =============================================================================
// Table Function: r_init() -> (status VARCHAR, platform VARCHAR)
// =============================================================================

static void r_init_bind(duckdb_bind_info info) {
    duckdb_bind_add_result_column(info, "status", 
        duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR));
    duckdb_bind_add_result_column(info, "platform",
        duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR));
    duckdb_bind_set_bind_data(info, NULL, NULL);
}

typedef struct { int initialized; } r_init_state_t;

static void r_init_init(duckdb_init_info info) {
    r_init_state_t* state = malloc(sizeof(r_init_state_t));
    state->initialized = 0;
    duckdb_init_set_init_data(info, state, free);
}

static void r_init_func(duckdb_function_info info, duckdb_data_chunk output) {
    r_init_state_t* state = duckdb_function_get_init_data(info);
    
    if (state->initialized) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    int rc = r_udf_init_internal();
    
    duckdb_vector status_vec = duckdb_data_chunk_get_vector(output, 0);
    duckdb_vector platform_vec = duckdb_data_chunk_get_vector(output, 1);
    
    const char* status = (rc == 0) ? "initialized" : "failed";
    duckdb_vector_assign_string_element(status_vec, 0, status);
    
#ifdef _WIN32
    duckdb_vector_assign_string_element(platform_vec, 0, "windows");
#else
    duckdb_vector_assign_string_element(platform_vec, 0, "unix");
#endif
    
    duckdb_data_chunk_set_size(output, 1);
    state->initialized = 1;
}

// =============================================================================
// Table Function: r_status() -> (initialized BOOLEAN, platform VARCHAR, ...)
// =============================================================================

static void r_status_bind(duckdb_bind_info info) {
    duckdb_bind_add_result_column(info, "initialized",
        duckdb_create_logical_type(DUCKDB_TYPE_BOOLEAN));
    duckdb_bind_add_result_column(info, "platform",
        duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR));
    duckdb_bind_add_result_column(info, "main_thread_calls",
        duckdb_create_logical_type(DUCKDB_TYPE_INTEGER));
    duckdb_bind_add_result_column(info, "worker_thread_calls",
        duckdb_create_logical_type(DUCKDB_TYPE_INTEGER));
    duckdb_bind_add_result_column(info, "chan_processed",
        duckdb_create_logical_type(DUCKDB_TYPE_INTEGER));
    duckdb_bind_set_bind_data(info, NULL, NULL);
}

static void r_status_func(duckdb_function_info info, duckdb_data_chunk output) {
    static int done = 0;
    if (done) {
        duckdb_data_chunk_set_size(output, 0);
        done = 0;
        return;
    }
    
    duckdb_vector init_vec = duckdb_data_chunk_get_vector(output, 0);
    duckdb_vector plat_vec = duckdb_data_chunk_get_vector(output, 1);
    duckdb_vector main_vec = duckdb_data_chunk_get_vector(output, 2);
    duckdb_vector worker_vec = duckdb_data_chunk_get_vector(output, 3);
    duckdb_vector chan_vec = duckdb_data_chunk_get_vector(output, 4);
    
    bool* init_data = duckdb_vector_get_data(init_vec);
    init_data[0] = atomic_load(&g_initialized);
    
#ifdef _WIN32
    duckdb_vector_assign_string_element(plat_vec, 0, "windows");
#else
    duckdb_vector_assign_string_element(plat_vec, 0, "unix (r_chan)");
#endif
    
    int32_t* main_data = duckdb_vector_get_data(main_vec);
    main_data[0] = atomic_load(&g_main_thread_calls);
    
    int32_t* worker_data = duckdb_vector_get_data(worker_vec);
    worker_data[0] = atomic_load(&g_worker_thread_calls);
    
    int32_t* chan_data = duckdb_vector_get_data(chan_vec);
    chan_data[0] = atomic_load(&g_chan_processed);
    
    duckdb_data_chunk_set_size(output, 1);
    done = 1;
}

// =============================================================================
// Table Function: r_eval(code) -> (result VARCHAR)
// Declare: r_eval(code = character(1)) -> character(1)
// =============================================================================

typedef struct { char* code; int done; } r_eval_data_t;

static void r_eval_bind(duckdb_bind_info info) {
    duckdb_value val = duckdb_bind_get_parameter(info, 0);
    r_eval_data_t* data = malloc(sizeof(r_eval_data_t));
    data->code = strdup(duckdb_get_varchar(val));
    data->done = 0;
    duckdb_destroy_value(&val);
    
    duckdb_bind_add_result_column(info, "result",
        duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR));
    duckdb_bind_set_bind_data(info, data, free);
}

static void r_eval_func(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_data_t* data = duckdb_function_get_bind_data(info);
    
    if (data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    r_result_t result;
    r_eval_typed(data->code, R_TYPE_CHARACTER_1, &result);
    
    duckdb_vector vec = duckdb_data_chunk_get_vector(output, 0);
    
    if (result.type == R_TYPE_ERROR) {
        duckdb_vector_assign_string_element(vec, 0, result.error_msg);
    } else if (result.is_na) {
        duckdb_vector_ensure_validity_writable(vec);
        duckdb_validity_set_row_invalid(duckdb_vector_get_validity(vec), 0);
    } else if (result.value.string_val) {
        duckdb_vector_assign_string_element(vec, 0, result.value.string_val);
    } else {
        duckdb_vector_assign_string_element(vec, 0, "");
    }
    
    r_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    data->done = 1;
}

// =============================================================================
// Table Function: r_double(code) -> (value DOUBLE)
// Declare: r_double(code = character(1)) -> double(1)
// =============================================================================

static void r_double_bind(duckdb_bind_info info) {
    duckdb_value val = duckdb_bind_get_parameter(info, 0);
    r_eval_data_t* data = malloc(sizeof(r_eval_data_t));
    data->code = strdup(duckdb_get_varchar(val));
    data->done = 0;
    duckdb_destroy_value(&val);
    
    duckdb_bind_add_result_column(info, "value",
        duckdb_create_logical_type(DUCKDB_TYPE_DOUBLE));
    duckdb_bind_set_bind_data(info, data, free);
}

static void r_double_func(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_data_t* data = duckdb_function_get_bind_data(info);
    
    if (data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    r_result_t result;
    r_eval_typed(data->code, R_TYPE_DOUBLE_1, &result);
    
    duckdb_vector vec = duckdb_data_chunk_get_vector(output, 0);
    double* out = duckdb_vector_get_data(vec);
    
    if (result.type == R_TYPE_ERROR) {
        duckdb_function_set_error(info, result.error_msg);
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    if (result.is_na) {
        duckdb_vector_ensure_validity_writable(vec);
        duckdb_validity_set_row_invalid(duckdb_vector_get_validity(vec), 0);
    } else {
        out[0] = result.value.double_val;
    }
    
    r_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    data->done = 1;
}

// =============================================================================
// Table Function: r_int(code) -> (value INTEGER)
// Declare: r_int(code = character(1)) -> integer(1)
// =============================================================================

static void r_int_bind(duckdb_bind_info info) {
    duckdb_value val = duckdb_bind_get_parameter(info, 0);
    r_eval_data_t* data = malloc(sizeof(r_eval_data_t));
    data->code = strdup(duckdb_get_varchar(val));
    data->done = 0;
    duckdb_destroy_value(&val);
    
    duckdb_bind_add_result_column(info, "value",
        duckdb_create_logical_type(DUCKDB_TYPE_INTEGER));
    duckdb_bind_set_bind_data(info, data, free);
}

static void r_int_func(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_data_t* data = duckdb_function_get_bind_data(info);
    
    if (data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    r_result_t result;
    r_eval_typed(data->code, R_TYPE_INTEGER_1, &result);
    
    duckdb_vector vec = duckdb_data_chunk_get_vector(output, 0);
    int32_t* out = duckdb_vector_get_data(vec);
    
    if (result.type == R_TYPE_ERROR) {
        duckdb_function_set_error(info, result.error_msg);
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    if (result.is_na) {
        duckdb_vector_ensure_validity_writable(vec);
        duckdb_validity_set_row_invalid(duckdb_vector_get_validity(vec), 0);
    } else {
        out[0] = result.value.int_val;
    }
    
    r_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    data->done = 1;
}

// =============================================================================
// Table Function: r_bool(code) -> (value BOOLEAN)
// Declare: r_bool(code = character(1)) -> logical(1)
// =============================================================================

static void r_bool_bind(duckdb_bind_info info) {
    duckdb_value val = duckdb_bind_get_parameter(info, 0);
    r_eval_data_t* data = malloc(sizeof(r_eval_data_t));
    data->code = strdup(duckdb_get_varchar(val));
    data->done = 0;
    duckdb_destroy_value(&val);
    
    duckdb_bind_add_result_column(info, "value",
        duckdb_create_logical_type(DUCKDB_TYPE_BOOLEAN));
    duckdb_bind_set_bind_data(info, data, free);
}

static void r_bool_func(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_data_t* data = duckdb_function_get_bind_data(info);
    
    if (data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    r_result_t result;
    r_eval_typed(data->code, R_TYPE_LOGICAL_1, &result);
    
    duckdb_vector vec = duckdb_data_chunk_get_vector(output, 0);
    bool* out = duckdb_vector_get_data(vec);
    
    if (result.type == R_TYPE_ERROR) {
        duckdb_function_set_error(info, result.error_msg);
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    if (result.is_na) {
        duckdb_vector_ensure_validity_writable(vec);
        duckdb_validity_set_row_invalid(duckdb_vector_get_validity(vec), 0);
    } else {
        out[0] = result.value.logical_val;
    }
    
    r_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    data->done = 1;
}

// =============================================================================
// Scalar Function: rx(expr, x) -> DOUBLE
// Declare: rx(expr = character(1), x = double(1)) -> double(1)
// =============================================================================

static void rx_scalar_func(duckdb_function_info info, duckdb_data_chunk input,
                           duckdb_vector output) {
    // If we're on main thread, drain pending requests from workers FIRST
    // This is critical for preventing deadlock
    if (is_main_thread()) {
        process_pending_requests();
    }
    
    idx_t count = duckdb_data_chunk_get_size(input);
    
    duckdb_vector expr_vec = duckdb_data_chunk_get_vector(input, 0);
    duckdb_vector x_vec = duckdb_data_chunk_get_vector(input, 1);
    
    duckdb_string_t* expr_data = duckdb_vector_get_data(expr_vec);
    double* x_data = duckdb_vector_get_data(x_vec);
    double* out_data = duckdb_vector_get_data(output);
    
    uint64_t* expr_validity = duckdb_vector_get_validity(expr_vec);
    uint64_t* x_validity = duckdb_vector_get_validity(x_vec);
    
    // Get expression (assumed constant)
    char* expr_str = NULL;
    if (count > 0 && duckdb_validity_row_is_valid(expr_validity, 0)) {
        expr_str = duckdb_string_extract(&expr_data[0]);
    }
    
    if (!expr_str) {
        duckdb_scalar_function_set_error(info, "rx: expression is NULL");
        return;
    }
    
    duckdb_vector_ensure_validity_writable(output);
    uint64_t* out_validity = duckdb_vector_get_validity(output);
    
    for (idx_t i = 0; i < count; i++) {
        int x_is_null = !duckdb_validity_row_is_valid(x_validity, i);
        double x_val = x_is_null ? 0.0 : x_data[i];
        
        r_result_t result;
        r_eval_with_x(expr_str, x_val, x_is_null, R_TYPE_DOUBLE_1, &result);
        
        if (result.type == R_TYPE_ERROR) {
            // Report error and abort
            duckdb_scalar_function_set_error(info, result.error_msg);
            free(expr_str);
            return;
        }
        
        if (result.is_na || result.type == R_TYPE_NULL) {
            duckdb_validity_set_row_invalid(out_validity, i);
        } else {
            out_data[i] = result.value.double_val;
        }
        
        r_result_free(&result);
    }
    
    free(expr_str);
}

// =============================================================================
// Scalar Function: rx_str(expr, x) -> VARCHAR
// Declare: rx_str(expr = character(1), x = character(1)) -> character(1)
// =============================================================================

static void rx_str_scalar_func(duckdb_function_info info, duckdb_data_chunk input,
                               duckdb_vector output) {
    // If we're on main thread, drain pending requests from workers FIRST
    if (is_main_thread()) {
        process_pending_requests();
    }
    
    idx_t count = duckdb_data_chunk_get_size(input);
    
    duckdb_vector expr_vec = duckdb_data_chunk_get_vector(input, 0);
    duckdb_vector x_vec = duckdb_data_chunk_get_vector(input, 1);
    
    duckdb_string_t* expr_data = duckdb_vector_get_data(expr_vec);
    duckdb_string_t* x_data = duckdb_vector_get_data(x_vec);
    
    uint64_t* expr_validity = duckdb_vector_get_validity(expr_vec);
    uint64_t* x_validity = duckdb_vector_get_validity(x_vec);
    
    char* expr_str = NULL;
    if (count > 0 && duckdb_validity_row_is_valid(expr_validity, 0)) {
        expr_str = duckdb_string_extract(&expr_data[0]);
    }
    
    if (!expr_str) {
        duckdb_scalar_function_set_error(info, "rx_str: expression is NULL");
        return;
    }
    
    duckdb_vector_ensure_validity_writable(output);
    uint64_t* out_validity = duckdb_vector_get_validity(output);
    
    for (idx_t i = 0; i < count; i++) {
        int x_is_null = !duckdb_validity_row_is_valid(x_validity, i);
        char* x_str = x_is_null ? NULL : duckdb_string_extract(&x_data[i]);
        
        r_result_t result;
        r_eval_with_str(expr_str, x_str, x_is_null, R_TYPE_CHARACTER_1, &result);
        
        if (x_str) free(x_str);
        
        if (result.type == R_TYPE_ERROR) {
            duckdb_scalar_function_set_error(info, result.error_msg);
            free(expr_str);
            return;
        }
        
        if (result.is_na || result.type == R_TYPE_NULL) {
            duckdb_validity_set_row_invalid(out_validity, i);
        } else if (result.value.string_val) {
            duckdb_vector_assign_string_element(output, i, result.value.string_val);
        }
        
        r_result_free(&result);
    }
    
    free(expr_str);
}

// =============================================================================
// Extension Registration
// =============================================================================

static void register_all_functions(duckdb_connection conn) {
    duckdb_logical_type varchar_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    duckdb_logical_type double_type = duckdb_create_logical_type(DUCKDB_TYPE_DOUBLE);
    
    // r_init()
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_init");
        duckdb_table_function_set_bind(func, r_init_bind);
        duckdb_table_function_set_init(func, r_init_init);
        duckdb_table_function_set_function(func, r_init_func);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // r_status()
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_status");
        duckdb_table_function_set_bind(func, r_status_bind);
        duckdb_table_function_set_init(func, r_init_init);
        duckdb_table_function_set_function(func, r_status_func);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // r_eval(code)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_eval");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_eval_bind);
        duckdb_table_function_set_init(func, r_init_init);
        duckdb_table_function_set_function(func, r_eval_func);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // r_double(code)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_double");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_double_bind);
        duckdb_table_function_set_init(func, r_init_init);
        duckdb_table_function_set_function(func, r_double_func);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // r_int(code)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_int");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_int_bind);
        duckdb_table_function_set_init(func, r_init_init);
        duckdb_table_function_set_function(func, r_int_func);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // r_bool(code)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_bool");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_bool_bind);
        duckdb_table_function_set_init(func, r_init_init);
        duckdb_table_function_set_function(func, r_bool_func);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // rx(expr, x) -> DOUBLE scalar
    {
        duckdb_scalar_function func = duckdb_create_scalar_function();
        duckdb_scalar_function_set_name(func, "rx");
        duckdb_scalar_function_add_parameter(func, varchar_type);
        duckdb_scalar_function_add_parameter(func, double_type);
        duckdb_scalar_function_set_return_type(func, double_type);
        duckdb_scalar_function_set_function(func, rx_scalar_func);
        duckdb_scalar_function_set_volatile(func);
        duckdb_register_scalar_function(conn, func);
        duckdb_destroy_scalar_function(&func);
    }
    
    // rx_str(expr, x) -> VARCHAR scalar
    {
        duckdb_scalar_function func = duckdb_create_scalar_function();
        duckdb_scalar_function_set_name(func, "rx_str");
        duckdb_scalar_function_add_parameter(func, varchar_type);
        duckdb_scalar_function_add_parameter(func, varchar_type);
        duckdb_scalar_function_set_return_type(func, varchar_type);
        duckdb_scalar_function_set_function(func, rx_str_scalar_func);
        duckdb_scalar_function_set_volatile(func);
        duckdb_register_scalar_function(conn, func);
        duckdb_destroy_scalar_function(&func);
    }
    
    duckdb_destroy_logical_type(&double_type);
    duckdb_destroy_logical_type(&varchar_type);
}

// =============================================================================
// Extension Entry Point
// =============================================================================

DUCKDB_EXTENSION_ENTRYPOINT(duckdb_connection conn, duckdb_extension_info info,
                            struct duckdb_extension_access *access) {
    (void)info;
    (void)access;
    
    // Auto-initialize on load (we're on R's main thread here)
    r_udf_init_internal();
    
    // Register all functions
    register_all_functions(conn);
    
    return true;
}
