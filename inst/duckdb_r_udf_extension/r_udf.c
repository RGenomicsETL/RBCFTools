/**
 * DuckDB R UDF Extension
 * 
 * A DuckDB extension that allows calling R functions from SQL queries.
 * Uses FD signaling pattern for thread-safe R callbacks from DuckDB worker threads.
 * 
 * Features:
 *   - Thread-safe R execution via pipe-based signaling
 *   - Integration with R's input handler event loop  
 *   - Automatic type conversion between DuckDB and R
 *   - Re-entrance protection
 *   - Works with DuckDB's parallel query execution
 *
 * Usage:
 *   LOAD 'r_udf.duckdb_extension';
 *   SELECT * FROM r_init();  -- Initialize async handler (once per session)
 *   SELECT * FROM r_eval('mean(c(1,2,3))');
 *
 * IMPORTANT: This extension must be loaded from within an R session.
 * The R interpreter must already be running. Call r_init() after loading
 * to enable thread-safe async callbacks.
 *
 * Based on async.c callback pattern by Simon Urbanek for safe R callbacks from C threads.
 *
 * Copyright (c) 2026 RBCFTools Authors
 * Licensed under MIT License
 */

// Must define before including duckdb_extension.h
#define DUCKDB_EXTENSION_NAME r_udf

#include "duckdb_extension.h"

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <pthread.h>
#include <errno.h>

#ifndef _WIN32
#include <unistd.h>
#include <sys/select.h>
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

// Required macro for DuckDB C extensions
DUCKDB_EXTENSION_EXTERN

// =============================================================================
// Async handler state (FD signaling pattern from Simon Urbanek)
// =============================================================================

#define R_UDF_MAX_RESULT_SIZE 8192
#define R_UDF_ACTIVITY_TYPE 42  // Custom activity type for R input handler

// Request types for async R calls
typedef enum {
    R_UDF_REQUEST_EVAL,      // Evaluate R expression string
    R_UDF_REQUEST_SHUTDOWN   // Shutdown the handler
} r_udf_request_type_t;

// Request structure passed via pipe
typedef struct r_udf_request {
    r_udf_request_type_t type;
    char* r_code;            // R code to evaluate (owned by caller)
    char* result;            // Result buffer (owned by caller)
    size_t result_size;      // Size of result buffer
    int error;               // Error flag (set by handler)
    pthread_mutex_t mutex;   // Mutex for completion signaling
    pthread_cond_t cond;     // Condition variable for completion
    int done;                // Completion flag
} r_udf_request_t;

// Global async handler state
static int g_async_initialized = 0;
static int g_in_r_call = 0;  // Re-entrance guard
static pthread_t g_r_main_thread;  // R's main thread ID

#ifndef _WIN32
static int g_request_pipe[2] = {-1, -1};  // [0]=read, [1]=write
static InputHandler* g_input_handler = NULL;
#endif

static pthread_mutex_t g_init_mutex = PTHREAD_MUTEX_INITIALIZER;

// Check if we're running on R's main thread
static int is_r_main_thread(void) {
    return pthread_equal(pthread_self(), g_r_main_thread);
}

// =============================================================================
// Typed R evaluation result
// =============================================================================

typedef enum {
    R_RESULT_NULL,
    R_RESULT_BOOL,
    R_RESULT_INT,
    R_RESULT_DOUBLE,
    R_RESULT_STRING,
    R_RESULT_RAW,           // For R raw vectors (bytes)
    R_RESULT_BOOL_ARRAY,
    R_RESULT_INT_ARRAY,
    R_RESULT_DOUBLE_ARRAY,
    R_RESULT_STRING_ARRAY,
    R_RESULT_ERROR
} r_result_type_t;

typedef struct {
    r_result_type_t type;
    union {
        int bool_val;
        int int_val;
        double double_val;
        char* string_val;
        struct {
            unsigned char* data;
            size_t len;
        } raw;
        struct {
            int* data;
            size_t len;
        } bool_array;
        struct {
            int* data;
            size_t len;
        } int_array;
        struct {
            double* data;
            size_t len;
        } double_array;
        struct {
            char** data;
            size_t len;
        } string_array;
    } value;
    int is_na;
    char error_msg[256];
} r_typed_result_t;

// Free typed result resources
static void r_typed_result_free(r_typed_result_t* res) {
    if (res->type == R_RESULT_STRING && res->value.string_val) {
        free(res->value.string_val);
    } else if (res->type == R_RESULT_RAW && res->value.raw.data) {
        free(res->value.raw.data);
    } else if (res->type == R_RESULT_BOOL_ARRAY && res->value.bool_array.data) {
        free(res->value.bool_array.data);
    } else if (res->type == R_RESULT_INT_ARRAY && res->value.int_array.data) {
        free(res->value.int_array.data);
    } else if (res->type == R_RESULT_DOUBLE_ARRAY && res->value.double_array.data) {
        free(res->value.double_array.data);
    } else if (res->type == R_RESULT_STRING_ARRAY && res->value.string_array.data) {
        for (size_t i = 0; i < res->value.string_array.len; i++) {
            free(res->value.string_array.data[i]);
        }
        free(res->value.string_array.data);
    }
}

// =============================================================================
// R callback execution (runs on main R thread via R_ToplevelExec)
// =============================================================================

typedef struct {
    const char* r_code;
    r_typed_result_t* result;
} r_eval_typed_callback_data_t;

static void r_eval_typed_inner_callback(void* data) {
    r_eval_typed_callback_data_t* eval_data = (r_eval_typed_callback_data_t*)data;
    r_typed_result_t* res = eval_data->result;
    
    // Initialize result
    memset(res, 0, sizeof(r_typed_result_t));
    res->type = R_RESULT_NULL;
    
    // Parse R code
    ParseStatus parse_status;
    SEXP code_str = PROTECT(Rf_mkString(eval_data->r_code));
    SEXP parsed = PROTECT(R_ParseVector(code_str, -1, &parse_status, R_NilValue));
    
    if (parse_status != PARSE_OK || TYPEOF(parsed) != EXPRSXP) {
        res->type = R_RESULT_ERROR;
        snprintf(res->error_msg, sizeof(res->error_msg), "Parse error");
        UNPROTECT(2);
        return;
    }
    
    // Evaluate each expression
    int error = 0;
    SEXP result = R_NilValue;
    
    for (int i = 0; i < Rf_length(parsed); i++) {
        result = R_tryEval(VECTOR_ELT(parsed, i), R_GlobalEnv, &error);
        if (error) {
            res->type = R_RESULT_ERROR;
            snprintf(res->error_msg, sizeof(res->error_msg), "Evaluation error");
            UNPROTECT(2);
            return;
        }
    }
    
    // Convert result to typed representation
    if (result == R_NilValue) {
        res->type = R_RESULT_NULL;
    } else if (TYPEOF(result) == LGLSXP) {
        if (Rf_length(result) == 1) {
            res->type = R_RESULT_BOOL;
            int val = LOGICAL(result)[0];
            if (val == NA_LOGICAL) {
                res->is_na = 1;
            } else {
                res->value.bool_val = val;
            }
        } else {
            // Array of logicals -> bool array
            res->type = R_RESULT_BOOL_ARRAY;
            size_t len = Rf_length(result);
            res->value.bool_array.len = len;
            res->value.bool_array.data = malloc(len * sizeof(int));
            int* lgl = LOGICAL(result);
            for (size_t i = 0; i < len; i++) {
                res->value.bool_array.data[i] = lgl[i];  // Preserves NA_LOGICAL
            }
        }
    } else if (TYPEOF(result) == INTSXP) {
        if (Rf_length(result) == 1) {
            res->type = R_RESULT_INT;
            int val = INTEGER(result)[0];
            if (val == NA_INTEGER) {
                res->is_na = 1;
            } else {
                res->value.int_val = val;
            }
        } else {
            res->type = R_RESULT_INT_ARRAY;
            size_t len = Rf_length(result);
            res->value.int_array.len = len;
            res->value.int_array.data = malloc(len * sizeof(int));
            memcpy(res->value.int_array.data, INTEGER(result), len * sizeof(int));
        }
    } else if (TYPEOF(result) == REALSXP) {
        if (Rf_length(result) == 1) {
            res->type = R_RESULT_DOUBLE;
            double val = REAL(result)[0];
            if (ISNA(val) || ISNAN(val)) {
                res->is_na = 1;
            } else {
                res->value.double_val = val;
            }
        } else {
            res->type = R_RESULT_DOUBLE_ARRAY;
            size_t len = Rf_length(result);
            res->value.double_array.len = len;
            res->value.double_array.data = malloc(len * sizeof(double));
            memcpy(res->value.double_array.data, REAL(result), len * sizeof(double));
        }
    } else if (TYPEOF(result) == STRSXP) {
        if (Rf_length(result) == 1) {
            res->type = R_RESULT_STRING;
            SEXP elem = STRING_ELT(result, 0);
            if (elem == NA_STRING) {
                res->is_na = 1;
            } else {
                res->value.string_val = strdup(CHAR(elem));
            }
        } else {
            res->type = R_RESULT_STRING_ARRAY;
            size_t len = Rf_length(result);
            res->value.string_array.len = len;
            res->value.string_array.data = malloc(len * sizeof(char*));
            for (size_t i = 0; i < len; i++) {
                SEXP elem = STRING_ELT(result, i);
                if (elem == NA_STRING) {
                    res->value.string_array.data[i] = NULL;
                } else {
                    res->value.string_array.data[i] = strdup(CHAR(elem));
                }
            }
        }
    } else if (TYPEOF(result) == RAWSXP) {
        // Raw vector -> BLOB
        res->type = R_RESULT_RAW;
        size_t len = Rf_length(result);
        res->value.raw.len = len;
        if (len > 0) {
            res->value.raw.data = malloc(len);
            memcpy(res->value.raw.data, RAW(result), len);
        } else {
            res->value.raw.data = NULL;
        }
    } else {
        // Unknown type - return as string representation
        res->type = R_RESULT_STRING;
        char buf[256];
        snprintf(buf, sizeof(buf), "<R object: type %d, length %d>", 
                 TYPEOF(result), Rf_length(result));
        res->value.string_val = strdup(buf);
    }
    
    UNPROTECT(2);
}

// Legacy string-only callback for compatibility
typedef struct {
    const char* r_code;
    char* result;
    size_t result_size;
    int error;
} r_eval_callback_data_t;

static void r_eval_inner_callback(void* data) {
    r_eval_callback_data_t* eval_data = (r_eval_callback_data_t*)data;
    
    // Parse R code
    ParseStatus parse_status;
    SEXP code_str = PROTECT(Rf_mkString(eval_data->r_code));
    SEXP parsed = PROTECT(R_ParseVector(code_str, -1, &parse_status, R_NilValue));
    
    if (parse_status != PARSE_OK || TYPEOF(parsed) != EXPRSXP) {
        snprintf(eval_data->result, eval_data->result_size, "PARSE_ERROR");
        eval_data->error = 1;
        UNPROTECT(2);
        return;
    }
    
    // Evaluate each expression
    int error = 0;
    SEXP result = R_NilValue;
    
    for (int i = 0; i < Rf_length(parsed); i++) {
        result = R_tryEval(VECTOR_ELT(parsed, i), R_GlobalEnv, &error);
        if (error) {
            snprintf(eval_data->result, eval_data->result_size, "EVAL_ERROR");
            eval_data->error = 1;
            UNPROTECT(2);
            return;
        }
    }
    
    // Convert result to string representation
    if (result == R_NilValue) {
        snprintf(eval_data->result, eval_data->result_size, "NULL");
    } else if (TYPEOF(result) == STRSXP && Rf_length(result) > 0) {
        snprintf(eval_data->result, eval_data->result_size, "%s", 
                 CHAR(STRING_ELT(result, 0)));
    } else if (TYPEOF(result) == INTSXP && Rf_length(result) > 0) {
        int val = INTEGER(result)[0];
        if (val == NA_INTEGER) {
            snprintf(eval_data->result, eval_data->result_size, "NA");
        } else {
            snprintf(eval_data->result, eval_data->result_size, "%d", val);
        }
    } else if (TYPEOF(result) == REALSXP && Rf_length(result) > 0) {
        double val = REAL(result)[0];
        if (ISNA(val) || ISNAN(val)) {
            snprintf(eval_data->result, eval_data->result_size, "NA");
        } else {
            snprintf(eval_data->result, eval_data->result_size, "%g", val);
        }
    } else if (TYPEOF(result) == LGLSXP && Rf_length(result) > 0) {
        int val = LOGICAL(result)[0];
        if (val == NA_LOGICAL) {
            snprintf(eval_data->result, eval_data->result_size, "NA");
        } else {
            snprintf(eval_data->result, eval_data->result_size, "%s", 
                     val ? "TRUE" : "FALSE");
        }
    } else {
        // For complex types, indicate type
        snprintf(eval_data->result, eval_data->result_size, "<R:%d>", TYPEOF(result));
    }
    
    eval_data->error = 0;
    UNPROTECT(2);
}

// Execute R eval with R_ToplevelExec wrapper and re-entrance protection
static void execute_r_eval(r_udf_request_t* req) {
    if (g_in_r_call) {
        // Re-entrance detected - fail safely
        snprintf(req->result, req->result_size, "REENTRANCE_ERROR");
        req->error = 1;
        return;
    }
    
    g_in_r_call = 1;
    
    r_eval_callback_data_t eval_data;
    eval_data.r_code = req->r_code;
    eval_data.result = req->result;
    eval_data.result_size = req->result_size;
    eval_data.error = 0;
    
    // R_ToplevelExec guarantees return even on R errors/longjmp
    Rboolean success = R_ToplevelExec(r_eval_inner_callback, &eval_data);
    
    if (!success) {
        snprintf(req->result, req->result_size, "R_TOPLEVEL_ERROR");
        req->error = 1;
    } else {
        req->error = eval_data.error;
    }
    
    g_in_r_call = 0;
}

// =============================================================================
// Input handler callback (called by R event loop when pipe has data)
// This runs on the main R thread, triggered by R's event loop
// =============================================================================

#ifndef _WIN32
static void r_udf_input_handler(void* data) {
    (void)data;
    
    // Read request pointer from pipe
    r_udf_request_t* req = NULL;
    ssize_t n = read(g_request_pipe[0], &req, sizeof(req));
    
    if (n != (ssize_t)sizeof(req) || req == NULL) {
        return;  // Invalid read, ignore
    }
    
    // Handle request based on type
    switch (req->type) {
        case R_UDF_REQUEST_EVAL:
            execute_r_eval(req);
            break;
            
        case R_UDF_REQUEST_SHUTDOWN:
            // Just mark as done, no action needed
            break;
    }
    
    // Signal completion to waiting thread
    pthread_mutex_lock(&req->mutex);
    req->done = 1;
    pthread_cond_signal(&req->cond);
    pthread_mutex_unlock(&req->mutex);
}
#endif

// =============================================================================
// Initialize async handler (must be called from R main thread via r_init())
// =============================================================================

static int r_udf_init_async_handler(void) {
    pthread_mutex_lock(&g_init_mutex);
    
    if (g_async_initialized) {
        pthread_mutex_unlock(&g_init_mutex);
        return 0;  // Already initialized
    }
    
    // Capture main R thread ID - this MUST be called from R's main thread
    g_r_main_thread = pthread_self();
    
#ifndef _WIN32
    // Create pipe for request signaling
    if (pipe(g_request_pipe) < 0) {
        pthread_mutex_unlock(&g_init_mutex);
        return -1;
    }
    
    // Register input handler with R's event loop
    // This allows R to process our requests during R_CheckUserInterrupt, etc.
    g_input_handler = addInputHandler(R_InputHandlers, g_request_pipe[0],
                                       r_udf_input_handler, R_UDF_ACTIVITY_TYPE);
    if (g_input_handler == NULL) {
        close(g_request_pipe[0]);
        close(g_request_pipe[1]);
        g_request_pipe[0] = g_request_pipe[1] = -1;
        pthread_mutex_unlock(&g_init_mutex);
        return -1;
    }
#endif
    
    g_async_initialized = 1;
    pthread_mutex_unlock(&g_init_mutex);
    return 0;
}

// =============================================================================
// Submit request and wait for response (called from DuckDB worker threads)
// Uses pipe to signal R main thread, then blocks waiting for completion
// =============================================================================

static int r_udf_submit_async_request(r_udf_request_t* req) {
#ifndef _WIN32
    if (!g_async_initialized || g_request_pipe[1] < 0) {
        return -1;  // Handler not initialized
    }
    
    // Initialize per-request synchronization
    pthread_mutex_init(&req->mutex, NULL);
    pthread_cond_init(&req->cond, NULL);
    req->done = 0;
    
    // Write request pointer to pipe (this triggers R's input handler)
    ssize_t n = write(g_request_pipe[1], &req, sizeof(req));
    if (n != (ssize_t)sizeof(req)) {
        pthread_mutex_destroy(&req->mutex);
        pthread_cond_destroy(&req->cond);
        return -1;
    }
    
    // Block until R thread signals completion
    pthread_mutex_lock(&req->mutex);
    while (!req->done) {
        pthread_cond_wait(&req->cond, &req->mutex);
    }
    pthread_mutex_unlock(&req->mutex);
    
    pthread_mutex_destroy(&req->mutex);
    pthread_cond_destroy(&req->cond);
    
    return 0;
#else
    // Windows: direct execution on current thread
    // TODO: implement Windows message-based signaling if needed
    execute_r_eval(req);
    return 0;
#endif
}

// =============================================================================
// Public API: Evaluate R expression (thread-safe)
// If on main R thread: execute directly
// If on worker thread with async initialized: use pipe signaling
// Otherwise: direct execution (assumes main thread)
// =============================================================================

static int r_udf_eval_string(const char* r_code, char* result, size_t result_size) {
    r_udf_request_t req;
    req.type = R_UDF_REQUEST_EVAL;
    req.r_code = (char*)r_code;
    req.result = result;
    req.result_size = result_size;
    req.error = 0;
    req.done = 0;
    
    // If async is initialized, check if we're on main thread
    if (g_async_initialized) {
        int on_main = is_r_main_thread();

        
        if (on_main) {
            // On main R thread - execute directly, no need for async
            execute_r_eval(&req);
            return req.error ? -1 : 0;
        }
        
        // On worker thread - use async pipe signaling
        if (r_udf_submit_async_request(&req) < 0) {
            snprintf(result, result_size, "ASYNC_SUBMIT_ERROR");
            return -1;
        }
        return req.error ? -1 : 0;
    }
    
    // Async not initialized - direct execution
    // This is safe during extension loading (always on main thread)
    execute_r_eval(&req);
    return req.error ? -1 : 0;
}

// =============================================================================
// DuckDB Table Function: r_eval
// Evaluates arbitrary R expression and returns result (thread-safe)
// =============================================================================

typedef struct {
    char* r_code;
    int done;
} r_eval_bind_data_t;

typedef struct {
    int initialized;
} r_eval_init_data_t;

static void r_eval_bind(duckdb_bind_info info) {
    r_eval_bind_data_t* bind_data = malloc(sizeof(r_eval_bind_data_t));
    
    duckdb_value code_val = duckdb_bind_get_parameter(info, 0);
    bind_data->r_code = strdup(duckdb_get_varchar(code_val));
    duckdb_destroy_value(&code_val);
    bind_data->done = 0;
    
    duckdb_bind_add_result_column(info, "result", duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR));
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_eval_init(duckdb_init_info info) {
    r_eval_init_data_t* init_data = malloc(sizeof(r_eval_init_data_t));
    init_data->initialized = 0;
    duckdb_init_set_init_data(info, init_data, free);
}

static void r_eval_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    // Evaluate R code via thread-safe async mechanism
    char result[R_UDF_MAX_RESULT_SIZE];
    r_udf_eval_string(bind_data->r_code, result, sizeof(result));
    
    duckdb_vector result_vec = duckdb_data_chunk_get_vector(output, 0);
    duckdb_vector_assign_string_element(result_vec, 0, result);
    duckdb_data_chunk_set_size(output, 1);
    
    bind_data->done = 1;
}

// =============================================================================
// Typed R evaluation - execute and return typed result
// =============================================================================

static void execute_r_eval_typed(const char* r_code, r_typed_result_t* result) {
    if (g_in_r_call) {
        result->type = R_RESULT_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "Re-entrance not allowed");
        return;
    }
    
    g_in_r_call = 1;
    
    r_eval_typed_callback_data_t eval_data;
    eval_data.r_code = r_code;
    eval_data.result = result;
    
    Rboolean success = R_ToplevelExec(r_eval_typed_inner_callback, &eval_data);
    
    if (!success) {
        result->type = R_RESULT_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "R_ToplevelExec failed");
    }
    
    g_in_r_call = 0;
}

// =============================================================================
// DuckDB Table Function: r_int - returns INTEGER
// =============================================================================

static void r_int_bind(duckdb_bind_info info) {
    r_eval_bind_data_t* bind_data = malloc(sizeof(r_eval_bind_data_t));
    
    duckdb_value code_val = duckdb_bind_get_parameter(info, 0);
    bind_data->r_code = strdup(duckdb_get_varchar(code_val));
    duckdb_destroy_value(&code_val);
    bind_data->done = 0;
    
    duckdb_bind_add_result_column(info, "value", duckdb_create_logical_type(DUCKDB_TYPE_INTEGER));
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_int_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    r_typed_result_t result;
    execute_r_eval_typed(bind_data->r_code, &result);
    
    duckdb_vector result_vec = duckdb_data_chunk_get_vector(output, 0);
    int32_t* data = duckdb_vector_get_data(result_vec);
    
    if (result.type == R_RESULT_ERROR || result.type == R_RESULT_NULL) {
        duckdb_vector_ensure_validity_writable(result_vec);
        uint64_t* validity = duckdb_vector_get_validity(result_vec);
        duckdb_validity_set_row_invalid(validity, 0);
    } else if (result.is_na) {
        duckdb_vector_ensure_validity_writable(result_vec);
        uint64_t* validity = duckdb_vector_get_validity(result_vec);
        duckdb_validity_set_row_invalid(validity, 0);
    } else if (result.type == R_RESULT_INT) {
        data[0] = result.value.int_val;
    } else if (result.type == R_RESULT_DOUBLE) {
        data[0] = (int32_t)result.value.double_val;
    } else if (result.type == R_RESULT_BOOL) {
        data[0] = result.value.bool_val;
    } else {
        duckdb_vector_ensure_validity_writable(result_vec);
        uint64_t* validity = duckdb_vector_get_validity(result_vec);
        duckdb_validity_set_row_invalid(validity, 0);
    }
    
    r_typed_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// DuckDB Table Function: r_double - returns DOUBLE
// =============================================================================

static void r_double_bind(duckdb_bind_info info) {
    r_eval_bind_data_t* bind_data = malloc(sizeof(r_eval_bind_data_t));
    
    duckdb_value code_val = duckdb_bind_get_parameter(info, 0);
    bind_data->r_code = strdup(duckdb_get_varchar(code_val));
    duckdb_destroy_value(&code_val);
    bind_data->done = 0;
    
    duckdb_bind_add_result_column(info, "value", duckdb_create_logical_type(DUCKDB_TYPE_DOUBLE));
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_double_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    r_typed_result_t result;
    execute_r_eval_typed(bind_data->r_code, &result);
    
    duckdb_vector result_vec = duckdb_data_chunk_get_vector(output, 0);
    double* data = duckdb_vector_get_data(result_vec);
    
    if (result.type == R_RESULT_ERROR || result.type == R_RESULT_NULL) {
        duckdb_vector_ensure_validity_writable(result_vec);
        uint64_t* validity = duckdb_vector_get_validity(result_vec);
        duckdb_validity_set_row_invalid(validity, 0);
    } else if (result.is_na) {
        duckdb_vector_ensure_validity_writable(result_vec);
        uint64_t* validity = duckdb_vector_get_validity(result_vec);
        duckdb_validity_set_row_invalid(validity, 0);
    } else if (result.type == R_RESULT_DOUBLE) {
        data[0] = result.value.double_val;
    } else if (result.type == R_RESULT_INT) {
        data[0] = (double)result.value.int_val;
    } else if (result.type == R_RESULT_BOOL) {
        data[0] = (double)result.value.bool_val;
    } else {
        duckdb_vector_ensure_validity_writable(result_vec);
        uint64_t* validity = duckdb_vector_get_validity(result_vec);
        duckdb_validity_set_row_invalid(validity, 0);
    }
    
    r_typed_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// DuckDB Table Function: r_bool - returns BOOLEAN
// =============================================================================

static void r_bool_bind(duckdb_bind_info info) {
    r_eval_bind_data_t* bind_data = malloc(sizeof(r_eval_bind_data_t));
    
    duckdb_value code_val = duckdb_bind_get_parameter(info, 0);
    bind_data->r_code = strdup(duckdb_get_varchar(code_val));
    duckdb_destroy_value(&code_val);
    bind_data->done = 0;
    
    duckdb_bind_add_result_column(info, "value", duckdb_create_logical_type(DUCKDB_TYPE_BOOLEAN));
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_bool_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    r_typed_result_t result;
    execute_r_eval_typed(bind_data->r_code, &result);
    
    duckdb_vector result_vec = duckdb_data_chunk_get_vector(output, 0);
    bool* data = duckdb_vector_get_data(result_vec);
    
    if (result.type == R_RESULT_ERROR || result.type == R_RESULT_NULL) {
        duckdb_vector_ensure_validity_writable(result_vec);
        uint64_t* validity = duckdb_vector_get_validity(result_vec);
        duckdb_validity_set_row_invalid(validity, 0);
    } else if (result.is_na) {
        duckdb_vector_ensure_validity_writable(result_vec);
        uint64_t* validity = duckdb_vector_get_validity(result_vec);
        duckdb_validity_set_row_invalid(validity, 0);
    } else if (result.type == R_RESULT_BOOL) {
        data[0] = result.value.bool_val != 0;
    } else if (result.type == R_RESULT_INT) {
        data[0] = result.value.int_val != 0;
    } else if (result.type == R_RESULT_DOUBLE) {
        data[0] = result.value.double_val != 0.0;
    } else {
        duckdb_vector_ensure_validity_writable(result_vec);
        uint64_t* validity = duckdb_vector_get_validity(result_vec);
        duckdb_validity_set_row_invalid(validity, 0);
    }
    
    r_typed_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// DuckDB Table Function: r_vector_int - returns INTEGER[] (list of ints)
// =============================================================================

static void r_vector_int_bind(duckdb_bind_info info) {
    r_eval_bind_data_t* bind_data = malloc(sizeof(r_eval_bind_data_t));
    
    duckdb_value code_val = duckdb_bind_get_parameter(info, 0);
    bind_data->r_code = strdup(duckdb_get_varchar(code_val));
    duckdb_destroy_value(&code_val);
    bind_data->done = 0;
    
    // Return a list of integers
    duckdb_logical_type int_type = duckdb_create_logical_type(DUCKDB_TYPE_INTEGER);
    duckdb_logical_type list_type = duckdb_create_list_type(int_type);
    duckdb_bind_add_result_column(info, "values", list_type);
    duckdb_destroy_logical_type(&int_type);
    duckdb_destroy_logical_type(&list_type);
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_vector_int_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    r_typed_result_t result;
    execute_r_eval_typed(bind_data->r_code, &result);
    
    duckdb_vector list_vec = duckdb_data_chunk_get_vector(output, 0);
    duckdb_vector child_vec = duckdb_list_vector_get_child(list_vec);
    
    size_t len = 0;
    int32_t* int_data = NULL;
    
    if (result.type == R_RESULT_INT_ARRAY) {
        len = result.value.int_array.len;
        int_data = result.value.int_array.data;
    } else if (result.type == R_RESULT_INT) {
        len = 1;
    } else if (result.type == R_RESULT_DOUBLE_ARRAY) {
        len = result.value.double_array.len;
    } else if (result.type == R_RESULT_DOUBLE) {
        len = 1;
    }
    
    // Reserve space for child elements
    duckdb_list_vector_reserve(list_vec, len);
    duckdb_list_vector_set_size(list_vec, len);
    
    // Set list entry (offset=0, length=len)
    duckdb_list_entry* list_data = duckdb_vector_get_data(list_vec);
    list_data[0].offset = 0;
    list_data[0].length = len;
    
    // Fill child vector
    int32_t* child_data = duckdb_vector_get_data(child_vec);
    
    if (result.type == R_RESULT_INT_ARRAY && int_data) {
        memcpy(child_data, int_data, len * sizeof(int32_t));
    } else if (result.type == R_RESULT_INT && !result.is_na) {
        child_data[0] = result.value.int_val;
    } else if (result.type == R_RESULT_DOUBLE_ARRAY) {
        for (size_t i = 0; i < len; i++) {
            child_data[i] = (int32_t)result.value.double_array.data[i];
        }
    } else if (result.type == R_RESULT_DOUBLE && !result.is_na) {
        child_data[0] = (int32_t)result.value.double_val;
    }
    
    r_typed_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// DuckDB Table Function: r_vector_double - returns DOUBLE[] 
// =============================================================================

static void r_vector_double_bind(duckdb_bind_info info) {
    r_eval_bind_data_t* bind_data = malloc(sizeof(r_eval_bind_data_t));
    
    duckdb_value code_val = duckdb_bind_get_parameter(info, 0);
    bind_data->r_code = strdup(duckdb_get_varchar(code_val));
    duckdb_destroy_value(&code_val);
    bind_data->done = 0;
    
    duckdb_logical_type double_type = duckdb_create_logical_type(DUCKDB_TYPE_DOUBLE);
    duckdb_logical_type list_type = duckdb_create_list_type(double_type);
    duckdb_bind_add_result_column(info, "values", list_type);
    duckdb_destroy_logical_type(&double_type);
    duckdb_destroy_logical_type(&list_type);
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_vector_double_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    r_typed_result_t result;
    execute_r_eval_typed(bind_data->r_code, &result);
    
    duckdb_vector list_vec = duckdb_data_chunk_get_vector(output, 0);
    duckdb_vector child_vec = duckdb_list_vector_get_child(list_vec);
    
    size_t len = 0;
    
    if (result.type == R_RESULT_DOUBLE_ARRAY) {
        len = result.value.double_array.len;
    } else if (result.type == R_RESULT_INT_ARRAY) {
        len = result.value.int_array.len;
    } else if (result.type == R_RESULT_DOUBLE || result.type == R_RESULT_INT) {
        len = 1;
    }
    
    duckdb_list_vector_reserve(list_vec, len);
    duckdb_list_vector_set_size(list_vec, len);
    
    duckdb_list_entry* list_data = duckdb_vector_get_data(list_vec);
    list_data[0].offset = 0;
    list_data[0].length = len;
    
    double* child_data = duckdb_vector_get_data(child_vec);
    
    if (result.type == R_RESULT_DOUBLE_ARRAY) {
        memcpy(child_data, result.value.double_array.data, len * sizeof(double));
    } else if (result.type == R_RESULT_INT_ARRAY) {
        for (size_t i = 0; i < len; i++) {
            child_data[i] = (double)result.value.int_array.data[i];
        }
    } else if (result.type == R_RESULT_DOUBLE && !result.is_na) {
        child_data[0] = result.value.double_val;
    } else if (result.type == R_RESULT_INT && !result.is_na) {
        child_data[0] = (double)result.value.int_val;
    }
    
    r_typed_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// DuckDB Table Function: r_vector_varchar
// Returns VARCHAR[] from R character vector
// =============================================================================

static void r_vector_varchar_bind(duckdb_bind_info info) {
    r_eval_bind_data_t* bind_data = malloc(sizeof(r_eval_bind_data_t));
    
    duckdb_value code_val = duckdb_bind_get_parameter(info, 0);
    bind_data->r_code = strdup(duckdb_get_varchar(code_val));
    duckdb_destroy_value(&code_val);
    bind_data->done = 0;
    
    // Return a list of strings
    duckdb_logical_type varchar_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    duckdb_logical_type list_type = duckdb_create_list_type(varchar_type);
    duckdb_bind_add_result_column(info, "result", list_type);
    duckdb_destroy_logical_type(&varchar_type);
    duckdb_destroy_logical_type(&list_type);
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_vector_varchar_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    duckdb_vector result_vec = duckdb_data_chunk_get_vector(output, 0);
    
    r_typed_result_t result;
    execute_r_eval_typed(bind_data->r_code, &result);
    
    // Handle error
    if (result.type == R_RESULT_ERROR) {
        duckdb_function_set_error(info, result.error_msg);
        bind_data->done = 1;
        return;
    }
    
    // Determine array size
    size_t len = 0;
    if (result.type == R_RESULT_STRING_ARRAY) {
        len = result.value.string_array.len;
    } else if (result.type == R_RESULT_STRING && !result.is_na) {
        len = 1;
    } else if (result.type == R_RESULT_NULL || result.is_na) {
        len = 0;
    }
    
    // Set up list entry
    duckdb_list_entry* entries = duckdb_vector_get_data(result_vec);
    entries[0].offset = 0;
    entries[0].length = len;
    
    // Reserve and populate child vector
    duckdb_list_vector_reserve(result_vec, len);
    duckdb_list_vector_set_size(result_vec, len);
    duckdb_vector child_vec = duckdb_list_vector_get_child(result_vec);
    
    if (result.type == R_RESULT_STRING_ARRAY) {
        for (size_t i = 0; i < len; i++) {
            if (result.value.string_array.data[i] == NULL) {
                duckdb_vector_ensure_validity_writable(child_vec);
                duckdb_validity_set_row_invalid(
                    duckdb_vector_get_validity(child_vec), i);
            } else {
                duckdb_vector_assign_string_element(child_vec, i, 
                    result.value.string_array.data[i]);
            }
        }
    } else if (result.type == R_RESULT_STRING && !result.is_na) {
        duckdb_vector_assign_string_element(child_vec, 0, result.value.string_val);
    }
    
    r_typed_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// DuckDB Table Function: r_vector_bool
// Returns BOOLEAN[] from R logical vector
// =============================================================================

static void r_vector_bool_bind(duckdb_bind_info info) {
    r_eval_bind_data_t* bind_data = malloc(sizeof(r_eval_bind_data_t));
    
    duckdb_value code_val = duckdb_bind_get_parameter(info, 0);
    bind_data->r_code = strdup(duckdb_get_varchar(code_val));
    duckdb_destroy_value(&code_val);
    bind_data->done = 0;
    
    // Return a list of booleans
    duckdb_logical_type bool_type = duckdb_create_logical_type(DUCKDB_TYPE_BOOLEAN);
    duckdb_logical_type list_type = duckdb_create_list_type(bool_type);
    duckdb_bind_add_result_column(info, "result", list_type);
    duckdb_destroy_logical_type(&bool_type);
    duckdb_destroy_logical_type(&list_type);
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_vector_bool_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    duckdb_vector result_vec = duckdb_data_chunk_get_vector(output, 0);
    
    r_typed_result_t result;
    execute_r_eval_typed(bind_data->r_code, &result);
    
    // Handle error
    if (result.type == R_RESULT_ERROR) {
        duckdb_function_set_error(info, result.error_msg);
        bind_data->done = 1;
        return;
    }
    
    // Determine array size
    size_t len = 0;
    if (result.type == R_RESULT_BOOL_ARRAY) {
        len = result.value.bool_array.len;
    } else if (result.type == R_RESULT_BOOL && !result.is_na) {
        len = 1;
    } else if (result.type == R_RESULT_NULL || result.is_na) {
        len = 0;
    }
    
    // Set up list entry
    duckdb_list_entry* entries = duckdb_vector_get_data(result_vec);
    entries[0].offset = 0;
    entries[0].length = len;
    
    // Reserve and populate child vector
    duckdb_list_vector_reserve(result_vec, len);
    duckdb_list_vector_set_size(result_vec, len);
    duckdb_vector child_vec = duckdb_list_vector_get_child(result_vec);
    
    bool* child_data = duckdb_vector_get_data(child_vec);
    
    if (result.type == R_RESULT_BOOL_ARRAY) {
        for (size_t i = 0; i < len; i++) {
            int val = result.value.bool_array.data[i];
            if (val == NA_LOGICAL) {
                duckdb_vector_ensure_validity_writable(child_vec);
                duckdb_validity_set_row_invalid(
                    duckdb_vector_get_validity(child_vec), i);
            } else {
                child_data[i] = val ? true : false;
            }
        }
    } else if (result.type == R_RESULT_BOOL && !result.is_na) {
        child_data[0] = result.value.bool_val ? true : false;
    }
    
    r_typed_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// DuckDB Table Function: r_raw
// Returns BLOB from R raw vector
// =============================================================================

static void r_raw_bind(duckdb_bind_info info) {
    r_eval_bind_data_t* bind_data = malloc(sizeof(r_eval_bind_data_t));
    
    duckdb_value code_val = duckdb_bind_get_parameter(info, 0);
    bind_data->r_code = strdup(duckdb_get_varchar(code_val));
    duckdb_destroy_value(&code_val);
    bind_data->done = 0;
    
    duckdb_bind_add_result_column(info, "result", 
                                   duckdb_create_logical_type(DUCKDB_TYPE_BLOB));
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_raw_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_eval_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    duckdb_vector result_vec = duckdb_data_chunk_get_vector(output, 0);
    
    r_typed_result_t result;
    execute_r_eval_typed(bind_data->r_code, &result);
    
    // Handle error
    if (result.type == R_RESULT_ERROR) {
        duckdb_function_set_error(info, result.error_msg);
        bind_data->done = 1;
        return;
    }
    
    // Handle NULL
    if (result.type == R_RESULT_NULL || result.is_na) {
        duckdb_vector_ensure_validity_writable(result_vec);
        duckdb_validity_set_row_invalid(
            duckdb_vector_get_validity(result_vec), 0);
        r_typed_result_free(&result);
        duckdb_data_chunk_set_size(output, 1);
        bind_data->done = 1;
        return;
    }
    
    // Handle raw vector
    if (result.type == R_RESULT_RAW) {
        duckdb_vector_assign_string_element_len(result_vec, 0, 
            (const char*)result.value.raw.data, result.value.raw.len);
    } else {
        // Unexpected type - set NULL
        duckdb_vector_ensure_validity_writable(result_vec);
        duckdb_validity_set_row_invalid(
            duckdb_vector_get_validity(result_vec), 0);
    }
    
    r_typed_result_free(&result);
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// DuckDB Table Function: r_init
// Initialize the async handler (call once after loading extension)
// =============================================================================

typedef struct {
    int done;
} r_init_bind_data_t;

static void r_init_bind(duckdb_bind_info info) {
    r_init_bind_data_t* bind_data = malloc(sizeof(r_init_bind_data_t));
    bind_data->done = 0;
    
    duckdb_bind_add_result_column(info, "status", 
                                   duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR));
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_init_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_init_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    duckdb_vector result_vec = duckdb_data_chunk_get_vector(output, 0);
    
    int result = r_udf_init_async_handler();
    if (result == 0 && g_async_initialized) {
        duckdb_vector_assign_string_element(result_vec, 0, 
            "Async handler initialized - thread-safe R calls enabled");
    } else if (result == 0) {
        duckdb_vector_assign_string_element(result_vec, 0, 
            "Handler already initialized");
    } else {
        duckdb_vector_assign_string_element(result_vec, 0, 
            "Initialization failed - check R event loop availability");
    }
    
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// DuckDB Table Function: r_status
// Check the status of the async handler
// =============================================================================

static void r_status_bind(duckdb_bind_info info) {
    r_init_bind_data_t* bind_data = malloc(sizeof(r_init_bind_data_t));
    bind_data->done = 0;
    
    duckdb_bind_add_result_column(info, "async_enabled", 
                                   duckdb_create_logical_type(DUCKDB_TYPE_BOOLEAN));
    duckdb_bind_add_result_column(info, "platform", 
                                   duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR));
    duckdb_bind_set_bind_data(info, bind_data, free);
}

static void r_status_function(duckdb_function_info info, duckdb_data_chunk output) {
    r_init_bind_data_t* bind_data = duckdb_function_get_bind_data(info);
    
    if (bind_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    // async_enabled column
    duckdb_vector async_vec = duckdb_data_chunk_get_vector(output, 0);
    bool* async_data = duckdb_vector_get_data(async_vec);
    async_data[0] = g_async_initialized ? true : false;
    
    // platform column
    duckdb_vector platform_vec = duckdb_data_chunk_get_vector(output, 1);
#ifdef _WIN32
    duckdb_vector_assign_string_element(platform_vec, 0, "windows");
#else
    duckdb_vector_assign_string_element(platform_vec, 0, "unix");
#endif
    
    duckdb_data_chunk_set_size(output, 1);
    bind_data->done = 1;
}

// =============================================================================
// Scalar Function: rx - evaluate R expression with injected .x value
// Supports R's non-standard evaluation pattern: rx('sqrt(.x)', column)
// =============================================================================

// Callback data for R evaluation with injected values
typedef struct {
    const char* r_code;
    double x_val;        // Value to inject as .x
    int x_is_null;       // Whether .x is NULL
    r_typed_result_t* result;
} r_eval_with_x_callback_data_t;

// Inner callback that runs on R thread - injects .x then evaluates
static void r_eval_with_x_inner_callback(void* data) {
    r_eval_with_x_callback_data_t* eval_data = (r_eval_with_x_callback_data_t*)data;
    r_typed_result_t* res = eval_data->result;
    
    memset(res, 0, sizeof(r_typed_result_t));
    res->type = R_RESULT_NULL;
    
    // If input is NULL, return NULL without evaluation
    if (eval_data->x_is_null) {
        res->is_na = 1;
        res->type = R_RESULT_DOUBLE;
        return;
    }
    
    // Inject .x into R global environment
    SEXP x_val = PROTECT(Rf_ScalarReal(eval_data->x_val));
    Rf_defineVar(Rf_install(".x"), x_val, R_GlobalEnv);
    
    // Parse R code
    ParseStatus parse_status;
    SEXP code_str = PROTECT(Rf_mkString(eval_data->r_code));
    SEXP parsed = PROTECT(R_ParseVector(code_str, -1, &parse_status, R_NilValue));
    
    if (parse_status != PARSE_OK || TYPEOF(parsed) != EXPRSXP) {
        res->type = R_RESULT_ERROR;
        snprintf(res->error_msg, sizeof(res->error_msg), "Parse error");
        UNPROTECT(3);
        return;
    }
    
    // Evaluate 
    int error = 0;
    SEXP result = R_NilValue;
    for (int i = 0; i < Rf_length(parsed); i++) {
        result = R_tryEval(VECTOR_ELT(parsed, i), R_GlobalEnv, &error);
        if (error) {
            res->type = R_RESULT_ERROR;
            snprintf(res->error_msg, sizeof(res->error_msg), "Evaluation error");
            UNPROTECT(3);
            return;
        }
    }
    
    // Extract result as double
    if (result == R_NilValue) {
        res->type = R_RESULT_NULL;
    } else if (TYPEOF(result) == REALSXP && Rf_length(result) >= 1) {
        res->type = R_RESULT_DOUBLE;
        double val = REAL(result)[0];
        if (ISNA(val) || ISNAN(val)) {
            res->is_na = 1;
        } else {
            res->value.double_val = val;
        }
    } else if (TYPEOF(result) == INTSXP && Rf_length(result) >= 1) {
        res->type = R_RESULT_DOUBLE;
        int val = INTEGER(result)[0];
        if (val == NA_INTEGER) {
            res->is_na = 1;
        } else {
            res->value.double_val = (double)val;
        }
    } else if (TYPEOF(result) == LGLSXP && Rf_length(result) >= 1) {
        res->type = R_RESULT_DOUBLE;
        int val = LOGICAL(result)[0];
        if (val == NA_LOGICAL) {
            res->is_na = 1;
        } else {
            res->value.double_val = (double)val;
        }
    } else {
        res->type = R_RESULT_ERROR;
        snprintf(res->error_msg, sizeof(res->error_msg), 
                 "rx requires numeric result, got type %d", TYPEOF(result));
    }
    
    UNPROTECT(3);
}

// Execute R eval with .x injection using R_ToplevelExec
static void execute_r_eval_with_x(const char* r_code, double x_val, int x_is_null,
                                   r_typed_result_t* result) {
    if (g_in_r_call) {
        result->type = R_RESULT_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "Re-entrance not allowed");
        return;
    }
    
    g_in_r_call = 1;
    
    r_eval_with_x_callback_data_t callback_data;
    callback_data.r_code = r_code;
    callback_data.x_val = x_val;
    callback_data.x_is_null = x_is_null;
    callback_data.result = result;
    
    Rboolean success = R_ToplevelExec(r_eval_with_x_inner_callback, &callback_data);
    
    if (!success) {
        result->type = R_RESULT_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "R_ToplevelExec failed");
    }
    
    g_in_r_call = 0;
}

// Scalar function: rx(expr, x) -> DOUBLE
// Injects the second parameter as .x in R, evaluates expr
static void rx_scalar_function(duckdb_function_info info, duckdb_data_chunk input, 
                                duckdb_vector output) {
    idx_t count = duckdb_data_chunk_get_size(input);
    
    // Get input vectors
    duckdb_vector expr_vec = duckdb_data_chunk_get_vector(input, 0);  // R expression
    duckdb_vector x_vec = duckdb_data_chunk_get_vector(input, 1);     // Value for .x
    
    // Get data pointers
    duckdb_string_t* expr_data = duckdb_vector_get_data(expr_vec);
    double* x_data = duckdb_vector_get_data(x_vec);
    double* out_data = duckdb_vector_get_data(output);
    
    // Get validity masks
    uint64_t* expr_validity = duckdb_vector_get_validity(expr_vec);
    uint64_t* x_validity = duckdb_vector_get_validity(x_vec);
    
    // Cache the expression string (assuming constant for all rows)
    char* expr_str = NULL;
    if (count > 0 && duckdb_validity_row_is_valid(expr_validity, 0)) {
        duckdb_string_t s = expr_data[0];
        if (s.value.inlined.length <= 12) {
            expr_str = strndup(s.value.inlined.inlined, s.value.inlined.length);
        } else {
            expr_str = strndup(s.value.pointer.ptr, s.value.pointer.length);
        }
    }
    
    if (!expr_str) {
        duckdb_scalar_function_set_error(info, "rx requires a valid R expression");
        return;
    }
    
    // Ensure output validity is writable
    duckdb_vector_ensure_validity_writable(output);
    uint64_t* out_validity = duckdb_vector_get_validity(output);
    
    // Process each row
    for (idx_t i = 0; i < count; i++) {
        int x_is_null = !duckdb_validity_row_is_valid(x_validity, i);
        double x_val = x_is_null ? 0.0 : x_data[i];
        
        r_typed_result_t result;
        execute_r_eval_with_x(expr_str, x_val, x_is_null, &result);
        
        if (result.type == R_RESULT_ERROR) {
            duckdb_scalar_function_set_error(info, result.error_msg);
            free(expr_str);
            return;
        }
        
        if (result.is_na || result.type == R_RESULT_NULL) {
            duckdb_validity_set_row_invalid(out_validity, i);
        } else {
            out_data[i] = result.value.double_val;
        }
    }
    
    free(expr_str);
}

// =============================================================================
// Scalar Function: rx_str - R expression with string .x value -> DOUBLE
// =============================================================================

// Callback data for R evaluation with string .x
typedef struct {
    const char* r_code;
    const char* x_str;   // String value for .x
    int x_is_null;
    r_typed_result_t* result;
} r_eval_with_str_callback_data_t;

static void r_eval_with_str_inner_callback(void* data) {
    r_eval_with_str_callback_data_t* eval_data = (r_eval_with_str_callback_data_t*)data;
    r_typed_result_t* res = eval_data->result;
    
    memset(res, 0, sizeof(r_typed_result_t));
    res->type = R_RESULT_NULL;
    
    if (eval_data->x_is_null) {
        res->is_na = 1;
        res->type = R_RESULT_STRING;
        return;
    }
    
    // Inject .x as string
    SEXP x_val = PROTECT(Rf_mkString(eval_data->x_str));
    Rf_defineVar(Rf_install(".x"), x_val, R_GlobalEnv);
    
    ParseStatus parse_status;
    SEXP code_str = PROTECT(Rf_mkString(eval_data->r_code));
    SEXP parsed = PROTECT(R_ParseVector(code_str, -1, &parse_status, R_NilValue));
    
    if (parse_status != PARSE_OK || TYPEOF(parsed) != EXPRSXP) {
        res->type = R_RESULT_ERROR;
        snprintf(res->error_msg, sizeof(res->error_msg), "Parse error");
        UNPROTECT(3);
        return;
    }
    
    int error = 0;
    SEXP result = R_NilValue;
    for (int i = 0; i < Rf_length(parsed); i++) {
        result = R_tryEval(VECTOR_ELT(parsed, i), R_GlobalEnv, &error);
        if (error) {
            res->type = R_RESULT_ERROR;
            snprintf(res->error_msg, sizeof(res->error_msg), "Evaluation error");
            UNPROTECT(3);
            return;
        }
    }
    
    // Convert result to string
    if (result == R_NilValue) {
        res->type = R_RESULT_NULL;
    } else if (TYPEOF(result) == STRSXP && Rf_length(result) >= 1) {
        res->type = R_RESULT_STRING;
        SEXP elem = STRING_ELT(result, 0);
        if (elem == NA_STRING) {
            res->is_na = 1;
        } else {
            res->value.string_val = strdup(CHAR(elem));
        }
    } else if (TYPEOF(result) == REALSXP && Rf_length(result) >= 1) {
        res->type = R_RESULT_STRING;
        double val = REAL(result)[0];
        if (ISNA(val) || ISNAN(val)) {
            res->is_na = 1;
        } else {
            char buf[64];
            snprintf(buf, sizeof(buf), "%g", val);
            res->value.string_val = strdup(buf);
        }
    } else if (TYPEOF(result) == INTSXP && Rf_length(result) >= 1) {
        res->type = R_RESULT_STRING;
        int val = INTEGER(result)[0];
        if (val == NA_INTEGER) {
            res->is_na = 1;
        } else {
            char buf[32];
            snprintf(buf, sizeof(buf), "%d", val);
            res->value.string_val = strdup(buf);
        }
    } else if (TYPEOF(result) == LGLSXP && Rf_length(result) >= 1) {
        res->type = R_RESULT_STRING;
        int val = LOGICAL(result)[0];
        if (val == NA_LOGICAL) {
            res->is_na = 1;
        } else {
            res->value.string_val = strdup(val ? "TRUE" : "FALSE");
        }
    } else {
        res->type = R_RESULT_STRING;
        char buf[128];
        snprintf(buf, sizeof(buf), "<R object: type %d>", TYPEOF(result));
        res->value.string_val = strdup(buf);
    }
    
    UNPROTECT(3);
}

static void execute_r_eval_with_str(const char* r_code, const char* x_str, int x_is_null,
                                     r_typed_result_t* result) {
    if (g_in_r_call) {
        result->type = R_RESULT_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "Re-entrance not allowed");
        return;
    }
    
    g_in_r_call = 1;
    
    r_eval_with_str_callback_data_t callback_data;
    callback_data.r_code = r_code;
    callback_data.x_str = x_str;
    callback_data.x_is_null = x_is_null;
    callback_data.result = result;
    
    Rboolean success = R_ToplevelExec(r_eval_with_str_inner_callback, &callback_data);
    
    if (!success) {
        result->type = R_RESULT_ERROR;
        snprintf(result->error_msg, sizeof(result->error_msg), "R_ToplevelExec failed");
    }
    
    g_in_r_call = 0;
}

// Helper to extract string from duckdb_string_t
static char* extract_duckdb_string(duckdb_string_t* s) {
    if (s->value.inlined.length <= 12) {
        return strndup(s->value.inlined.inlined, s->value.inlined.length);
    } else {
        return strndup(s->value.pointer.ptr, s->value.pointer.length);
    }
}

// Scalar function: rx_str(expr, x_str) -> VARCHAR
static void rx_str_scalar_function(duckdb_function_info info, duckdb_data_chunk input, 
                                    duckdb_vector output) {
    idx_t count = duckdb_data_chunk_get_size(input);
    
    duckdb_vector expr_vec = duckdb_data_chunk_get_vector(input, 0);
    duckdb_vector x_vec = duckdb_data_chunk_get_vector(input, 1);
    
    duckdb_string_t* expr_data = duckdb_vector_get_data(expr_vec);
    duckdb_string_t* x_data = duckdb_vector_get_data(x_vec);
    
    uint64_t* expr_validity = duckdb_vector_get_validity(expr_vec);
    uint64_t* x_validity = duckdb_vector_get_validity(x_vec);
    
    char* expr_str = NULL;
    if (count > 0 && duckdb_validity_row_is_valid(expr_validity, 0)) {
        expr_str = extract_duckdb_string(&expr_data[0]);
    }
    
    if (!expr_str) {
        duckdb_scalar_function_set_error(info, "rx_str requires a valid R expression");
        return;
    }
    
    duckdb_vector_ensure_validity_writable(output);
    uint64_t* out_validity = duckdb_vector_get_validity(output);
    
    for (idx_t i = 0; i < count; i++) {
        int x_is_null = !duckdb_validity_row_is_valid(x_validity, i);
        char* x_str = x_is_null ? NULL : extract_duckdb_string(&x_data[i]);
        
        r_typed_result_t result;
        execute_r_eval_with_str(expr_str, x_str, x_is_null, &result);
        
        if (x_str) free(x_str);
        
        if (result.type == R_RESULT_ERROR) {
            duckdb_scalar_function_set_error(info, result.error_msg);
            free(expr_str);
            return;
        }
        
        if (result.is_na || result.type == R_RESULT_NULL) {
            duckdb_validity_set_row_invalid(out_validity, i);
        } else if (result.value.string_val) {
            duckdb_vector_assign_string_element(output, i, result.value.string_val);
            free(result.value.string_val);
        }
    }
    
    free(expr_str);
}

// =============================================================================
// Extension initialization
// =============================================================================

static void register_r_udf_functions(duckdb_connection conn) {
    duckdb_logical_type varchar_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    
    // Register r_eval table function (VARCHAR result)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_eval");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_eval_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_eval_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_int table function (INTEGER result)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_int");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_int_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_int_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_double table function (DOUBLE result)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_double");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_double_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_double_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_bool table function (BOOLEAN result)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_bool");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_bool_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_bool_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_vector_int table function (INTEGER[] result)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_vector_int");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_vector_int_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_vector_int_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_vector_double table function (DOUBLE[] result)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_vector_double");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_vector_double_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_vector_double_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_vector_varchar table function (VARCHAR[] result)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_vector_varchar");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_vector_varchar_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_vector_varchar_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_vector_bool table function (BOOLEAN[] result)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_vector_bool");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_vector_bool_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_vector_bool_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_raw table function (BLOB result)
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_raw");
        duckdb_table_function_add_parameter(func, varchar_type);
        duckdb_table_function_set_bind(func, r_raw_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_raw_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_init table function
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_init");
        duckdb_table_function_set_bind(func, r_init_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_init_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // Register r_status table function
    {
        duckdb_table_function func = duckdb_create_table_function();
        duckdb_table_function_set_name(func, "r_status");
        duckdb_table_function_set_bind(func, r_status_bind);
        duckdb_table_function_set_init(func, r_eval_init);
        duckdb_table_function_set_function(func, r_status_function);
        duckdb_register_table_function(conn, func);
        duckdb_destroy_table_function(&func);
    }
    
    // =========================================================================
    // Scalar Functions - can use column values as parameters
    // =========================================================================
    
    duckdb_logical_type double_type = duckdb_create_logical_type(DUCKDB_TYPE_DOUBLE);
    
    // Register rx scalar function: rx(expr, x) -> DOUBLE
    // Injects second parameter as .x, evaluates R expression
    {
        duckdb_scalar_function func = duckdb_create_scalar_function();
        duckdb_scalar_function_set_name(func, "rx");
        duckdb_scalar_function_add_parameter(func, varchar_type);  // R expression
        duckdb_scalar_function_add_parameter(func, double_type);   // .x value
        duckdb_scalar_function_set_return_type(func, double_type);
        duckdb_scalar_function_set_function(func, rx_scalar_function);
        duckdb_scalar_function_set_volatile(func);  // Re-run for each row
        duckdb_register_scalar_function(conn, func);
        duckdb_destroy_scalar_function(&func);
    }
    
    // Register rx_str scalar function: rx_str(expr, x_str) -> VARCHAR
    // Injects string .x, returns string result
    {
        duckdb_scalar_function func = duckdb_create_scalar_function();
        duckdb_scalar_function_set_name(func, "rx_str");
        duckdb_scalar_function_add_parameter(func, varchar_type);  // R expression
        duckdb_scalar_function_add_parameter(func, varchar_type);  // .x string value
        duckdb_scalar_function_set_return_type(func, varchar_type);
        duckdb_scalar_function_set_function(func, rx_str_scalar_function);
        duckdb_scalar_function_set_volatile(func);
        duckdb_register_scalar_function(conn, func);
        duckdb_destroy_scalar_function(&func);
    }
    
    duckdb_destroy_logical_type(&double_type);
    duckdb_destroy_logical_type(&varchar_type);
}

// Main extension entry point
DUCKDB_EXTENSION_ENTRYPOINT(duckdb_connection conn, duckdb_extension_info info,
                            struct duckdb_extension_access *access) {
    (void)info;
    (void)access;
    
    register_r_udf_functions(conn);
    
    return true;
}
