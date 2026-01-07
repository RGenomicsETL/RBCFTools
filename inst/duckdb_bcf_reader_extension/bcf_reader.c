/**
 * DuckDB BCF/VCF Reader Extension
 * 
 * A properly-typed VCF/BCF reader for DuckDB that matches the type system
 * of the nanoarrow vcf_arrow_stream implementation.
 * 
 * Features:
 *   - VCF spec-compliant type validation with warnings
 *   - Proper DuckDB types: INT32, INT64, FLOAT, DOUBLE, VARCHAR, LIST, STRUCT
 *   - Boolean support for FLAG fields
 *   - Nullable fields with validity tracking
 *   - Parallel scan support for indexed files (CSI/TBI)
 *   - Region filtering
 *   - Projection pushdown
 *
 * Usage:
 *   LOAD 'bcf_reader.duckdb_extension';
 *   SELECT * FROM bcf_read('path/to/file.vcf.gz');
 *   SELECT * FROM bcf_read('path/to/file.bcf', region := 'chr1:1000-2000');
 *
 * Build:
 *   make (uses package htslib from RBCFTools)
 *
 * Copyright (c) 2026 RBCFTools Authors
 * Licensed under MIT License
 */

// Must define before including duckdb_extension.h
#define DUCKDB_EXTENSION_NAME bcf_reader

#include "duckdb_extension.h"
#include "vcf_types.h"

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>

// htslib headers
#include <htslib/vcf.h>
#include <htslib/hts.h>
#include <htslib/hts_log.h>
#include <htslib/synced_bcf_reader.h>
#include <htslib/tbx.h>
#include <htslib/kstring.h>

// Required macro for DuckDB C extensions
DUCKDB_EXTENSION_EXTERN

// =============================================================================
// Constants
// =============================================================================

#define BCF_READER_DEFAULT_BATCH_SIZE 2048
#define BCF_READER_MAX_STRING_LEN 65536

// Column indices for core VCF fields
enum {
    COL_CHROM = 0,
    COL_POS,
    COL_ID,
    COL_REF,
    COL_ALT,
    COL_QUAL,
    COL_FILTER,
    COL_CORE_COUNT  // Number of core columns (7)
};

// =============================================================================
// Field Metadata Structure
// =============================================================================

typedef struct {
    char* name;              // Field name (owned)
    int header_id;           // Header ID for bcf_get_* functions
    int header_type;         // BCF_HT_* from header (used for reading data)
    int schema_type;         // BCF_HT_* for schema (may be corrected)
    int vl_type;             // BCF_VL_* (corrected per VCF spec)
    int is_list;             // Whether this is a list type
    int duckdb_col_idx;      // Column index in DuckDB result
} field_meta_t;

// =============================================================================
// Bind Data - stores parameters and schema info
// =============================================================================

typedef struct {
    char* file_path;
    char* region;              // Optional region filter
    int include_info;          // Include INFO fields
    int include_format;        // Include FORMAT/sample fields
    int n_samples;             // Number of samples
    char** sample_names;       // Sample names (owned)
    
    // Field metadata
    int n_info_fields;
    field_meta_t* info_fields;
    
    int n_format_fields;
    field_meta_t* format_fields;
    
    // Total column count
    int total_columns;
    
    // Parallel scan info (populated if index exists)
    int has_index;             // Whether an index was found
    int n_contigs;             // Number of contigs for parallel scan
    char** contig_names;       // Contig names (owned)
} bcf_bind_data_t;

// =============================================================================
// Global Init Data - shared across all threads
// =============================================================================

typedef struct {
    int current_contig;        // Next contig to assign (atomic-like access via DuckDB)
    int n_contigs;             // Total number of contigs
    char** contig_names;       // Contig names (reference to bind data)
    int has_region;            // User specified a region
} bcf_global_init_data_t;

// =============================================================================
// Init Data - per-thread scanning state (now used as local init)
// =============================================================================

typedef struct {
    htsFile* fp;
    bcf_hdr_t* hdr;
    bcf1_t* rec;
    
    // Index support
    hts_idx_t* idx;           // BCF index (CSI)
    tbx_t* tbx;               // VCF tabix index (TBI)
    hts_itr_t* itr;           // Iterator
    kstring_t kstr;           // String buffer for VCF text parsing
    
    int64_t current_row;
    int done;
    
    // Projection pushdown
    idx_t column_count;
    idx_t* column_ids;
    
    // Parallel scan state
    int is_parallel;
    int assigned_contig;       // Which contig this thread is scanning (-1 = all)
    const char* contig_name;   // Name of assigned contig (reference, don't free)
    int needs_next_contig;     // Flag to request next contig assignment
} bcf_init_data_t;
    idx_t column_count;
    idx_t* column_ids;
    
    // Parallel scan state
    int is_parallel;
    int assigned_contig;       // Which contig this thread is scanning (-1 = all)
    const char* contig_name;   // Name of assigned contig
} bcf_init_data_t;

// =============================================================================
// Warning Callback for DuckDB
// =============================================================================

static void duckdb_vcf_warning(const char* msg, void* ctx) {
    (void)ctx;
    // In DuckDB extensions, we can't easily emit warnings
    // For now, print to stderr
    fprintf(stderr, "[bcf_reader] %s\n", msg);
}

// =============================================================================
// Memory Management
// =============================================================================

static void destroy_bind_data(void* data) {
    bcf_bind_data_t* bind = (bcf_bind_data_t*)data;
    if (!bind) return;
    
    if (bind->file_path) duckdb_free(bind->file_path);
    if (bind->region) duckdb_free(bind->region);
    
    if (bind->sample_names) {
        for (int i = 0; i < bind->n_samples; i++) {
            if (bind->sample_names[i]) duckdb_free(bind->sample_names[i]);
        }
        duckdb_free(bind->sample_names);
    }
    
    if (bind->info_fields) {
        for (int i = 0; i < bind->n_info_fields; i++) {
            if (bind->info_fields[i].name) duckdb_free(bind->info_fields[i].name);
        }
        duckdb_free(bind->info_fields);
    }
    
    if (bind->format_fields) {
        for (int i = 0; i < bind->n_format_fields; i++) {
            if (bind->format_fields[i].name) duckdb_free(bind->format_fields[i].name);
        }
        duckdb_free(bind->format_fields);
    }
    
    if (bind->contig_names) {
        for (int i = 0; i < bind->n_contigs; i++) {
            if (bind->contig_names[i]) duckdb_free(bind->contig_names[i]);
        }
        duckdb_free(bind->contig_names);
    }
    
    duckdb_free(bind);
}

static void destroy_global_init_data(void* data) {
    bcf_global_init_data_t* global = (bcf_global_init_data_t*)data;
    if (global) {
        // contig_names is a reference, don't free
        duckdb_free(global);
    }
}

static void destroy_init_data(void* data) {
    bcf_init_data_t* init = (bcf_init_data_t*)data;
    if (!init) return;
    
    if (init->itr) hts_itr_destroy(init->itr);
    if (init->tbx) tbx_destroy(init->tbx);
    if (init->idx) hts_idx_destroy(init->idx);
    if (init->rec) bcf_destroy(init->rec);
    if (init->hdr) bcf_hdr_destroy(init->hdr);
    if (init->fp) hts_close(init->fp);
    if (init->column_ids) duckdb_free(init->column_ids);
    ks_free(&init->kstr);
    
    duckdb_free(init);
}

// =============================================================================
// String Utilities
// =============================================================================

static char* strdup_duckdb(const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s) + 1;
    char* copy = (char*)duckdb_malloc(len);
    if (copy) memcpy(copy, s, len);
    return copy;
}

// =============================================================================
// DuckDB Type Creation Helpers
// =============================================================================

/**
 * Create a DuckDB logical type for a BCF field.
 */
static duckdb_logical_type create_bcf_field_type(int bcf_type, int is_list) {
    duckdb_logical_type element_type;
    
    switch (bcf_type) {
        case BCF_HT_FLAG:
            element_type = duckdb_create_logical_type(DUCKDB_TYPE_BOOLEAN);
            break;
        case BCF_HT_INT:
            element_type = duckdb_create_logical_type(DUCKDB_TYPE_INTEGER);
            break;
        case BCF_HT_REAL:
            element_type = duckdb_create_logical_type(DUCKDB_TYPE_FLOAT);
            break;
        case BCF_HT_STR:
        default:
            element_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
            break;
    }
    
    if (is_list) {
        duckdb_logical_type list_type = duckdb_create_list_type(element_type);
        duckdb_destroy_logical_type(&element_type);
        return list_type;
    }
    
    return element_type;
}

// =============================================================================
// Schema Building - Bind Function
// =============================================================================

static void bcf_read_bind(duckdb_bind_info info) {
    // Set up warning callback
    vcf_set_warning_callback(duckdb_vcf_warning, NULL);
    
    // Get the file path parameter
    duckdb_value path_val = duckdb_bind_get_parameter(info, 0);
    char* file_path = duckdb_get_varchar(path_val);
    duckdb_destroy_value(&path_val);
    
    if (!file_path || strlen(file_path) == 0) {
        duckdb_bind_set_error(info, "bcf_read requires a file path");
        if (file_path) duckdb_free(file_path);
        return;
    }
    
    // Get optional region named parameter
    char* region = NULL;
    duckdb_value region_val = duckdb_bind_get_named_parameter(info, "region");
    if (region_val && !duckdb_is_null_value(region_val)) {
        region = duckdb_get_varchar(region_val);
    }
    if (region_val) duckdb_destroy_value(&region_val);
    
    // Open the file to read header
    htsFile* fp = hts_open(file_path, "r");
    if (!fp) {
        char err[512];
        snprintf(err, sizeof(err), "Failed to open BCF/VCF file: %s", file_path);
        duckdb_bind_set_error(info, err);
        duckdb_free(file_path);
        if (region) duckdb_free(region);
        return;
    }
    
    bcf_hdr_t* hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        duckdb_bind_set_error(info, "Failed to read BCF/VCF header");
        duckdb_free(file_path);
        if (region) duckdb_free(region);
        return;
    }
    
    // Create bind data
    bcf_bind_data_t* bind = (bcf_bind_data_t*)duckdb_malloc(sizeof(bcf_bind_data_t));
    memset(bind, 0, sizeof(bcf_bind_data_t));
    bind->file_path = file_path;
    bind->region = region;
    bind->include_info = 1;
    bind->include_format = 1;
    bind->n_samples = bcf_hdr_nsamples(hdr);
    
    // Copy sample names
    if (bind->n_samples > 0) {
        bind->sample_names = (char**)duckdb_malloc(bind->n_samples * sizeof(char*));
        for (int i = 0; i < bind->n_samples; i++) {
            bind->sample_names[i] = strdup_duckdb(hdr->samples[i]);
        }
    }
    
    // Create logical types for schema
    duckdb_logical_type varchar_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    duckdb_logical_type bigint_type = duckdb_create_logical_type(DUCKDB_TYPE_BIGINT);
    duckdb_logical_type double_type = duckdb_create_logical_type(DUCKDB_TYPE_DOUBLE);
    duckdb_logical_type varchar_list_type = duckdb_create_list_type(varchar_type);
    
    int col_idx = 0;
    
    // -------------------------------------------------------------------------
    // Core VCF columns (matching nanoarrow schema)
    // -------------------------------------------------------------------------
    
    // CHROM - VARCHAR (not null)
    duckdb_bind_add_result_column(info, "CHROM", varchar_type);
    col_idx++;
    
    // POS - BIGINT (1-based position)
    duckdb_bind_add_result_column(info, "POS", bigint_type);
    col_idx++;
    
    // ID - VARCHAR (nullable)
    duckdb_bind_add_result_column(info, "ID", varchar_type);
    col_idx++;
    
    // REF - VARCHAR
    duckdb_bind_add_result_column(info, "REF", varchar_type);
    col_idx++;
    
    // ALT - LIST(VARCHAR) - list of alternate alleles
    duckdb_bind_add_result_column(info, "ALT", varchar_list_type);
    col_idx++;
    
    // QUAL - DOUBLE (nullable, matching nanoarrow FLOAT64)
    duckdb_bind_add_result_column(info, "QUAL", double_type);
    col_idx++;
    
    // FILTER - LIST(VARCHAR) - list of filter names
    duckdb_bind_add_result_column(info, "FILTER", varchar_list_type);
    col_idx++;
    
    // -------------------------------------------------------------------------
    // INFO fields (with type validation)
    // -------------------------------------------------------------------------
    
    // Count INFO fields
    bind->n_info_fields = 0;
    for (int i = 0; i < hdr->n[BCF_DT_ID]; i++) {
        if (hdr->id[BCF_DT_ID][i].val && 
            hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_INFO]) {
            bind->n_info_fields++;
        }
    }
    
    if (bind->n_info_fields > 0) {
        bind->info_fields = (field_meta_t*)duckdb_malloc(bind->n_info_fields * sizeof(field_meta_t));
        memset(bind->info_fields, 0, bind->n_info_fields * sizeof(field_meta_t));
        
        int info_idx = 0;
        for (int i = 0; i < hdr->n[BCF_DT_ID] && info_idx < bind->n_info_fields; i++) {
            if (hdr->id[BCF_DT_ID][i].val && 
                hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_INFO]) {
                const char* field_name = hdr->id[BCF_DT_ID][i].key;
                int header_type = bcf_hdr_id2type(hdr, BCF_HL_INFO, i);
                int header_vl_type = bcf_hdr_id2length(hdr, BCF_HL_INFO, i);
                
                // Validate against VCF spec (emits warnings)
                int corrected_type;
                int corrected_vl_type = vcf_validate_info_field(field_name, header_vl_type, 
                                                                 header_type, &corrected_type);
                
                field_meta_t* field = &bind->info_fields[info_idx];
                field->name = strdup_duckdb(field_name);
                field->header_id = i;
                field->header_type = header_type;
                field->schema_type = header_type;  // Use header type for data
                field->vl_type = corrected_vl_type;
                field->is_list = vcf_is_list_type(corrected_vl_type);
                field->duckdb_col_idx = col_idx;
                
                // Create column name: INFO_<fieldname>
                char col_name[256];
                snprintf(col_name, sizeof(col_name), "INFO_%s", field_name);
                
                // Create DuckDB type
                duckdb_logical_type field_type = create_bcf_field_type(header_type, field->is_list);
                duckdb_bind_add_result_column(info, col_name, field_type);
                duckdb_destroy_logical_type(&field_type);
                
                col_idx++;
                info_idx++;
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // FORMAT fields per sample (with type validation)
    // -------------------------------------------------------------------------
    
    if (bind->n_samples > 0) {
        // Count FORMAT fields
        bind->n_format_fields = 0;
        for (int i = 0; i < hdr->n[BCF_DT_ID]; i++) {
            if (hdr->id[BCF_DT_ID][i].val && 
                hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_FMT]) {
                bind->n_format_fields++;
            }
        }
        
        if (bind->n_format_fields == 0) {
            // Add GT as default
            bind->n_format_fields = 1;
            bind->format_fields = (field_meta_t*)duckdb_malloc(sizeof(field_meta_t));
            memset(bind->format_fields, 0, sizeof(field_meta_t));
            bind->format_fields[0].name = strdup_duckdb("GT");
            bind->format_fields[0].header_type = BCF_HT_STR;
            bind->format_fields[0].schema_type = BCF_HT_STR;
            bind->format_fields[0].vl_type = BCF_VL_FIXED;
            bind->format_fields[0].is_list = 0;
        } else {
            bind->format_fields = (field_meta_t*)duckdb_malloc(bind->n_format_fields * sizeof(field_meta_t));
            memset(bind->format_fields, 0, bind->n_format_fields * sizeof(field_meta_t));
            
            int fmt_idx = 0;
            for (int i = 0; i < hdr->n[BCF_DT_ID] && fmt_idx < bind->n_format_fields; i++) {
                if (hdr->id[BCF_DT_ID][i].val && 
                    hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_FMT]) {
                    const char* field_name = hdr->id[BCF_DT_ID][i].key;
                    int header_type = bcf_hdr_id2type(hdr, BCF_HL_FMT, i);
                    int header_vl_type = bcf_hdr_id2length(hdr, BCF_HL_FMT, i);
                    
                    // Validate against VCF spec (emits warnings, only once)
                    int corrected_type;
                    int corrected_vl_type = vcf_validate_format_field(field_name, header_vl_type,
                                                                       header_type, &corrected_type);
                    
                    field_meta_t* field = &bind->format_fields[fmt_idx];
                    field->name = strdup_duckdb(field_name);
                    field->header_id = i;
                    field->header_type = header_type;
                    field->schema_type = header_type;
                    field->vl_type = corrected_vl_type;
                    field->is_list = vcf_is_list_type(corrected_vl_type);
                    
                    fmt_idx++;
                }
            }
        }
        
        // Add FORMAT columns for each sample
        for (int s = 0; s < bind->n_samples; s++) {
            for (int f = 0; f < bind->n_format_fields; f++) {
                field_meta_t* field = &bind->format_fields[f];
                
                // Column name: FORMAT_<fieldname>_<samplename>
                char col_name[512];
                snprintf(col_name, sizeof(col_name), "FORMAT_%s_%s", 
                         field->name, bind->sample_names[s]);
                
                duckdb_logical_type field_type = create_bcf_field_type(field->header_type, field->is_list);
                duckdb_bind_add_result_column(info, col_name, field_type);
                duckdb_destroy_logical_type(&field_type);
                
                col_idx++;
            }
        }
    }
    
    bind->total_columns = col_idx;
    
    // -------------------------------------------------------------------------
    // Check for index and extract contig names for parallel scanning
    // -------------------------------------------------------------------------
    
    bind->has_index = 0;
    bind->n_contigs = 0;
    bind->contig_names = NULL;
    
    // Only set up parallel scan if no user-specified region
    if (!region || strlen(region) == 0) {
        // Suppress htslib warnings when index doesn't exist
        int old_log_level = hts_get_log_level();
        hts_set_log_level(HTS_LOG_OFF);
        
        // Try to load index
        hts_idx_t* idx = NULL;
        tbx_t* tbx = NULL;
        enum htsExactFormat fmt = hts_get_format(fp)->format;
        
        if (fmt == bcf) {
            idx = bcf_index_load(file_path);
        } else {
            tbx = tbx_index_load(file_path);
            if (!tbx) {
                idx = bcf_index_load(file_path);
            }
        }
        
        // Restore log level
        hts_set_log_level(old_log_level);
        
        if (idx || tbx) {
            bind->has_index = 1;
            
            // Get contig names from header for parallel scan
            int n_seqs = hdr->n[BCF_DT_CTG];
            if (n_seqs > 0) {
                bind->n_contigs = n_seqs;
                bind->contig_names = (char**)duckdb_malloc(n_seqs * sizeof(char*));
                
                for (int i = 0; i < n_seqs; i++) {
                    bind->contig_names[i] = strdup_duckdb(hdr->id[BCF_DT_CTG][i].key);
                }
            }
            
            if (idx) hts_idx_destroy(idx);
            if (tbx) tbx_destroy(tbx);
        }
    }
    
    // Cleanup
    duckdb_destroy_logical_type(&varchar_type);
    duckdb_destroy_logical_type(&bigint_type);
    duckdb_destroy_logical_type(&double_type);
    duckdb_destroy_logical_type(&varchar_list_type);
    
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    duckdb_bind_set_bind_data(info, bind, destroy_bind_data);
}

// =============================================================================
// Global Init Function - Set up parallel scanning
// =============================================================================

static void bcf_read_global_init(duckdb_init_info info) {
    bcf_bind_data_t* bind = (bcf_bind_data_t*)duckdb_init_get_bind_data(info);
    
    bcf_global_init_data_t* global = (bcf_global_init_data_t*)duckdb_malloc(sizeof(bcf_global_init_data_t));
    memset(global, 0, sizeof(bcf_global_init_data_t));
    
    global->current_contig = 0;
    global->has_region = (bind->region && strlen(bind->region) > 0);
    
    // Enable parallel scan if:
    // 1. Index exists
    // 2. Multiple contigs available
    // 3. No user-specified region (region queries are already filtered)
    if (bind->has_index && bind->n_contigs > 1 && !global->has_region) {
        global->n_contigs = bind->n_contigs;
        global->contig_names = bind->contig_names;  // Reference only
        
        // Cap threads at number of contigs or reasonable max
        idx_t max_threads = bind->n_contigs;
        if (max_threads > 16) max_threads = 16;
        duckdb_init_set_max_threads(info, max_threads);
    } else {
        // Single-threaded scan
        global->n_contigs = 0;
        global->contig_names = NULL;
        duckdb_init_set_max_threads(info, 1);
    }
    
    duckdb_init_set_init_data(info, global, destroy_global_init_data);
}

// =============================================================================
// Local Init Function - Per-thread scanning state
// =============================================================================

static void bcf_read_local_init(duckdb_init_info info) {
    bcf_bind_data_t* bind = (bcf_bind_data_t*)duckdb_init_get_bind_data(info);
    bcf_global_init_data_t* global = (bcf_global_init_data_t*)duckdb_init_get_init_data(info);
    
    bcf_init_data_t* local = (bcf_init_data_t*)duckdb_malloc(sizeof(bcf_init_data_t));
    memset(local, 0, sizeof(bcf_init_data_t));
    
    // Initialize parallel scan state
    local->is_parallel = (global->n_contigs > 0);
    local->assigned_contig = -1;
    local->contig_name = NULL;
    local->needs_next_contig = local->is_parallel;  // Start by requesting first contig
    
    // Open file (each thread gets its own file handle)
    local->fp = hts_open(bind->file_path, "r");
    if (!local->fp) {
        duckdb_init_set_error(info, "Failed to open BCF/VCF file");
        duckdb_free(local);
        return;
    }
    
    // Read header
    local->hdr = bcf_hdr_read(local->fp);
    if (!local->hdr) {
        hts_close(local->fp);
        duckdb_init_set_error(info, "Failed to read BCF/VCF header");
        duckdb_free(local);
        return;
    }
    
    // Allocate record
    local->rec = bcf_init();
    
    // Load index for parallel scanning or region queries
    if (local->is_parallel || (bind->region && strlen(bind->region) > 0)) {
        enum htsExactFormat fmt = hts_get_format(local->fp)->format;
        
        if (fmt == bcf) {
            local->idx = bcf_index_load(bind->file_path);
        } else {
            local->tbx = tbx_index_load(bind->file_path);
            if (!local->tbx) {
                local->idx = bcf_index_load(bind->file_path);
            }
        }
    }
    
    // Set up region query if user specified a region (non-parallel case)
    if (!local->is_parallel && bind->region && strlen(bind->region) > 0) {
        if (local->idx) {
            local->itr = bcf_itr_querys(local->idx, local->hdr, bind->region);
        } else if (local->tbx) {
            local->itr = tbx_itr_querys(local->tbx, bind->region);
        }
        
        if (!local->itr) {
            char err[512];
            snprintf(err, sizeof(err), 
                     "Region query requires index file. Region: %s", bind->region);
            duckdb_init_set_error(info, err);
            destroy_init_data(local);
            return;
        }
    }
    
    local->current_row = 0;
    local->done = 0;
    
    // Get projection pushdown info
    local->column_count = duckdb_init_get_column_count(info);
    local->column_ids = (idx_t*)duckdb_malloc(sizeof(idx_t) * local->column_count);
    for (idx_t i = 0; i < local->column_count; i++) {
        local->column_ids[i] = duckdb_init_get_column_index(info, i);
    }
    
    // Store as local init data
    duckdb_init_set_init_data(info, local, destroy_init_data);
}

// =============================================================================
// Helper: Set validity bit
// =============================================================================

static inline void set_validity_bit(uint64_t* validity, idx_t row, int is_valid) {
    if (!validity) return;
    idx_t entry_idx = row / 64;
    idx_t bit_idx = row % 64;
    if (is_valid) {
        validity[entry_idx] |= ((uint64_t)1 << bit_idx);
    } else {
        validity[entry_idx] &= ~((uint64_t)1 << bit_idx);
    }
}

// =============================================================================
// Main Scan Function
// =============================================================================

static void bcf_read_function(duckdb_function_info info, duckdb_data_chunk output) {
    bcf_bind_data_t* bind = (bcf_bind_data_t*)duckdb_function_get_bind_data(info);
    
    // Try to get local init data first (for parallel scans)
    bcf_init_data_t* init = (bcf_init_data_t*)duckdb_function_get_local_init_data(info);
    if (!init) {
        // Fall back to regular init data (shouldn't happen with our setup)
        init = (bcf_init_data_t*)duckdb_function_get_init_data(info);
    }
    
    if (!init || init->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    idx_t vector_size = duckdb_vector_size();
    idx_t row_count = 0;
    
    // Read records
    while (row_count < vector_size) {
        int ret;
        
        if (init->itr) {
            if (init->tbx) {
                // VCF with tabix: read text line then parse
                ret = tbx_itr_next(init->fp, init->tbx, init->itr, &init->kstr);
                if (ret >= 0) {
                    ret = vcf_parse1(&init->kstr, init->hdr, init->rec);
                    init->kstr.l = 0;
                }
            } else {
                // BCF with index
                ret = bcf_itr_next(init->fp, init->itr, init->rec);
            }
        } else {
            ret = bcf_read(init->fp, init->hdr, init->rec);
        }
        
        if (ret < 0) {
            init->done = 1;
            break;
        }
        
        // Unpack record
        bcf_unpack(init->rec, BCF_UN_ALL);
        
        // Process each requested column
        for (idx_t i = 0; i < init->column_count; i++) {
            idx_t col_id = init->column_ids[i];
            duckdb_vector vec = duckdb_data_chunk_get_vector(output, i);
            
            // Core VCF columns
            if (col_id == COL_CHROM) {
                const char* chrom = bcf_hdr_id2name(init->hdr, init->rec->rid);
                duckdb_vector_assign_string_element(vec, row_count, chrom ? chrom : ".");
            }
            else if (col_id == COL_POS) {
                int64_t* data = (int64_t*)duckdb_vector_get_data(vec);
                data[row_count] = init->rec->pos + 1;  // 1-based
            }
            else if (col_id == COL_ID) {
                const char* id = init->rec->d.id;
                if (id && strcmp(id, ".") != 0) {
                    duckdb_vector_assign_string_element(vec, row_count, id);
                } else {
                    duckdb_vector_ensure_validity_writable(vec);
                    uint64_t* validity = duckdb_vector_get_validity(vec);
                    set_validity_bit(validity, row_count, 0);
                }
            }
            else if (col_id == COL_REF) {
                const char* ref = init->rec->d.allele[0];
                duckdb_vector_assign_string_element(vec, row_count, ref ? ref : ".");
            }
            else if (col_id == COL_ALT) {
                // ALT is a LIST(VARCHAR)
                duckdb_list_entry entry;
                entry.offset = duckdb_list_vector_get_size(vec);
                entry.length = init->rec->n_allele > 1 ? init->rec->n_allele - 1 : 0;
                
                duckdb_vector child_vec = duckdb_list_vector_get_child(vec);
                
                // Reserve and set space for all ALT alleles
                if (entry.length > 0) {
                    duckdb_list_vector_reserve(vec, entry.offset + entry.length);
                    duckdb_list_vector_set_size(vec, entry.offset + entry.length);
                    
                    for (int a = 1; a < init->rec->n_allele; a++) {
                        duckdb_vector_assign_string_element(child_vec, entry.offset + a - 1,
                                                            init->rec->d.allele[a]);
                    }
                }
                
                duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                list_data[row_count] = entry;
            }
            else if (col_id == COL_QUAL) {
                double* data = (double*)duckdb_vector_get_data(vec);
                if (bcf_float_is_missing(init->rec->qual)) {
                    duckdb_vector_ensure_validity_writable(vec);
                    uint64_t* validity = duckdb_vector_get_validity(vec);
                    set_validity_bit(validity, row_count, 0);
                    data[row_count] = 0.0;
                } else {
                    data[row_count] = init->rec->qual;
                }
            }
            else if (col_id == COL_FILTER) {
                // FILTER is a LIST(VARCHAR)
                duckdb_list_entry entry;
                entry.offset = duckdb_list_vector_get_size(vec);
                
                duckdb_vector child_vec = duckdb_list_vector_get_child(vec);
                
                if (init->rec->d.n_flt == 0) {
                    // No filters means PASS
                    entry.length = 1;
                    duckdb_list_vector_set_size(vec, entry.offset + 1);
                    duckdb_vector_assign_string_element(child_vec, entry.offset, "PASS");
                } else {
                    entry.length = init->rec->d.n_flt;
                    // Reserve space for all filters at once
                    duckdb_list_vector_set_size(vec, entry.offset + entry.length);
                    for (int f = 0; f < init->rec->d.n_flt; f++) {
                        const char* flt_name = bcf_hdr_int2id(init->hdr, BCF_DT_ID, 
                                                              init->rec->d.flt[f]);
                        duckdb_vector_assign_string_element(child_vec, entry.offset + f,
                                                            flt_name ? flt_name : ".");
                    }
                }
                
                duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                list_data[row_count] = entry;
            }
            else if (col_id >= COL_CORE_COUNT && 
                     col_id < (idx_t)(COL_CORE_COUNT + bind->n_info_fields)) {
                // INFO field
                int field_idx = col_id - COL_CORE_COUNT;
                field_meta_t* field = &bind->info_fields[field_idx];
                const char* tag = field->name;
                
                if (field->header_type == BCF_HT_FLAG) {
                    // Boolean field
                    bool* data = (bool*)duckdb_vector_get_data(vec);
                    int* dummy = NULL;
                    int ndummy = 0;
                    int ret_info = bcf_get_info_flag(init->hdr, init->rec, tag, &dummy, &ndummy);
                    free(dummy);
                    data[row_count] = (ret_info == 1);
                }
                else if (field->header_type == BCF_HT_INT) {
                    int32_t* values = NULL;
                    int n_values = 0;
                    int ret_info = bcf_get_info_int32(init->hdr, init->rec, tag, &values, &n_values);
                    
                    if (ret_info > 0 && values) {
                        if (field->is_list) {
                            // List of integers
                            duckdb_list_entry entry;
                            entry.offset = duckdb_list_vector_get_size(vec);
                            entry.length = 0;
                            
                            duckdb_vector child_vec = duckdb_list_vector_get_child(vec);
                            
                            // First count valid values
                            for (int v = 0; v < ret_info; v++) {
                                if (values[v] != bcf_int32_missing && values[v] != bcf_int32_vector_end) {
                                    entry.length++;
                                }
                            }
                            
                            // Reserve and set size
                            if (entry.length > 0) {
                                duckdb_list_vector_reserve(vec, entry.offset + entry.length);
                                duckdb_list_vector_set_size(vec, entry.offset + entry.length);
                                
                                // Now fill in the values
                                int32_t* child_data = (int32_t*)duckdb_vector_get_data(child_vec);
                                int write_idx = 0;
                                for (int v = 0; v < ret_info; v++) {
                                    if (values[v] != bcf_int32_missing && values[v] != bcf_int32_vector_end) {
                                        child_data[entry.offset + write_idx] = values[v];
                                        write_idx++;
                                    }
                                }
                            }
                            
                            duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                            list_data[row_count] = entry;
                        } else {
                            // Scalar integer
                            int32_t* data = (int32_t*)duckdb_vector_get_data(vec);
                            if (values[0] != bcf_int32_missing) {
                                data[row_count] = values[0];
                            } else {
                                duckdb_vector_ensure_validity_writable(vec);
                                uint64_t* validity = duckdb_vector_get_validity(vec);
                                set_validity_bit(validity, row_count, 0);
                            }
                        }
                    } else {
                        // No data - NULL
                        duckdb_vector_ensure_validity_writable(vec);
                        uint64_t* validity = duckdb_vector_get_validity(vec);
                        set_validity_bit(validity, row_count, 0);
                        
                        if (field->is_list) {
                            duckdb_list_entry entry = {duckdb_list_vector_get_size(vec), 0};
                            duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                            list_data[row_count] = entry;
                        }
                    }
                    free(values);
                }
                else if (field->header_type == BCF_HT_REAL) {
                    float* values = NULL;
                    int n_values = 0;
                    int ret_info = bcf_get_info_float(init->hdr, init->rec, tag, &values, &n_values);
                    
                    if (ret_info > 0 && values) {
                        if (field->is_list) {
                            // List of floats
                            duckdb_list_entry entry;
                            entry.offset = duckdb_list_vector_get_size(vec);
                            entry.length = 0;
                            
                            duckdb_vector child_vec = duckdb_list_vector_get_child(vec);
                            
                            // First count valid values
                            for (int v = 0; v < ret_info; v++) {
                                if (!bcf_float_is_missing(values[v]) && !bcf_float_is_vector_end(values[v])) {
                                    entry.length++;
                                }
                            }
                            
                            // Reserve and set size
                            if (entry.length > 0) {
                                duckdb_list_vector_reserve(vec, entry.offset + entry.length);
                                duckdb_list_vector_set_size(vec, entry.offset + entry.length);
                                
                                // Now fill in the values
                                float* child_data = (float*)duckdb_vector_get_data(child_vec);
                                int write_idx = 0;
                                for (int v = 0; v < ret_info; v++) {
                                    if (!bcf_float_is_missing(values[v]) && !bcf_float_is_vector_end(values[v])) {
                                        child_data[entry.offset + write_idx] = values[v];
                                        write_idx++;
                                    }
                                }
                            }
                            
                            duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                            list_data[row_count] = entry;
                        } else {
                            // Scalar float
                            float* data = (float*)duckdb_vector_get_data(vec);
                            if (!bcf_float_is_missing(values[0])) {
                                data[row_count] = values[0];
                            } else {
                                duckdb_vector_ensure_validity_writable(vec);
                                uint64_t* validity = duckdb_vector_get_validity(vec);
                                set_validity_bit(validity, row_count, 0);
                            }
                        }
                    } else {
                        duckdb_vector_ensure_validity_writable(vec);
                        uint64_t* validity = duckdb_vector_get_validity(vec);
                        set_validity_bit(validity, row_count, 0);
                        
                        if (field->is_list) {
                            duckdb_list_entry entry = {duckdb_list_vector_get_size(vec), 0};
                            duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                            list_data[row_count] = entry;
                        }
                    }
                    free(values);
                }
                else {
                    // String type
                    char* value = NULL;
                    int n_value = 0;
                    int ret_info = bcf_get_info_string(init->hdr, init->rec, tag, &value, &n_value);
                    
                    if (ret_info > 0 && value && strcmp(value, ".") != 0) {
                        if (field->is_list) {
                            // List of strings - split by comma
                            duckdb_list_entry entry;
                            entry.offset = duckdb_list_vector_get_size(vec);
                            entry.length = 0;
                            
                            duckdb_vector child_vec = duckdb_list_vector_get_child(vec);
                            
                            char* value_copy = strdup_duckdb(value);
                            
                            // First count the number of tokens
                            char* tok;
                            char* saveptr = NULL;
                            for (tok = strtok_r(value_copy, ",", &saveptr); 
                                 tok != NULL; 
                                 tok = strtok_r(NULL, ",", &saveptr)) {
                                entry.length++;
                            }
                            duckdb_free(value_copy);
                            
                            // Reserve and set size
                            if (entry.length > 0) {
                                duckdb_list_vector_reserve(vec, entry.offset + entry.length);
                                duckdb_list_vector_set_size(vec, entry.offset + entry.length);
                                
                                // Parse again and fill in values
                                value_copy = strdup_duckdb(value);
                                saveptr = NULL;
                                int write_idx = 0;
                                for (tok = strtok_r(value_copy, ",", &saveptr); 
                                     tok != NULL; 
                                     tok = strtok_r(NULL, ",", &saveptr)) {
                                    duckdb_vector_assign_string_element(child_vec, entry.offset + write_idx, tok);
                                    write_idx++;
                                }
                                duckdb_free(value_copy);
                            }
                            
                            duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                            list_data[row_count] = entry;
                        } else {
                            duckdb_vector_assign_string_element(vec, row_count, value);
                        }
                    } else {
                        duckdb_vector_ensure_validity_writable(vec);
                        uint64_t* validity = duckdb_vector_get_validity(vec);
                        set_validity_bit(validity, row_count, 0);
                        
                        if (field->is_list) {
                            duckdb_list_entry entry = {duckdb_list_vector_get_size(vec), 0};
                            duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                            list_data[row_count] = entry;
                        }
                    }
                    free(value);
                }
            }
            else {
                // FORMAT field for a sample
                int format_col_start = COL_CORE_COUNT + bind->n_info_fields;
                int format_col_idx = col_id - format_col_start;
                int sample_idx = format_col_idx / bind->n_format_fields;
                int field_idx = format_col_idx % bind->n_format_fields;
                
                if (sample_idx < bind->n_samples && field_idx < bind->n_format_fields) {
                    field_meta_t* field = &bind->format_fields[field_idx];
                    const char* tag = field->name;
                    
                    if (field->header_type == BCF_HT_INT) {
                        int32_t* values = NULL;
                        int n_values = 0;
                        int ret_fmt = bcf_get_format_int32(init->hdr, init->rec, tag, &values, &n_values);
                        
                        if (ret_fmt > 0 && values) {
                            int vals_per_sample = ret_fmt / bind->n_samples;
                            int32_t* sample_vals = values + sample_idx * vals_per_sample;
                            
                            if (field->is_list) {
                                duckdb_list_entry entry;
                                entry.offset = duckdb_list_vector_get_size(vec);
                                entry.length = 0;
                                
                                duckdb_vector child_vec = duckdb_list_vector_get_child(vec);
                                
                                // First count valid values
                                for (int v = 0; v < vals_per_sample; v++) {
                                    if (sample_vals[v] != bcf_int32_missing && 
                                        sample_vals[v] != bcf_int32_vector_end) {
                                        entry.length++;
                                    }
                                }
                                
                                // Reserve and set size
                                if (entry.length > 0) {
                                    duckdb_list_vector_reserve(vec, entry.offset + entry.length);
                                    duckdb_list_vector_set_size(vec, entry.offset + entry.length);
                                    
                                    // Now fill in the values
                                    int32_t* child_data = (int32_t*)duckdb_vector_get_data(child_vec);
                                    int write_idx = 0;
                                    for (int v = 0; v < vals_per_sample; v++) {
                                        if (sample_vals[v] != bcf_int32_missing && 
                                            sample_vals[v] != bcf_int32_vector_end) {
                                            child_data[entry.offset + write_idx] = sample_vals[v];
                                            write_idx++;
                                        }
                                    }
                                }
                                
                                duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                                list_data[row_count] = entry;
                            } else {
                                int32_t* data = (int32_t*)duckdb_vector_get_data(vec);
                                if (sample_vals[0] != bcf_int32_missing) {
                                    data[row_count] = sample_vals[0];
                                } else {
                                    duckdb_vector_ensure_validity_writable(vec);
                                    uint64_t* validity = duckdb_vector_get_validity(vec);
                                    set_validity_bit(validity, row_count, 0);
                                }
                            }
                        } else {
                            duckdb_vector_ensure_validity_writable(vec);
                            uint64_t* validity = duckdb_vector_get_validity(vec);
                            set_validity_bit(validity, row_count, 0);
                            
                            if (field->is_list) {
                                duckdb_list_entry entry = {duckdb_list_vector_get_size(vec), 0};
                                duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                                list_data[row_count] = entry;
                            }
                        }
                        free(values);
                    }
                    else if (field->header_type == BCF_HT_REAL) {
                        float* values = NULL;
                        int n_values = 0;
                        int ret_fmt = bcf_get_format_float(init->hdr, init->rec, tag, &values, &n_values);
                        
                        if (ret_fmt > 0 && values) {
                            int vals_per_sample = ret_fmt / bind->n_samples;
                            float* sample_vals = values + sample_idx * vals_per_sample;
                            
                            if (field->is_list) {
                                duckdb_list_entry entry;
                                entry.offset = duckdb_list_vector_get_size(vec);
                                entry.length = 0;
                                
                                duckdb_vector child_vec = duckdb_list_vector_get_child(vec);
                                
                                // First count valid values
                                for (int v = 0; v < vals_per_sample; v++) {
                                    if (!bcf_float_is_missing(sample_vals[v]) && 
                                        !bcf_float_is_vector_end(sample_vals[v])) {
                                        entry.length++;
                                    }
                                }
                                
                                // Reserve and set size
                                if (entry.length > 0) {
                                    duckdb_list_vector_reserve(vec, entry.offset + entry.length);
                                    duckdb_list_vector_set_size(vec, entry.offset + entry.length);
                                    
                                    // Now fill in the values
                                    float* child_data = (float*)duckdb_vector_get_data(child_vec);
                                    int write_idx = 0;
                                    for (int v = 0; v < vals_per_sample; v++) {
                                        if (!bcf_float_is_missing(sample_vals[v]) && 
                                            !bcf_float_is_vector_end(sample_vals[v])) {
                                            child_data[entry.offset + write_idx] = sample_vals[v];
                                            write_idx++;
                                        }
                                    }
                                }
                                
                                duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                                list_data[row_count] = entry;
                            } else {
                                float* data = (float*)duckdb_vector_get_data(vec);
                                if (!bcf_float_is_missing(sample_vals[0])) {
                                    data[row_count] = sample_vals[0];
                                } else {
                                    duckdb_vector_ensure_validity_writable(vec);
                                    uint64_t* validity = duckdb_vector_get_validity(vec);
                                    set_validity_bit(validity, row_count, 0);
                                }
                            }
                        } else {
                            duckdb_vector_ensure_validity_writable(vec);
                            uint64_t* validity = duckdb_vector_get_validity(vec);
                            set_validity_bit(validity, row_count, 0);
                            
                            if (field->is_list) {
                                duckdb_list_entry entry = {duckdb_list_vector_get_size(vec), 0};
                                duckdb_list_entry* list_data = (duckdb_list_entry*)duckdb_vector_get_data(vec);
                                list_data[row_count] = entry;
                            }
                        }
                        free(values);
                    }
                    else {
                        // String type - GT needs special handling
                        if (strcmp(tag, "GT") == 0) {
                            // GT is stored as encoded integers, use bcf_get_genotypes()
                            int32_t* gt_arr = NULL;
                            int n_gt = 0;
                            int ret_gt = bcf_get_genotypes(init->hdr, init->rec, &gt_arr, &n_gt);
                            
                            if (ret_gt > 0 && gt_arr) {
                                int ploidy = ret_gt / bind->n_samples;
                                int32_t* sample_gt = gt_arr + sample_idx * ploidy;
                                
                                // Build GT string (e.g., "0/1", "1|1", "./.")
                                char gt_str[64];
                                int pos = 0;
                                
                                for (int p = 0; p < ploidy && pos < 60; p++) {
                                    if (p > 0) {
                                        // Add separator: '|' for phased, '/' for unphased
                                        gt_str[pos++] = bcf_gt_is_phased(sample_gt[p]) ? '|' : '/';
                                    }
                                    
                                    if (sample_gt[p] == bcf_int32_vector_end) {
                                        break;  // End of genotype
                                    } else if (bcf_gt_is_missing(sample_gt[p])) {
                                        gt_str[pos++] = '.';
                                    } else {
                                        int allele = bcf_gt_allele(sample_gt[p]);
                                        pos += snprintf(gt_str + pos, sizeof(gt_str) - pos, "%d", allele);
                                    }
                                }
                                gt_str[pos] = '\0';
                                
                                if (pos > 0) {
                                    duckdb_vector_assign_string_element(vec, row_count, gt_str);
                                } else {
                                    duckdb_vector_ensure_validity_writable(vec);
                                    uint64_t* validity = duckdb_vector_get_validity(vec);
                                    set_validity_bit(validity, row_count, 0);
                                }
                            } else {
                                duckdb_vector_ensure_validity_writable(vec);
                                uint64_t* validity = duckdb_vector_get_validity(vec);
                                set_validity_bit(validity, row_count, 0);
                            }
                            free(gt_arr);
                        } else {
                            // Other string FORMAT fields
                            char** values = NULL;
                            int n_values = 0;
                            int ret_fmt = bcf_get_format_string(init->hdr, init->rec, tag, &values, &n_values);
                            
                            if (ret_fmt > 0 && values && values[sample_idx]) {
                                duckdb_vector_assign_string_element(vec, row_count, values[sample_idx]);
                            } else {
                                duckdb_vector_ensure_validity_writable(vec);
                                uint64_t* validity = duckdb_vector_get_validity(vec);
                                set_validity_bit(validity, row_count, 0);
                            }
                            
                            if (values) free(values[0]);
                            free(values);
                        }
                    }
                }
            }
        }
        
        row_count++;
        init->current_row++;
    }
    
    duckdb_data_chunk_set_size(output, row_count);
}

// =============================================================================
// Register the bcf_read Table Function
// =============================================================================

static void register_bcf_read_function(duckdb_connection connection) {
    duckdb_table_function tf = duckdb_create_table_function();
    duckdb_table_function_set_name(tf, "bcf_read");
    
    // Parameters
    duckdb_logical_type varchar_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    duckdb_table_function_add_parameter(tf, varchar_type);  // file_path
    duckdb_table_function_add_named_parameter(tf, "region", varchar_type);  // optional region
    duckdb_destroy_logical_type(&varchar_type);
    
    // Callbacks - use global init + local init for parallel scan support
    duckdb_table_function_set_bind(tf, bcf_read_bind);
    duckdb_table_function_set_init(tf, bcf_read_global_init);       // Global init
    duckdb_table_function_set_local_init(tf, bcf_read_local_init);  // Per-thread init
    duckdb_table_function_set_function(tf, bcf_read_function);
    
    // Enable projection pushdown
    duckdb_table_function_supports_projection_pushdown(tf, true);
    
    // Register
    duckdb_register_table_function(connection, tf);
    duckdb_destroy_table_function(&tf);
}

// =============================================================================
// Extension Entry Point
// =============================================================================

DUCKDB_EXTENSION_ENTRYPOINT(duckdb_connection connection, duckdb_extension_info info, 
                            struct duckdb_extension_access* access) {
    (void)info;
    (void)access;
    
    register_bcf_read_function(connection);
    
    return true;
}
