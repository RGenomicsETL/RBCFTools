// VCF/BCF to Arrow Stream Integration
// Copyright (c) 2026 RBCFTools Authors
// Licensed under MIT License

#ifndef VCF_ARROW_STREAM_H
#define VCF_ARROW_STREAM_H

#include <htslib/vcf.h>
#include <htslib/hts.h>
#include <htslib/synced_bcf_reader.h>
#include <htslib/tbx.h>
#include <htslib/kstring.h>

// Arrow C Data Interface structures
// (These are also defined in nanoarrow/r.h but we define them here for standalone use)
#ifndef ARROW_C_DATA_INTERFACE
#define ARROW_C_DATA_INTERFACE

#include <stdint.h>

#define ARROW_FLAG_DICTIONARY_ORDERED 1
#define ARROW_FLAG_NULLABLE 2
#define ARROW_FLAG_MAP_KEYS_SORTED 4

struct ArrowSchema {
    const char* format;
    const char* name;
    const char* metadata;
    int64_t flags;
    int64_t n_children;
    struct ArrowSchema** children;
    struct ArrowSchema* dictionary;
    void (*release)(struct ArrowSchema*);
    void* private_data;
};

struct ArrowArray {
    int64_t length;
    int64_t null_count;
    int64_t offset;
    int64_t n_buffers;
    int64_t n_children;
    const void** buffers;
    struct ArrowArray** children;
    struct ArrowArray* dictionary;
    void (*release)(struct ArrowArray*);
    void* private_data;
};

#endif // ARROW_C_DATA_INTERFACE

#ifndef ARROW_C_STREAM_INTERFACE
#define ARROW_C_STREAM_INTERFACE

struct ArrowArrayStream {
    int (*get_schema)(struct ArrowArrayStream*, struct ArrowSchema* out);
    int (*get_next)(struct ArrowArrayStream*, struct ArrowArray* out);
    const char* (*get_last_error)(struct ArrowArrayStream*);
    void (*release)(struct ArrowArrayStream*);
    void* private_data;
};

#endif // ARROW_C_STREAM_INTERFACE

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// VCF Arrow Schema Definition
// =============================================================================

// Standard VCF columns as Arrow types:
// - CHROM: utf8 (string)
// - POS: int64
// - ID: utf8 (string, nullable)
// - REF: utf8 (string)
// - ALT: list<utf8> (list of strings)
// - QUAL: float64 (nullable)
// - FILTER: list<utf8> (list of strings)
// - INFO: struct (dynamic based on header)
// - FORMAT/samples: struct of lists (dynamic based on header)

// Options for configuring the VCF stream
typedef struct {
    int64_t batch_size;           // Number of records per batch (default: 10000)
    int include_info;             // Include INFO fields (default: 1)
    int include_format;           // Include FORMAT/sample fields (default: 1)
    const char* region;           // Region filter (e.g., "chr1:1000-2000")
    const char* samples;          // Sample filter (comma-separated or file)
    const char* index;            // Index file path (NULL for auto-detection)
                                  // VCF: tries .tbi first, then .csi
                                  // BCF: uses .csi only
    int threads;                  // Number of threads for decompression
} vcf_arrow_options_t;

// Private data for the VCF stream
typedef struct {
    htsFile* fp;                  // VCF/BCF file handle
    bcf_hdr_t* hdr;               // VCF header
    bcf1_t* rec;                  // Current record (reusable)
    hts_idx_t* idx;               // Index (for region queries)
    tbx_t* tbx;                   // Tabix index (for VCF files)
    hts_itr_t* itr;               // Iterator (for region queries)
    kstring_t kstr;               // String buffer for tbx_itr_next (VCF text parsing)
    vcf_arrow_options_t opts;     // Options
    char error_msg[256];          // Last error message
    int finished;                 // Stream finished flag
    
    // Schema cache
    struct ArrowSchema* cached_schema;
    
    // Buffer management for batch building
    // These grow as needed during batch construction
    size_t chrom_buf_size;
    char** chrom_data;
    int32_t* chrom_offsets;
    
    size_t pos_buf_size;
    int64_t* pos_data;
    
    size_t id_buf_size;
    char** id_data;
    int32_t* id_offsets;
    uint8_t* id_validity;
    
    size_t ref_buf_size;
    char** ref_data;
    int32_t* ref_offsets;
    
    // ALT as list<string>
    size_t alt_buf_size;
    char** alt_data;
    int32_t* alt_offsets;
    int32_t* alt_list_offsets;
    
    size_t qual_buf_size;
    double* qual_data;
    uint8_t* qual_validity;
    
    // Filter as list<string>
    size_t filter_buf_size;
    char** filter_data;
    int32_t* filter_offsets;
    int32_t* filter_list_offsets;
    
} vcf_arrow_private_t;

// =============================================================================
// Public API
// =============================================================================

/**
 * @brief Initialize default options
 * @param opts Options structure to initialize
 */
void vcf_arrow_options_init(vcf_arrow_options_t* opts);

/**
 * @brief Create a VCF/BCF to Arrow stream
 * 
 * This creates an ArrowArrayStream that reads VCF/BCF records and produces
 * Arrow record batches. The stream can be consumed by any Arrow-compatible
 * library (nanoarrow, pyarrow, arrow-rs, etc.)
 * 
 * @param stream Output stream (must be pre-allocated)
 * @param filename Path to VCF/BCF file. Supports htslib ##idx## syntax for 
 *                 non-standard index locations (e.g., "file.vcf.gz##idx##custom.tbi")
 * @param opts Options (NULL for defaults)
 * @return 0 on success, non-zero on error
 * 
 * @note Index files (.tbi for VCF, .csi for BCF) are only required for region queries.
 *       For whole-file streaming, no index is needed.
 * 
 * @note Non-standard index paths can be specified either via:
 *       1. opts.index parameter, or
 *       2. Using htslib ##idx## syntax in filename (e.g., "file.vcf.gz##idx##path/to/index.tbi")
 *       Useful for presigned URLs or non-standard index locations.
 * 
 * Example usage:
 * @code
 * struct ArrowArrayStream stream;
 * vcf_arrow_options_t opts;
 * vcf_arrow_options_init(&opts);
 * opts.batch_size = 50000;
 * opts.region = "chr1:1-1000000";
 * 
 * if (vcf_arrow_stream_init(&stream, "input.vcf.gz", &opts) == 0) {
 *     struct ArrowSchema schema;
 *     stream.get_schema(&stream, &schema);
 *     
 *     struct ArrowArray batch;
 *     while (stream.get_next(&stream, &batch) == 0 && batch.release != NULL) {
 *         // Process batch...
 *         batch.release(&batch);
 *     }
 *     stream.release(&stream);
 * }
 * @endcode
 */
int vcf_arrow_stream_init(struct ArrowArrayStream* stream,
                          const char* filename,
                          const vcf_arrow_options_t* opts);

/**
 * @brief Get the VCF schema as an Arrow schema
 * 
 * Creates an Arrow schema representing the VCF structure. The schema includes:
 * - Core VCF columns (CHROM, POS, ID, REF, ALT, QUAL, FILTER)
 * - INFO fields (if include_info is set)
 * - FORMAT/sample data (if include_format is set)
 * 
 * @param hdr VCF header
 * @param schema Output schema
 * @param opts Options
 * @return 0 on success
 */
int vcf_arrow_schema_from_header(const bcf_hdr_t* hdr,
                                  struct ArrowSchema* schema,
                                  const vcf_arrow_options_t* opts);

/**
 * @brief Convert a batch of VCF records to an Arrow array
 * 
 * Reads up to batch_size records and converts them to an Arrow record batch.
 * 
 * @param fp File handle
 * @param hdr Header
 * @param itr Iterator (can be NULL for sequential reading)
 * @param batch_size Maximum records to read
 * @param array Output array
 * @param opts Options
 * @return Number of records read, or negative on error
 */
int vcf_arrow_read_batch(htsFile* fp,
                         bcf_hdr_t* hdr,
                         hts_itr_t* itr,
                         int64_t batch_size,
                         struct ArrowArray* array,
                         const vcf_arrow_options_t* opts);

#ifdef __cplusplus
}
#endif

#endif // VCF_ARROW_STREAM_H
