// R interface for VCF/BCF to Arrow Stream
// Uses nanoarrow R package for Arrow integration
// Copyright (c) 2026 RBCFTools Authors

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include "vcf_arrow_stream.h"

// Include nanoarrow R header for external pointer handling
// This header is available when LinkingTo: nanoarrow
#include <nanoarrow/r.h>

// =============================================================================
// R-callable Functions
// =============================================================================

/**
 * Create a VCF to Arrow stream
 * 
 * @param filename_sexp Path to VCF/BCF file
 * @param batch_size_sexp Batch size
 * @param region_sexp Region string (or R_NilValue)
 * @param samples_sexp Sample filter string (or R_NilValue)
 * @param include_info_sexp Include INFO fields
 * @param include_format_sexp Include FORMAT fields
 * @param index_sexp Index file path (or R_NilValue)
 * @param threads_sexp Number of threads
 * @param parse_vep_sexp Enable VEP parsing
 * @param vep_tag_sexp VEP tag (CSQ, BCSQ, ANN) or R_NilValue for auto-detect
 * @param vep_columns_sexp Comma-separated VEP columns or R_NilValue for all
 * @param vep_transcript_mode_sexp 0=all, 1=first
 * @return nanoarrow_array_stream external pointer
 */
SEXP vcf_to_arrow_stream(SEXP filename_sexp, SEXP batch_size_sexp,
                         SEXP region_sexp, SEXP samples_sexp,
                         SEXP include_info_sexp, SEXP include_format_sexp,
                         SEXP index_sexp, SEXP threads_sexp,
                         SEXP parse_vep_sexp, SEXP vep_tag_sexp,
                         SEXP vep_columns_sexp, SEXP vep_transcript_mode_sexp) {
    // Validate inputs
    if (TYPEOF(filename_sexp) != STRSXP || Rf_length(filename_sexp) != 1) {
        Rf_error("filename must be a single character string");
    }
    
    const char* filename = CHAR(STRING_ELT(filename_sexp, 0));
    
    // Set up options
    vcf_arrow_options_t opts;
    vcf_arrow_options_init(&opts);
    
    if (!Rf_isNull(batch_size_sexp)) {
        opts.batch_size = Rf_asInteger(batch_size_sexp);
        if (opts.batch_size <= 0) {
            Rf_error("batch_size must be positive");
        }
    }
    
    if (!Rf_isNull(region_sexp) && TYPEOF(region_sexp) == STRSXP) {
        opts.region = CHAR(STRING_ELT(region_sexp, 0));
    }
    
    if (!Rf_isNull(index_sexp) && TYPEOF(index_sexp) == STRSXP) {
        opts.index = CHAR(STRING_ELT(index_sexp, 0));
    }
    
    if (!Rf_isNull(samples_sexp) && TYPEOF(samples_sexp) == STRSXP) {
        opts.samples = CHAR(STRING_ELT(samples_sexp, 0));
    }
    
    if (!Rf_isNull(include_info_sexp)) {
        opts.include_info = Rf_asLogical(include_info_sexp);
    }
    
    if (!Rf_isNull(include_format_sexp)) {
        opts.include_format = Rf_asLogical(include_format_sexp);
    }
    
    if (!Rf_isNull(threads_sexp)) {
        opts.threads = Rf_asInteger(threads_sexp);
    }
    
    // VEP parsing options
    if (!Rf_isNull(parse_vep_sexp)) {
        opts.parse_vep = Rf_asLogical(parse_vep_sexp);
    }
    
    if (!Rf_isNull(vep_tag_sexp) && TYPEOF(vep_tag_sexp) == STRSXP) {
        opts.vep_tag = CHAR(STRING_ELT(vep_tag_sexp, 0));
    }
    
    if (!Rf_isNull(vep_columns_sexp) && TYPEOF(vep_columns_sexp) == STRSXP) {
        opts.vep_columns = CHAR(STRING_ELT(vep_columns_sexp, 0));
    }
    
    if (!Rf_isNull(vep_transcript_mode_sexp)) {
        opts.vep_transcript_mode = Rf_asInteger(vep_transcript_mode_sexp);
    }
    
    // Create the stream external pointer using nanoarrow's helper
    SEXP stream_xptr = PROTECT(nanoarrow_array_stream_owning_xptr());
    struct ArrowArrayStream* stream = nanoarrow_output_array_stream_from_xptr(stream_xptr);
    
    // Initialize the VCF stream
    int ret = vcf_arrow_stream_init(stream, filename, &opts);
    if (ret != 0) {
        const char* errmsg = "unknown error";
        if (stream->get_last_error) {
            const char* last_err = stream->get_last_error(stream);
            if (last_err && last_err[0]) {
                errmsg = last_err;
            }
        }
        UNPROTECT(1);
        Rf_error("Failed to initialize VCF stream: %s", errmsg);
    }
    
    UNPROTECT(1);
    return stream_xptr;
}

/**
 * Get schema from a VCF file
 * 
 * @param filename_sexp Path to VCF/BCF file
 * @return nanoarrow_schema external pointer
 */
SEXP vcf_arrow_get_schema(SEXP filename_sexp) {
    if (TYPEOF(filename_sexp) != STRSXP || Rf_length(filename_sexp) != 1) {
        Rf_error("filename must be a single character string");
    }
    
    const char* filename = CHAR(STRING_ELT(filename_sexp, 0));
    
    // Open file to read header
    htsFile* fp = hts_open(filename, "r");
    if (!fp) {
        Rf_error("Failed to open file: %s", filename);
    }
    
    bcf_hdr_t* hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        Rf_error("Failed to read VCF header");
    }
    
    // Create schema external pointer
    SEXP schema_xptr = PROTECT(nanoarrow_schema_owning_xptr());
    struct ArrowSchema* schema = nanoarrow_output_schema_from_xptr(schema_xptr);
    
    vcf_arrow_options_t opts;
    vcf_arrow_options_init(&opts);
    
    int ret = vcf_arrow_schema_from_header(hdr, schema, &opts);
    
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    if (ret != 0) {
        UNPROTECT(1);
        Rf_error("Failed to create schema from VCF header");
    }
    
    UNPROTECT(1);
    return schema_xptr;
}

/**
 * Read a single batch from VCF as Arrow array
 * 
 * @param stream_xptr Arrow array stream external pointer
 * @return nanoarrow_array external pointer (or R_NilValue if stream ended)
 */
SEXP vcf_arrow_read_next_batch(SEXP stream_xptr) {
    struct ArrowArrayStream* stream = nanoarrow_array_stream_from_xptr(stream_xptr);
    
    SEXP array_xptr = PROTECT(nanoarrow_array_owning_xptr());
    struct ArrowArray* array = nanoarrow_output_array_from_xptr(array_xptr);
    
    int ret = stream->get_next(stream, array);
    if (ret != 0) {
        UNPROTECT(1);
        Rf_error("Error reading batch: %s", 
                 stream->get_last_error ? stream->get_last_error(stream) : "unknown error");
    }
    
    // Check if stream is exhausted
    if (array->release == NULL) {
        UNPROTECT(1);
        return R_NilValue;
    }
    
    UNPROTECT(1);
    return array_xptr;
}

/**
 * Read all batches from VCF stream as a list
 * 
 * @param stream_xptr Arrow array stream external pointer
 * @param max_batches_sexp Maximum batches to read (or NULL for unlimited)
 * @return List of nanoarrow_array external pointers
 */
SEXP vcf_arrow_collect_batches(SEXP stream_xptr, SEXP max_batches_sexp) {
    struct ArrowArrayStream* stream = nanoarrow_array_stream_from_xptr(stream_xptr);
    
    int max_batches = -1;
    if (!Rf_isNull(max_batches_sexp)) {
        max_batches = Rf_asInteger(max_batches_sexp);
    }
    
    // Start with capacity for 10 batches, grow as needed
    int capacity = 10;
    int n_batches = 0;
    SEXP batches = PROTECT(Rf_allocVector(VECSXP, capacity));
    
    while (max_batches < 0 || n_batches < max_batches) {
        SEXP array_xptr = PROTECT(nanoarrow_array_owning_xptr());
        struct ArrowArray* array = nanoarrow_output_array_from_xptr(array_xptr);
        
        int ret = stream->get_next(stream, array);
        if (ret != 0) {
            UNPROTECT(n_batches + 2);  // array_xptr + all previous + batches
            Rf_error("Error reading batch: %s",
                     stream->get_last_error ? stream->get_last_error(stream) : "unknown error");
        }
        
        if (array->release == NULL) {
            // Stream exhausted
            UNPROTECT(1);  // array_xptr
            break;
        }
        
        // Grow list if needed
        if (n_batches >= capacity) {
            capacity *= 2;
            SEXP new_batches = PROTECT(Rf_allocVector(VECSXP, capacity));
            for (int i = 0; i < n_batches; i++) {
                SET_VECTOR_ELT(new_batches, i, VECTOR_ELT(batches, i));
            }
            UNPROTECT(2);  // new_batches and old batches
            batches = PROTECT(new_batches);
        }
        
        SET_VECTOR_ELT(batches, n_batches, array_xptr);
        n_batches++;
        // Keep array_xptr protected until we're done
    }
    
    // Trim list to actual size
    if (n_batches < capacity) {
        SEXP result = PROTECT(Rf_allocVector(VECSXP, n_batches));
        for (int i = 0; i < n_batches; i++) {
            SET_VECTOR_ELT(result, i, VECTOR_ELT(batches, i));
        }
        UNPROTECT(n_batches + 2);  // result + all array_xptrs + batches
        return result;
    }
    
    UNPROTECT(n_batches + 1);  // all array_xptrs + batches
    return batches;
}
