/**
 * DuckDB BCF/VCF Reader Extension
 * 
 * Self-contained extension that provides a table function to read BCF/VCF files.
 * 
 * Usage:
 *   LOAD 'bcf_reader.duckdb_extension';
 *   SELECT * FROM bcf_read('path/to/file.vcf.gz');
 *   SELECT * FROM bcf_read('path/to/file.bcf', region := 'chr1:1000-2000');
 *
 * Build:
 *   make
 *
 * Requirements:
 *   - htslib (libhts-dev)
 *   - DuckDB v1.2.0+
 */

// Must define before including duckdb_extension.h
#define DUCKDB_EXTENSION_NAME bcf_reader

#include "duckdb_extension.h"

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// htslib headers
#include <htslib/vcf.h>
#include <htslib/hts.h>
#include <htslib/synced_bcf_reader.h>

// Required macro for DuckDB C extensions
DUCKDB_EXTENSION_EXTERN

//===--------------------------------------------------------------------===//
// Bind Data - stores parameters from the function call
//===--------------------------------------------------------------------===//
typedef struct {
    char *file_path;
    char *region;        // Optional region filter (e.g., "chr1:1000-2000")
    int include_info;    // Whether to include INFO fields
    int include_format;  // Whether to include FORMAT fields
    int n_samples;       // Number of samples in the file
} bcf_bind_data_t;

//===--------------------------------------------------------------------===//
// Init Data - stores state during scanning
//===--------------------------------------------------------------------===//
typedef struct {
    htsFile *fp;
    bcf_hdr_t *hdr;
    bcf1_t *rec;
    hts_idx_t *idx;
    hts_itr_t *itr;
    int64_t current_row;
    int done;
    // Projection pushdown support
    idx_t column_count;        // Number of columns requested
    idx_t *column_ids;         // Original column indices that were requested
} bcf_init_data_t;

//===--------------------------------------------------------------------===//
// Helper: Destroy bind data
//===--------------------------------------------------------------------===//
static void destroy_bind_data(void *data) {
    bcf_bind_data_t *bind = (bcf_bind_data_t *)data;
    if (bind) {
        if (bind->file_path) duckdb_free(bind->file_path);
        if (bind->region) duckdb_free(bind->region);
        duckdb_free(bind);
    }
}

//===--------------------------------------------------------------------===//
// Helper: Destroy init data
//===--------------------------------------------------------------------===//
static void destroy_init_data(void *data) {
    bcf_init_data_t *init = (bcf_init_data_t *)data;
    if (init) {
        if (init->itr) hts_itr_destroy(init->itr);
        if (init->idx) hts_idx_destroy(init->idx);
        if (init->rec) bcf_destroy(init->rec);
        if (init->hdr) bcf_hdr_destroy(init->hdr);
        if (init->fp) hts_close(init->fp);
        if (init->column_ids) duckdb_free(init->column_ids);
        duckdb_free(init);
    }
}

//===--------------------------------------------------------------------===//
// Bind Function - called once to set up the table schema
//===--------------------------------------------------------------------===//
static void bcf_read_bind(duckdb_bind_info info) {
    // Get the file path parameter
    duckdb_value path_val = duckdb_bind_get_parameter(info, 0);
    char *file_path = duckdb_get_varchar(path_val);
    duckdb_destroy_value(&path_val);
    
    if (!file_path || strlen(file_path) == 0) {
        duckdb_bind_set_error(info, "bcf_read requires a file path");
        if (file_path) duckdb_free(file_path);
        return;
    }
    
    // Get optional region parameter
    char *region = NULL;
    if (duckdb_bind_get_parameter_count(info) > 1) {
        duckdb_value region_val = duckdb_bind_get_parameter(info, 1);
        if (!duckdb_is_null_value(region_val)) {
            region = duckdb_get_varchar(region_val);
        }
        duckdb_destroy_value(&region_val);
    }
    
    // Open the file to read the header and determine schema
    htsFile *fp = hts_open(file_path, "r");
    if (!fp) {
        duckdb_bind_set_error(info, "Failed to open BCF/VCF file");
        duckdb_free(file_path);
        if (region) duckdb_free(region);
        return;
    }
    
    bcf_hdr_t *hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        duckdb_bind_set_error(info, "Failed to read BCF/VCF header");
        duckdb_free(file_path);
        if (region) duckdb_free(region);
        return;
    }
    
    int n_samples = bcf_hdr_nsamples(hdr);
    
    // Create bind data
    bcf_bind_data_t *bind_data = (bcf_bind_data_t *)duckdb_malloc(sizeof(bcf_bind_data_t));
    bind_data->file_path = file_path;
    bind_data->region = region;
    bind_data->include_info = 1;
    bind_data->include_format = 1;
    bind_data->n_samples = n_samples;
    
    // Add result columns - core VCF fields
    duckdb_logical_type varchar_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    duckdb_logical_type bigint_type = duckdb_create_logical_type(DUCKDB_TYPE_BIGINT);
    duckdb_logical_type float_type = duckdb_create_logical_type(DUCKDB_TYPE_FLOAT);
    
    // Core VCF columns (0-7)
    duckdb_bind_add_result_column(info, "CHROM", varchar_type);   // 0
    duckdb_bind_add_result_column(info, "POS", bigint_type);       // 1
    duckdb_bind_add_result_column(info, "ID", varchar_type);       // 2
    duckdb_bind_add_result_column(info, "REF", varchar_type);      // 3
    duckdb_bind_add_result_column(info, "ALT", varchar_type);      // 4
    duckdb_bind_add_result_column(info, "QUAL", float_type);       // 5
    duckdb_bind_add_result_column(info, "FILTER", varchar_type);   // 6
    duckdb_bind_add_result_column(info, "INFO", varchar_type);     // 7
    
    // Add sample columns for GT (genotype) if samples exist (8+)
    if (n_samples > 0) {
        for (int i = 0; i < n_samples; i++) {
            const char *sample_name = hdr->samples[i];
            char col_name[256];
            snprintf(col_name, sizeof(col_name), "GT_%s", sample_name);
            duckdb_bind_add_result_column(info, col_name, varchar_type);
        }
    }
    
    // Cleanup types
    duckdb_destroy_logical_type(&varchar_type);
    duckdb_destroy_logical_type(&bigint_type);
    duckdb_destroy_logical_type(&float_type);
    
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    // Set bind data
    duckdb_bind_set_bind_data(info, bind_data, destroy_bind_data);
}

//===--------------------------------------------------------------------===//
// Init Function - called to initialize scanning state
//===--------------------------------------------------------------------===//
static void bcf_read_init(duckdb_init_info info) {
    bcf_bind_data_t *bind_data = (bcf_bind_data_t *)duckdb_init_get_bind_data(info);
    
    bcf_init_data_t *init_data = (bcf_init_data_t *)duckdb_malloc(sizeof(bcf_init_data_t));
    memset(init_data, 0, sizeof(bcf_init_data_t));
    
    // Open the file
    init_data->fp = hts_open(bind_data->file_path, "r");
    if (!init_data->fp) {
        duckdb_init_set_error(info, "Failed to open BCF/VCF file");
        duckdb_free(init_data);
        return;
    }
    
    // Read header
    init_data->hdr = bcf_hdr_read(init_data->fp);
    if (!init_data->hdr) {
        hts_close(init_data->fp);
        duckdb_init_set_error(info, "Failed to read BCF/VCF header");
        duckdb_free(init_data);
        return;
    }
    
    // Allocate record
    init_data->rec = bcf_init();
    
    // Set up region iterator if specified
    if (bind_data->region && strlen(bind_data->region) > 0) {
        init_data->idx = bcf_index_load(bind_data->file_path);
        if (init_data->idx) {
            init_data->itr = bcf_itr_querys(init_data->idx, init_data->hdr, bind_data->region);
        }
    }
    
    init_data->current_row = 0;
    init_data->done = 0;
    
    // Get projection pushdown info - which columns are requested
    init_data->column_count = duckdb_init_get_column_count(info);
    init_data->column_ids = (idx_t *)duckdb_malloc(sizeof(idx_t) * init_data->column_count);
    for (idx_t i = 0; i < init_data->column_count; i++) {
        init_data->column_ids[i] = duckdb_init_get_column_index(info, i);
    }
    
    duckdb_init_set_init_data(info, init_data, destroy_init_data);
}

//===--------------------------------------------------------------------===//
// Main Function - called repeatedly to fetch data chunks
//===--------------------------------------------------------------------===//
static void bcf_read_function(duckdb_function_info info, duckdb_data_chunk output) {
    bcf_init_data_t *init_data = (bcf_init_data_t *)duckdb_function_get_init_data(info);
    
    if (!init_data || init_data->done) {
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    
    idx_t vector_size = duckdb_vector_size();
    idx_t row_count = 0;
    
    // Get n_samples from init_data header
    int n_samples = bcf_hdr_nsamples(init_data->hdr);
    
    // Read records
    int ret;
    while (row_count < vector_size) {
        // Read next record
        if (init_data->itr) {
            ret = bcf_itr_next(init_data->fp, init_data->itr, init_data->rec);
        } else {
            ret = bcf_read(init_data->fp, init_data->hdr, init_data->rec);
        }
        
        if (ret < 0) {
            init_data->done = 1;
            break;
        }
        
        // Verify record is valid before accessing
        if (!init_data->rec) {
            init_data->done = 1;
            break;
        }
        
        // Unpack the record
        bcf_unpack(init_data->rec, BCF_UN_ALL);
        
        // Only process columns that were requested (projection pushdown)
        for (idx_t i = 0; i < init_data->column_count; i++) {
            idx_t col_id = init_data->column_ids[i];
            duckdb_vector vec = duckdb_data_chunk_get_vector(output, i);
            
            if (col_id == 0) {
                // CHROM
                const char *chrom = bcf_hdr_id2name(init_data->hdr, init_data->rec->rid);
                duckdb_vector_assign_string_element(vec, row_count, chrom ? chrom : ".");
            } else if (col_id == 1) {
                // POS (1-based)
                int64_t *pos_data = (int64_t *)duckdb_vector_get_data(vec);
                pos_data[row_count] = init_data->rec->pos + 1;
            } else if (col_id == 2) {
                // ID
                const char *id = init_data->rec->d.id;
                duckdb_vector_assign_string_element(vec, row_count, id ? id : ".");
            } else if (col_id == 3) {
                // REF
                const char *ref = init_data->rec->d.allele[0];
                duckdb_vector_assign_string_element(vec, row_count, ref ? ref : ".");
            } else if (col_id == 4) {
                // ALT (comma-separated)
                if (init_data->rec->n_allele > 1) {
                    size_t alt_len = 0;
                    for (int j = 1; j < init_data->rec->n_allele; j++) {
                        alt_len += strlen(init_data->rec->d.allele[j]) + 1;
                    }
                    char *alt_str = (char *)duckdb_malloc(alt_len + 1);
                    alt_str[0] = '\0';
                    for (int j = 1; j < init_data->rec->n_allele; j++) {
                        if (j > 1) strcat(alt_str, ",");
                        strcat(alt_str, init_data->rec->d.allele[j]);
                    }
                    duckdb_vector_assign_string_element(vec, row_count, alt_str);
                    duckdb_free(alt_str);
                } else {
                    duckdb_vector_assign_string_element(vec, row_count, ".");
                }
            } else if (col_id == 5) {
                // QUAL
                float *qual_data = (float *)duckdb_vector_get_data(vec);
                qual_data[row_count] = init_data->rec->qual;
            } else if (col_id == 6) {
                // FILTER
                if (init_data->rec->d.n_flt > 0) {
                    char filter_str[1024] = "";
                    for (int j = 0; j < init_data->rec->d.n_flt; j++) {
                        if (j > 0) strcat(filter_str, ";");
                        strcat(filter_str, bcf_hdr_int2id(init_data->hdr, BCF_DT_ID, init_data->rec->d.flt[j]));
                    }
                    duckdb_vector_assign_string_element(vec, row_count, filter_str);
                } else {
                    duckdb_vector_assign_string_element(vec, row_count, "PASS");
                }
            } else if (col_id == 7) {
                // INFO (placeholder)
                duckdb_vector_assign_string_element(vec, row_count, ".");
            } else if (col_id >= 8 && (int)(col_id - 8) < n_samples) {
                // Genotype columns (GT_<sample>)
                int sample_idx = (int)(col_id - 8);
                int32_t *gt_arr = NULL;
                int n_gt = 0;
                int n_gt_arr = 0;
                
                n_gt = bcf_get_genotypes(init_data->hdr, init_data->rec, &gt_arr, &n_gt_arr);
                
                if (n_gt > 0) {
                    int ploidy = n_gt / n_samples;
                    char gt_str[64] = "";
                    
                    for (int p = 0; p < ploidy; p++) {
                        int32_t allele = gt_arr[sample_idx * ploidy + p];
                        if (bcf_gt_is_missing(allele)) {
                            strcat(gt_str, p > 0 ? "/." : ".");
                        } else {
                            char allele_str[16];
                            snprintf(allele_str, sizeof(allele_str), "%s%d", 
                                     p > 0 ? (bcf_gt_is_phased(allele) ? "|" : "/") : "",
                                     bcf_gt_allele(allele));
                            strcat(gt_str, allele_str);
                        }
                    }
                    duckdb_vector_assign_string_element(vec, row_count, gt_str);
                } else {
                    duckdb_vector_assign_string_element(vec, row_count, "./.");
                }
                
                if (gt_arr) free(gt_arr);
            }
        }
        
        row_count++;
        init_data->current_row++;
    }
    
    duckdb_data_chunk_set_size(output, row_count);
}

//===--------------------------------------------------------------------===//
// Register the bcf_read table function
//===--------------------------------------------------------------------===//
static void register_bcf_read_function(duckdb_connection connection) {
    // Create the bcf_read table function
    duckdb_table_function tf = duckdb_create_table_function();
    duckdb_table_function_set_name(tf, "bcf_read");
    
    // Add parameters
    duckdb_logical_type varchar_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    duckdb_table_function_add_parameter(tf, varchar_type);  // file_path
    duckdb_table_function_add_named_parameter(tf, "region", varchar_type);  // optional region
    duckdb_destroy_logical_type(&varchar_type);
    
    // Set callbacks
    duckdb_table_function_set_bind(tf, bcf_read_bind);
    duckdb_table_function_set_init(tf, bcf_read_init);
    duckdb_table_function_set_function(tf, bcf_read_function);
    
    // Enable projection pushdown for efficient queries like SELECT COUNT(*)
    duckdb_table_function_supports_projection_pushdown(tf, true);
    
    // Register the function
    duckdb_register_table_function(connection, tf);
    duckdb_destroy_table_function(&tf);
}

//===--------------------------------------------------------------------===//
// Extension Entry Point
//===--------------------------------------------------------------------===//
DUCKDB_EXTENSION_ENTRYPOINT(duckdb_connection connection, duckdb_extension_info info, struct duckdb_extension_access *access) {
    // Register the BCF/VCF reader function
    register_bcf_read_function(connection);
    
    // Return true to indicate successful initialization
    return true;
}
