// VCF/BCF to Arrow Stream Implementation
// Copyright (c) 2026 RBCFTools Authors
// Licensed under MIT License

#include "vcf_arrow_stream.h"
#include <stdlib.h>
#include <string.h>
#include <errno.h>

// =============================================================================
// Helper Macros and Constants
// =============================================================================

#define VCF_ARROW_DEFAULT_BATCH_SIZE 10000
#define VCF_ARROW_INITIAL_STRING_BUF 4096

#define RETURN_IF_ERROR(expr) do { int __ret = (expr); if (__ret != 0) return __ret; } while(0)

// Arrow format strings
#define ARROW_FORMAT_INT8    "c"
#define ARROW_FORMAT_INT16   "s"
#define ARROW_FORMAT_INT32   "i"
#define ARROW_FORMAT_INT64   "l"
#define ARROW_FORMAT_UINT8   "C"
#define ARROW_FORMAT_UINT16  "S"
#define ARROW_FORMAT_UINT32  "I"
#define ARROW_FORMAT_UINT64  "L"
#define ARROW_FORMAT_FLOAT32 "f"
#define ARROW_FORMAT_FLOAT64 "g"
#define ARROW_FORMAT_UTF8    "u"
#define ARROW_FORMAT_BINARY  "z"
#define ARROW_FORMAT_STRUCT  "+s"
#define ARROW_FORMAT_LIST    "+l"

// =============================================================================
// Memory Management Helpers
// =============================================================================

static void* vcf_arrow_malloc(size_t size) {
    return malloc(size);
}

static void* vcf_arrow_realloc(void* ptr, size_t size) {
    return realloc(ptr, size);
}

static void vcf_arrow_free(void* ptr) {
    free(ptr);
}

static char* vcf_arrow_strdup(const char* s) {
    if (s == NULL) return NULL;
    size_t len = strlen(s) + 1;
    char* copy = (char*)vcf_arrow_malloc(len);
    if (copy) memcpy(copy, s, len);
    return copy;
}

// =============================================================================
// Schema Release Functions
// =============================================================================

static void release_schema_simple(struct ArrowSchema* schema) {
    if (schema->format) vcf_arrow_free((void*)schema->format);
    if (schema->name) vcf_arrow_free((void*)schema->name);
    if (schema->metadata) vcf_arrow_free((void*)schema->metadata);
    
    if (schema->children) {
        for (int64_t i = 0; i < schema->n_children; i++) {
            if (schema->children[i] && schema->children[i]->release) {
                schema->children[i]->release(schema->children[i]);
            }
            vcf_arrow_free(schema->children[i]);
        }
        vcf_arrow_free(schema->children);
    }
    
    if (schema->dictionary && schema->dictionary->release) {
        schema->dictionary->release(schema->dictionary);
        vcf_arrow_free(schema->dictionary);
    }
    
    schema->release = NULL;
}

// =============================================================================
// Array Release Functions
// =============================================================================

// Private data structure for managing array memory
typedef struct {
    void** buffers_to_free;
    int n_buffers_to_free;
    struct ArrowArray** children_to_free;
    int n_children_to_free;
} array_private_data_t;

static void release_array_simple(struct ArrowArray* array) {
    if (array->buffers) {
        // The first buffer is typically the validity bitmap
        for (int64_t i = 0; i < array->n_buffers; i++) {
            if (array->buffers[i]) {
                vcf_arrow_free((void*)array->buffers[i]);
            }
        }
        vcf_arrow_free(array->buffers);
    }
    
    if (array->children) {
        for (int64_t i = 0; i < array->n_children; i++) {
            if (array->children[i] && array->children[i]->release) {
                array->children[i]->release(array->children[i]);
            }
            vcf_arrow_free(array->children[i]);
        }
        vcf_arrow_free(array->children);
    }
    
    if (array->dictionary && array->dictionary->release) {
        array->dictionary->release(array->dictionary);
        vcf_arrow_free(array->dictionary);
    }
    
    if (array->private_data) {
        vcf_arrow_free(array->private_data);
    }
    
    array->release = NULL;
}

// =============================================================================
// Schema Building Helpers
// =============================================================================

static int init_schema_field(struct ArrowSchema* schema, const char* format, 
                             const char* name, int64_t flags) {
    memset(schema, 0, sizeof(*schema));
    schema->format = vcf_arrow_strdup(format);
    schema->name = vcf_arrow_strdup(name);
    schema->flags = flags;
    schema->n_children = 0;
    schema->children = NULL;
    schema->dictionary = NULL;
    schema->metadata = NULL;
    schema->release = &release_schema_simple;
    schema->private_data = NULL;
    
    if (!schema->format || !schema->name) {
        release_schema_simple(schema);
        return ENOMEM;
    }
    return 0;
}

static int init_schema_struct(struct ArrowSchema* schema, const char* name, 
                              int64_t n_children) {
    RETURN_IF_ERROR(init_schema_field(schema, ARROW_FORMAT_STRUCT, name, 0));
    
    schema->n_children = n_children;
    schema->children = (struct ArrowSchema**)vcf_arrow_malloc(
        n_children * sizeof(struct ArrowSchema*));
    if (!schema->children) {
        release_schema_simple(schema);
        return ENOMEM;
    }
    
    for (int64_t i = 0; i < n_children; i++) {
        schema->children[i] = (struct ArrowSchema*)vcf_arrow_malloc(sizeof(struct ArrowSchema));
        if (!schema->children[i]) {
            release_schema_simple(schema);
            return ENOMEM;
        }
        memset(schema->children[i], 0, sizeof(struct ArrowSchema));
    }
    
    return 0;
}

static int init_schema_list(struct ArrowSchema* schema, const char* name,
                            const char* child_format, const char* child_name) {
    RETURN_IF_ERROR(init_schema_field(schema, ARROW_FORMAT_LIST, name, ARROW_FLAG_NULLABLE));
    
    schema->n_children = 1;
    schema->children = (struct ArrowSchema**)vcf_arrow_malloc(sizeof(struct ArrowSchema*));
    if (!schema->children) {
        release_schema_simple(schema);
        return ENOMEM;
    }
    
    schema->children[0] = (struct ArrowSchema*)vcf_arrow_malloc(sizeof(struct ArrowSchema));
    if (!schema->children[0]) {
        release_schema_simple(schema);
        return ENOMEM;
    }
    
    return init_schema_field(schema->children[0], child_format, child_name, 0);
}

// =============================================================================
// VCF to Arrow Type Mapping
// =============================================================================

// Map BCF header type to Arrow format string
static const char* bcf_type_to_arrow_format(int type, int number) {
    switch (type) {
        case BCF_HT_FLAG:
            return "b";  // boolean
        case BCF_HT_INT:
            return ARROW_FORMAT_INT32;
        case BCF_HT_REAL:
            return ARROW_FORMAT_FLOAT32;
        case BCF_HT_STR:
            return ARROW_FORMAT_UTF8;
        default:
            return ARROW_FORMAT_UTF8;  // fallback
    }
}

// =============================================================================
// Core Schema Creation
// =============================================================================

int vcf_arrow_schema_from_header(const bcf_hdr_t* hdr,
                                  struct ArrowSchema* schema,
                                  const vcf_arrow_options_t* opts) {
    // Core VCF fields: CHROM, POS, ID, REF, ALT, QUAL, FILTER = 7
    // Plus INFO fields if requested
    // Plus one struct for samples if requested
    
    int n_core = 7;  // CHROM, POS, ID, REF, ALT, QUAL, FILTER
    int n_info = 0;
    int n_format = 0;
    (void)n_format;
    
    if (opts && opts->include_info) {
        // Count INFO fields in header
        for (int i = 0; i < hdr->n[BCF_DT_ID]; i++) {
            if (hdr->id[BCF_DT_ID][i].val && 
                hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_INFO]) {
                n_info++;
            }
        }
    }
    
    int n_samples = bcf_hdr_nsamples(hdr);
    int include_samples = (opts == NULL || opts->include_format) && n_samples > 0;
    
    int64_t n_children = n_core;
    if (n_info > 0) n_children++;  // INFO struct
    if (include_samples) n_children++;  // samples struct
    
    RETURN_IF_ERROR(init_schema_struct(schema, "", n_children));
    
    int idx = 0;
    
    // CHROM - string (index 0)
    RETURN_IF_ERROR(init_schema_field(schema->children[idx++], 
                                      ARROW_FORMAT_UTF8, "CHROM", 0));
    
    // POS - int64 (1-based position) (index 1)
    RETURN_IF_ERROR(init_schema_field(schema->children[idx++],
                                      ARROW_FORMAT_INT64, "POS", 0));
    
    // ID - string (nullable) (index 2)
    RETURN_IF_ERROR(init_schema_field(schema->children[idx++],
                                      ARROW_FORMAT_UTF8, "ID", ARROW_FLAG_NULLABLE));
    
    // REF - string (index 3)
    RETURN_IF_ERROR(init_schema_field(schema->children[idx++],
                                      ARROW_FORMAT_UTF8, "REF", 0));
    
    // ALT - list<string> (index 4)
    RETURN_IF_ERROR(init_schema_list(schema->children[idx++],
                                     "ALT", ARROW_FORMAT_UTF8, "item"));
    
    // QUAL - float64 (nullable) (index 5)
    RETURN_IF_ERROR(init_schema_field(schema->children[idx++],
                                      ARROW_FORMAT_FLOAT64, "QUAL", ARROW_FLAG_NULLABLE));
    
    // FILTER - list<string> (index 6)
    RETURN_IF_ERROR(init_schema_list(schema->children[idx++],
                                     "FILTER", ARROW_FORMAT_UTF8, "item"));
    
    // INFO struct (if requested and present)
    if (n_info > 0) {
        RETURN_IF_ERROR(init_schema_struct(schema->children[idx], "INFO", n_info));
        struct ArrowSchema* info_schema = schema->children[idx];
        
        int info_idx = 0;
        for (int i = 0; i < hdr->n[BCF_DT_ID] && info_idx < n_info; i++) {
            if (hdr->id[BCF_DT_ID][i].val && 
                hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_INFO]) {
                bcf_hrec_t* hrec = hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_INFO];
                const char* field_name = hdr->id[BCF_DT_ID][i].key;
                
                // Get type from header
                int type = bcf_hdr_id2type(hdr, BCF_HL_INFO, i);
                int number = bcf_hdr_id2number(hdr, BCF_HL_INFO, i);
                const char* format = bcf_type_to_arrow_format(type, number);
                
                // If Number != 1, wrap in list
                if (number != 1 && number != 0) {
                    RETURN_IF_ERROR(init_schema_list(info_schema->children[info_idx],
                                                     field_name, format, "item"));
                } else {
                    RETURN_IF_ERROR(init_schema_field(info_schema->children[info_idx],
                                                      format, field_name, ARROW_FLAG_NULLABLE));
                }
                info_idx++;
            }
        }
        idx++;
    }
    
    // Samples struct (if requested and present)
    if (include_samples) {
        // Count FORMAT fields in header
        int n_fmt_fields = 0;
        for (int i = 0; i < hdr->n[BCF_DT_ID]; i++) {
            if (hdr->id[BCF_DT_ID][i].val && 
                hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_FMT]) {
                n_fmt_fields++;
            }
        }
        if (n_fmt_fields == 0) n_fmt_fields = 1;  // At least GT
        
        RETURN_IF_ERROR(init_schema_struct(schema->children[idx], "samples", n_samples));
        struct ArrowSchema* samples_schema = schema->children[idx];
        
        for (int s = 0; s < n_samples; s++) {
            const char* sample_name = hdr->samples[s];
            RETURN_IF_ERROR(init_schema_struct(samples_schema->children[s], sample_name, n_fmt_fields));
            
            // Add FORMAT fields to each sample struct
            int fmt_idx = 0;
            for (int i = 0; i < hdr->n[BCF_DT_ID] && fmt_idx < n_fmt_fields; i++) {
                if (hdr->id[BCF_DT_ID][i].val && 
                    hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_FMT]) {
                    const char* field_name = hdr->id[BCF_DT_ID][i].key;
                    int type = bcf_hdr_id2type(hdr, BCF_HL_FMT, i);
                    int number = bcf_hdr_id2number(hdr, BCF_HL_FMT, i);
                    const char* format = bcf_type_to_arrow_format(type, number);
                    
                    if (number != 1 && number != 0) {
                        RETURN_IF_ERROR(init_schema_list(samples_schema->children[s]->children[fmt_idx],
                                                         field_name, format, "item"));
                    } else {
                        RETURN_IF_ERROR(init_schema_field(samples_schema->children[s]->children[fmt_idx],
                                                          format, field_name, ARROW_FLAG_NULLABLE));
                    }
                    fmt_idx++;
                }
            }
            
            // Fallback if no FORMAT fields found in header
            if (fmt_idx == 0) {
                RETURN_IF_ERROR(init_schema_field(samples_schema->children[s]->children[0],
                                                  ARROW_FORMAT_UTF8, "GT", ARROW_FLAG_NULLABLE));
            }
        }
        idx++;
    }
    
    return 0;
}

// =============================================================================
// Stream Implementation
// =============================================================================

static int vcf_stream_get_schema(struct ArrowArrayStream* stream, struct ArrowSchema* out) {
    vcf_arrow_private_t* priv = (vcf_arrow_private_t*)stream->private_data;
    
    if (priv->cached_schema == NULL) {
        priv->cached_schema = (struct ArrowSchema*)vcf_arrow_malloc(sizeof(struct ArrowSchema));
        if (!priv->cached_schema) {
            snprintf(priv->error_msg, sizeof(priv->error_msg), "Failed to allocate schema");
            return ENOMEM;
        }
        
        int ret = vcf_arrow_schema_from_header(priv->hdr, priv->cached_schema, &priv->opts);
        if (ret != 0) {
            vcf_arrow_free(priv->cached_schema);
            priv->cached_schema = NULL;
            snprintf(priv->error_msg, sizeof(priv->error_msg), "Failed to create schema");
            return ret;
        }
    }
    
    // Deep copy schema by regenerating it with the same options
    return vcf_arrow_schema_from_header(priv->hdr, out, &priv->opts);
}

static int vcf_stream_get_next(struct ArrowArrayStream* stream, struct ArrowArray* out) {
    vcf_arrow_private_t* priv = (vcf_arrow_private_t*)stream->private_data;
    
    if (priv->finished) {
        // Signal end of stream
        memset(out, 0, sizeof(*out));
        out->release = NULL;
        return 0;
    }
    
    // Allocate batch buffers
    int64_t batch_size = priv->opts.batch_size;
    int64_t n_read = 0;
    
    // Allocate temporary storage for this batch
    char** chrom_data = (char**)vcf_arrow_malloc(batch_size * sizeof(char*));
    int64_t* pos_data = (int64_t*)vcf_arrow_malloc(batch_size * sizeof(int64_t));
    char** id_data = (char**)vcf_arrow_malloc(batch_size * sizeof(char*));
    char** ref_data = (char**)vcf_arrow_malloc(batch_size * sizeof(char*));
    double* qual_data = (double*)vcf_arrow_malloc(batch_size * sizeof(double));
    uint8_t* qual_validity = (uint8_t*)vcf_arrow_malloc((batch_size + 7) / 8);
    
    // ALT: need offsets into alt_strings array and the concatenated alt allele strings
    // Each record can have 0 or more ALT alleles
    int32_t* alt_list_offsets = (int32_t*)vcf_arrow_malloc((batch_size + 1) * sizeof(int32_t));
    char*** alt_data = (char***)vcf_arrow_malloc(batch_size * sizeof(char**));  // array of string arrays
    int* alt_counts = (int*)vcf_arrow_malloc(batch_size * sizeof(int));  // number of ALTs per record
    
    // FILTER: similar structure
    int32_t* filter_list_offsets = (int32_t*)vcf_arrow_malloc((batch_size + 1) * sizeof(int32_t));
    char*** filter_data = (char***)vcf_arrow_malloc(batch_size * sizeof(char**));
    int* filter_counts = (int*)vcf_arrow_malloc(batch_size * sizeof(int));
    
    // FORMAT data storage - will be allocated per FORMAT field if needed
    int n_samples = bcf_hdr_nsamples(priv->hdr);
    int n_fmt_fields = 0;
    int* fmt_ids = NULL;       // header IDs for each FORMAT field
    int* fmt_types = NULL;     // BCF_HT_* type for each FORMAT field
    int* fmt_numbers = NULL;   // Number (1=scalar, else list)
    
    // Per-FORMAT-field data arrays (indexed by format field)
    // For int/float scalar: [batch_size * n_samples] values
    // For int/float list: [batch_size * n_samples * max_len] values + counts
    // For string: concatenated strings + offsets
    void** fmt_data = NULL;           // Raw data arrays per FORMAT field
    int32_t** fmt_offsets = NULL;     // For lists/strings: offsets per record*sample
    int** fmt_lengths = NULL;         // Actual length per record*sample for lists
    uint8_t** fmt_validity = NULL;    // Validity bitmaps per FORMAT field per sample
    
    if (priv->opts.include_format && n_samples > 0) {
        // Count FORMAT fields
        for (int i = 0; i < priv->hdr->n[BCF_DT_ID]; i++) {
            if (priv->hdr->id[BCF_DT_ID][i].val && 
                priv->hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_FMT]) {
                n_fmt_fields++;
            }
        }
        if (n_fmt_fields == 0) n_fmt_fields = 1;  // At least GT
        
        fmt_ids = (int*)vcf_arrow_malloc(n_fmt_fields * sizeof(int));
        fmt_types = (int*)vcf_arrow_malloc(n_fmt_fields * sizeof(int));
        fmt_numbers = (int*)vcf_arrow_malloc(n_fmt_fields * sizeof(int));
        fmt_data = (void**)vcf_arrow_malloc(n_fmt_fields * sizeof(void*));
        fmt_offsets = (int32_t**)vcf_arrow_malloc(n_fmt_fields * sizeof(int32_t*));
        fmt_lengths = (int**)vcf_arrow_malloc(n_fmt_fields * sizeof(int*));
        fmt_validity = (uint8_t**)vcf_arrow_malloc(n_fmt_fields * n_samples * sizeof(uint8_t*));
        
        memset(fmt_data, 0, n_fmt_fields * sizeof(void*));
        memset(fmt_offsets, 0, n_fmt_fields * sizeof(int32_t*));
        memset(fmt_lengths, 0, n_fmt_fields * sizeof(int*));
        memset(fmt_validity, 0, n_fmt_fields * n_samples * sizeof(uint8_t*));
        
        // Populate fmt_ids, fmt_types, fmt_numbers
        int fmt_idx = 0;
        for (int i = 0; i < priv->hdr->n[BCF_DT_ID] && fmt_idx < n_fmt_fields; i++) {
            if (priv->hdr->id[BCF_DT_ID][i].val && 
                priv->hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_FMT]) {
                fmt_ids[fmt_idx] = i;
                fmt_types[fmt_idx] = bcf_hdr_id2type(priv->hdr, BCF_HL_FMT, i);
                fmt_numbers[fmt_idx] = bcf_hdr_id2number(priv->hdr, BCF_HL_FMT, i);
                fmt_idx++;
            }
        }
        
        // Allocate validity arrays for each sample for each FORMAT field
        for (int f = 0; f < n_fmt_fields; f++) {
            for (int s = 0; s < n_samples; s++) {
                fmt_validity[f * n_samples + s] = (uint8_t*)vcf_arrow_malloc((batch_size + 7) / 8);
                memset(fmt_validity[f * n_samples + s], 0, (batch_size + 7) / 8);
            }
        }
    }
    
    if (!chrom_data || !pos_data || !id_data || !ref_data || !qual_data || !qual_validity ||
        !alt_list_offsets || !alt_data || !alt_counts ||
        !filter_list_offsets || !filter_data || !filter_counts) {
        vcf_arrow_free(chrom_data);
        vcf_arrow_free(pos_data);
        vcf_arrow_free(id_data);
        vcf_arrow_free(ref_data);
        vcf_arrow_free(qual_data);
        vcf_arrow_free(qual_validity);
        vcf_arrow_free(alt_list_offsets);
        vcf_arrow_free(alt_data);
        vcf_arrow_free(alt_counts);
        vcf_arrow_free(filter_list_offsets);
        vcf_arrow_free(filter_data);
        vcf_arrow_free(filter_counts);
        vcf_arrow_free(fmt_ids);
        vcf_arrow_free(fmt_types);
        vcf_arrow_free(fmt_numbers);
        vcf_arrow_free(fmt_data);
        vcf_arrow_free(fmt_offsets);
        vcf_arrow_free(fmt_lengths);
        if (fmt_validity) {
            for (int i = 0; i < n_fmt_fields * n_samples; i++) {
                vcf_arrow_free(fmt_validity[i]);
            }
            vcf_arrow_free(fmt_validity);
        }
        snprintf(priv->error_msg, sizeof(priv->error_msg), "Failed to allocate batch buffers");
        return ENOMEM;
    }
    
    memset(qual_validity, 0, (batch_size + 7) / 8);
    memset(alt_data, 0, batch_size * sizeof(char**));
    memset(filter_data, 0, batch_size * sizeof(char**));
    alt_list_offsets[0] = 0;
    filter_list_offsets[0] = 0;
    
    // Allocate FORMAT data storage based on types
    // For scalars: batch_size * n_samples elements
    // For lists: we'll use dynamic arrays per FORMAT field
    if (priv->opts.include_format && n_samples > 0) {
        for (int f = 0; f < n_fmt_fields; f++) {
            int type = fmt_types[f];
            int number = fmt_numbers[f];
            int is_list = (number != 1 && number != 0);
            
            if (is_list) {
                // For lists, allocate offset arrays and length tracking
                // Data will be accumulated with realloc
                fmt_offsets[f] = (int32_t*)vcf_arrow_malloc((batch_size * n_samples + 1) * sizeof(int32_t));
                memset(fmt_offsets[f], 0, (batch_size * n_samples + 1) * sizeof(int32_t));
                fmt_lengths[f] = (int*)vcf_arrow_malloc(batch_size * n_samples * sizeof(int));
                memset(fmt_lengths[f], 0, batch_size * n_samples * sizeof(int));
                // fmt_data[f] will grow as needed
                fmt_data[f] = NULL;
            } else {
                // Scalar: fixed size allocation
                if (type == BCF_HT_INT) {
                    fmt_data[f] = vcf_arrow_malloc(batch_size * n_samples * sizeof(int32_t));
                    memset(fmt_data[f], 0, batch_size * n_samples * sizeof(int32_t));
                } else if (type == BCF_HT_REAL) {
                    fmt_data[f] = vcf_arrow_malloc(batch_size * n_samples * sizeof(float));
                    memset(fmt_data[f], 0, batch_size * n_samples * sizeof(float));
                } else {
                    // String scalar - use offsets and concatenated data
                    fmt_offsets[f] = (int32_t*)vcf_arrow_malloc((batch_size * n_samples + 1) * sizeof(int32_t));
                    memset(fmt_offsets[f], 0, (batch_size * n_samples + 1) * sizeof(int32_t));
                    fmt_data[f] = NULL;  // Will grow as needed
                }
            }
        }
    }
    
    // Read records
    int ret;
    while (n_read < batch_size) {
        if (priv->itr) {
            ret = bcf_itr_next(priv->fp, priv->itr, priv->rec);
        } else {
            ret = bcf_read(priv->fp, priv->hdr, priv->rec);
        }
        
        if (ret < 0) {
            if (ret == -1) {
                // End of file
                priv->finished = 1;
                break;
            }
            // Error
            snprintf(priv->error_msg, sizeof(priv->error_msg), "Error reading VCF record");
            goto cleanup_error;
        }
        
        // Unpack the record
        bcf_unpack(priv->rec, BCF_UN_ALL);
        
        // CHROM
        chrom_data[n_read] = vcf_arrow_strdup(bcf_hdr_id2name(priv->hdr, priv->rec->rid));
        
        // POS (convert to 1-based)
        pos_data[n_read] = priv->rec->pos + 1;
        
        // ID
        id_data[n_read] = vcf_arrow_strdup(priv->rec->d.id);
        
        // REF
        ref_data[n_read] = vcf_arrow_strdup(priv->rec->d.allele[0]);
        
        // ALT - alleles 1 through n_allele-1
        int n_alt = priv->rec->n_allele - 1;
        alt_counts[n_read] = n_alt;
        if (n_alt > 0) {
            alt_data[n_read] = (char**)vcf_arrow_malloc(n_alt * sizeof(char*));
            for (int i = 0; i < n_alt; i++) {
                alt_data[n_read][i] = vcf_arrow_strdup(priv->rec->d.allele[i + 1]);
            }
        } else {
            alt_data[n_read] = NULL;
        }
        alt_list_offsets[n_read + 1] = alt_list_offsets[n_read] + n_alt;
        
        // QUAL
        if (bcf_float_is_missing(priv->rec->qual)) {
            qual_data[n_read] = 0.0;
            // qual_validity bit already 0 (NULL)
        } else {
            qual_data[n_read] = priv->rec->qual;
            // Set validity bit
            qual_validity[n_read / 8] |= (1 << (n_read % 8));
        }
        
        // FILTER - get filter names
        int n_flt = priv->rec->d.n_flt;
        filter_counts[n_read] = n_flt;
        if (n_flt > 0) {
            filter_data[n_read] = (char**)vcf_arrow_malloc(n_flt * sizeof(char*));
            for (int i = 0; i < n_flt; i++) {
                const char* flt_name = bcf_hdr_int2id(priv->hdr, BCF_DT_ID, priv->rec->d.flt[i]);
                filter_data[n_read][i] = vcf_arrow_strdup(flt_name);
            }
        } else {
            filter_data[n_read] = NULL;
        }
        filter_list_offsets[n_read + 1] = filter_list_offsets[n_read] + n_flt;
        
        // Extract FORMAT data for all samples
        if (priv->opts.include_format && n_samples > 0) {
            for (int f = 0; f < n_fmt_fields; f++) {
                int id = fmt_ids[f];
                int type = fmt_types[f];
                int number = fmt_numbers[f];
                int is_list = (number != 1 && number != 0);
                const char* tag = bcf_hdr_int2id(priv->hdr, BCF_DT_ID, id);
                
                if (type == BCF_HT_INT) {
                    int32_t* values = NULL;
                    int n_values = 0;
                    int ret_fmt = bcf_get_format_int32(priv->hdr, priv->rec, tag, &values, &n_values);
                    
                    if (ret_fmt > 0 && values) {
                        int vals_per_sample = ret_fmt / n_samples;
                        
                        if (is_list) {
                            // List of integers
                            // Accumulate into fmt_data[f] with offsets
                            // ... complex list handling - for now mark as valid if we got data
                            for (int s = 0; s < n_samples; s++) {
                                int base_idx = n_read * n_samples + s;
                                int valid_count = 0;
                                for (int v = 0; v < vals_per_sample; v++) {
                                    int32_t val = values[s * vals_per_sample + v];
                                    if (val != bcf_int32_missing && val != bcf_int32_vector_end) {
                                        valid_count++;
                                    }
                                }
                                fmt_lengths[f][base_idx] = valid_count;
                                if (valid_count > 0) {
                                    fmt_validity[f * n_samples + s][n_read / 8] |= (1 << (n_read % 8));
                                }
                            }
                        } else {
                            // Scalar integer
                            int32_t* data = (int32_t*)fmt_data[f];
                            for (int s = 0; s < n_samples; s++) {
                                int32_t val = values[s * vals_per_sample];
                                int idx = n_read * n_samples + s;
                                if (val != bcf_int32_missing && val != bcf_int32_vector_end) {
                                    data[idx] = val;
                                    fmt_validity[f * n_samples + s][n_read / 8] |= (1 << (n_read % 8));
                                }
                            }
                        }
                    }
                    free(values);
                    
                } else if (type == BCF_HT_REAL) {
                    float* values = NULL;
                    int n_values = 0;
                    int ret_fmt = bcf_get_format_float(priv->hdr, priv->rec, tag, &values, &n_values);
                    
                    if (ret_fmt > 0 && values) {
                        int vals_per_sample = ret_fmt / n_samples;
                        
                        if (is_list) {
                            // List of floats
                            for (int s = 0; s < n_samples; s++) {
                                int base_idx = n_read * n_samples + s;
                                int valid_count = 0;
                                for (int v = 0; v < vals_per_sample; v++) {
                                    float val = values[s * vals_per_sample + v];
                                    if (!bcf_float_is_missing(val) && !bcf_float_is_vector_end(val)) {
                                        valid_count++;
                                    }
                                }
                                fmt_lengths[f][base_idx] = valid_count;
                                if (valid_count > 0) {
                                    fmt_validity[f * n_samples + s][n_read / 8] |= (1 << (n_read % 8));
                                }
                            }
                        } else {
                            // Scalar float
                            float* data = (float*)fmt_data[f];
                            for (int s = 0; s < n_samples; s++) {
                                float val = values[s * vals_per_sample];
                                int idx = n_read * n_samples + s;
                                if (!bcf_float_is_missing(val) && !bcf_float_is_vector_end(val)) {
                                    data[idx] = val;
                                    fmt_validity[f * n_samples + s][n_read / 8] |= (1 << (n_read % 8));
                                }
                            }
                        }
                    }
                    free(values);
                    
                } else {
                    // String type (BCF_HT_STR)
                    char** values = NULL;
                    int n_values = 0;
                    int ret_fmt = bcf_get_format_string(priv->hdr, priv->rec, tag, &values, &n_values);
                    
                    if (ret_fmt > 0 && values) {
                        // String data - mark valid samples
                        for (int s = 0; s < n_samples; s++) {
                            const char* val = values[s];
                            if (val && strcmp(val, ".") != 0 && val[0] != '\0') {
                                fmt_validity[f * n_samples + s][n_read / 8] |= (1 << (n_read % 8));
                            }
                        }
                    }
                    if (values) free(values[0]);
                    free(values);
                }
            }
        }
        
        n_read++;
    }
    
    if (n_read == 0) {
        // No records read, stream is done
        priv->finished = 1;
        memset(out, 0, sizeof(*out));
        out->release = NULL;
        
        vcf_arrow_free(chrom_data);
        vcf_arrow_free(pos_data);
        vcf_arrow_free(id_data);
        vcf_arrow_free(ref_data);
        vcf_arrow_free(qual_data);
        vcf_arrow_free(qual_validity);
        vcf_arrow_free(alt_list_offsets);
        vcf_arrow_free(alt_data);
        vcf_arrow_free(alt_counts);
        vcf_arrow_free(filter_list_offsets);
        vcf_arrow_free(filter_data);
        vcf_arrow_free(filter_counts);
        
        // Free FORMAT data storage
        if (fmt_validity) {
            for (int i = 0; i < n_fmt_fields * n_samples; i++) {
                vcf_arrow_free(fmt_validity[i]);
            }
            vcf_arrow_free(fmt_validity);
        }
        for (int f = 0; f < n_fmt_fields; f++) {
            vcf_arrow_free(fmt_data[f]);
            vcf_arrow_free(fmt_offsets[f]);
            vcf_arrow_free(fmt_lengths[f]);
        }
        vcf_arrow_free(fmt_ids);
        vcf_arrow_free(fmt_types);
        vcf_arrow_free(fmt_numbers);
        vcf_arrow_free(fmt_data);
        vcf_arrow_free(fmt_offsets);
        vcf_arrow_free(fmt_lengths);
        
        return 0;
    }
    
    // Determine number of children to match schema
    // This must match the logic in vcf_arrow_schema_from_header
    int n_core = 7;  // CHROM, POS, ID, REF, ALT, QUAL, FILTER
    int n_info = 0;
    
    if (priv->opts.include_info) {
        // Count INFO fields in header (same logic as schema creation)
        for (int i = 0; i < priv->hdr->n[BCF_DT_ID]; i++) {
            if (priv->hdr->id[BCF_DT_ID][i].val && 
                priv->hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_INFO]) {
                n_info++;
            }
        }
    }
    
    // n_samples was already computed earlier
    int include_samples = priv->opts.include_format && n_samples > 0;
    
    int64_t n_children = n_core;
    if (n_info > 0) n_children++;  // INFO struct
    if (include_samples) n_children++;  // samples struct
    
    // Build the output array
    // CHROM(0), POS(1), ID(2), REF(3), ALT(4), QUAL(5), FILTER(6), [INFO(7)], [samples(8)]
    
    out->length = n_read;
    out->null_count = 0;
    out->offset = 0;
    out->n_buffers = 1;  // Struct has validity buffer only
    out->n_children = n_children;
    out->release = &release_array_simple;
    out->private_data = NULL;
    
    // Allocate buffers array
    out->buffers = (const void**)vcf_arrow_malloc(sizeof(void*) * 1);
    out->buffers[0] = NULL;  // No nulls at struct level
    
    // Allocate children
    out->children = (struct ArrowArray**)vcf_arrow_malloc(sizeof(struct ArrowArray*) * n_children);
    for (int64_t i = 0; i < n_children; i++) {
        out->children[i] = (struct ArrowArray*)vcf_arrow_malloc(sizeof(struct ArrowArray));
        memset(out->children[i], 0, sizeof(struct ArrowArray));
        out->children[i]->release = &release_array_simple;
    }
    
    // =========================================================================
    // Child 0: CHROM (utf8 string)
    // =========================================================================
    {
        struct ArrowArray* arr = out->children[0];
        arr->length = n_read;
        arr->null_count = 0;
        arr->offset = 0;
        arr->n_buffers = 3;
        arr->n_children = 0;
        
        size_t total_len = 0;
        for (int64_t i = 0; i < n_read; i++) {
            total_len += strlen(chrom_data[i]);
        }
        
        int32_t* offsets = (int32_t*)vcf_arrow_malloc((n_read + 1) * sizeof(int32_t));
        char* data = (char*)vcf_arrow_malloc(total_len > 0 ? total_len : 1);
        
        offsets[0] = 0;
        size_t pos = 0;
        for (int64_t i = 0; i < n_read; i++) {
            size_t len = strlen(chrom_data[i]);
            memcpy(data + pos, chrom_data[i], len);
            pos += len;
            offsets[i + 1] = pos;
            vcf_arrow_free(chrom_data[i]);
        }
        
        arr->buffers = (const void**)vcf_arrow_malloc(3 * sizeof(void*));
        arr->buffers[0] = NULL;  // validity (all valid)
        arr->buffers[1] = offsets;
        arr->buffers[2] = data;
    }
    vcf_arrow_free(chrom_data);
    
    // =========================================================================
    // Child 1: POS (int64)
    // =========================================================================
    {
        struct ArrowArray* arr = out->children[1];
        arr->length = n_read;
        arr->null_count = 0;
        arr->offset = 0;
        arr->n_buffers = 2;
        arr->n_children = 0;
        
        arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
        arr->buffers[0] = NULL;  // validity
        arr->buffers[1] = pos_data;  // transfer ownership
    }
    
    // =========================================================================
    // Child 2: ID (utf8 string, nullable)
    // =========================================================================
    {
        struct ArrowArray* arr = out->children[2];
        arr->length = n_read;
        arr->offset = 0;
        arr->n_buffers = 3;
        arr->n_children = 0;
        
        size_t total_len = 0;
        int64_t null_count = 0;
        uint8_t* validity = (uint8_t*)vcf_arrow_malloc((n_read + 7) / 8);
        memset(validity, 0, (n_read + 7) / 8);
        
        for (int64_t i = 0; i < n_read; i++) {
            if (id_data[i] && strcmp(id_data[i], ".") != 0) {
                total_len += strlen(id_data[i]);
                validity[i / 8] |= (1 << (i % 8));
            } else {
                null_count++;
            }
        }
        arr->null_count = null_count;
        
        int32_t* offsets = (int32_t*)vcf_arrow_malloc((n_read + 1) * sizeof(int32_t));
        char* data = (char*)vcf_arrow_malloc(total_len > 0 ? total_len : 1);
        
        offsets[0] = 0;
        size_t pos = 0;
        for (int64_t i = 0; i < n_read; i++) {
            if (id_data[i] && strcmp(id_data[i], ".") != 0) {
                size_t len = strlen(id_data[i]);
                memcpy(data + pos, id_data[i], len);
                pos += len;
            }
            offsets[i + 1] = pos;
            vcf_arrow_free(id_data[i]);
        }
        
        arr->buffers = (const void**)vcf_arrow_malloc(3 * sizeof(void*));
        arr->buffers[0] = validity;
        arr->buffers[1] = offsets;
        arr->buffers[2] = data;
    }
    vcf_arrow_free(id_data);
    
    // =========================================================================
    // Child 3: REF (utf8 string)
    // =========================================================================
    {
        struct ArrowArray* arr = out->children[3];
        arr->length = n_read;
        arr->null_count = 0;
        arr->offset = 0;
        arr->n_buffers = 3;
        arr->n_children = 0;
        
        size_t total_len = 0;
        for (int64_t i = 0; i < n_read; i++) {
            total_len += strlen(ref_data[i]);
        }
        
        int32_t* offsets = (int32_t*)vcf_arrow_malloc((n_read + 1) * sizeof(int32_t));
        char* data = (char*)vcf_arrow_malloc(total_len > 0 ? total_len : 1);
        
        offsets[0] = 0;
        size_t pos = 0;
        for (int64_t i = 0; i < n_read; i++) {
            size_t len = strlen(ref_data[i]);
            memcpy(data + pos, ref_data[i], len);
            pos += len;
            offsets[i + 1] = pos;
            vcf_arrow_free(ref_data[i]);
        }
        
        arr->buffers = (const void**)vcf_arrow_malloc(3 * sizeof(void*));
        arr->buffers[0] = NULL;
        arr->buffers[1] = offsets;
        arr->buffers[2] = data;
    }
    vcf_arrow_free(ref_data);
    
    // =========================================================================
    // Child 4: ALT (list<utf8>)
    // List arrays have: validity, offsets; child array has the string values
    // =========================================================================
    {
        struct ArrowArray* arr = out->children[4];
        arr->length = n_read;
        arr->null_count = 0;
        arr->offset = 0;
        arr->n_buffers = 2;  // validity, offsets
        arr->n_children = 1;
        
        arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
        arr->buffers[0] = NULL;  // validity (lists are never null, just empty)
        arr->buffers[1] = alt_list_offsets;  // transfer ownership
        
        // Create child string array for ALT values
        arr->children = (struct ArrowArray**)vcf_arrow_malloc(sizeof(struct ArrowArray*));
        arr->children[0] = (struct ArrowArray*)vcf_arrow_malloc(sizeof(struct ArrowArray));
        memset(arr->children[0], 0, sizeof(struct ArrowArray));
        
        struct ArrowArray* child = arr->children[0];
        child->release = &release_array_simple;
        
        int64_t total_alts = alt_list_offsets[n_read];
        child->length = total_alts;
        child->null_count = 0;
        child->offset = 0;
        child->n_buffers = 3;
        child->n_children = 0;
        
        // Calculate total string length
        size_t total_len = 0;
        for (int64_t i = 0; i < n_read; i++) {
            for (int j = 0; j < alt_counts[i]; j++) {
                total_len += strlen(alt_data[i][j]);
            }
        }
        
        int32_t* str_offsets = (int32_t*)vcf_arrow_malloc((total_alts + 1) * sizeof(int32_t));
        char* str_data = (char*)vcf_arrow_malloc(total_len > 0 ? total_len : 1);
        
        str_offsets[0] = 0;
        size_t pos = 0;
        int64_t idx = 0;
        for (int64_t i = 0; i < n_read; i++) {
            for (int j = 0; j < alt_counts[i]; j++) {
                size_t len = strlen(alt_data[i][j]);
                memcpy(str_data + pos, alt_data[i][j], len);
                pos += len;
                str_offsets[idx + 1] = pos;
                vcf_arrow_free(alt_data[i][j]);
                idx++;
            }
            vcf_arrow_free(alt_data[i]);
        }
        
        child->buffers = (const void**)vcf_arrow_malloc(3 * sizeof(void*));
        child->buffers[0] = NULL;
        child->buffers[1] = str_offsets;
        child->buffers[2] = str_data;
    }
    vcf_arrow_free(alt_data);
    vcf_arrow_free(alt_counts);
    
    // =========================================================================
    // Child 5: QUAL (float64, nullable)
    // =========================================================================
    {
        struct ArrowArray* arr = out->children[5];
        arr->length = n_read;
        arr->offset = 0;
        arr->n_buffers = 2;
        arr->n_children = 0;
        
        int64_t null_count = 0;
        for (int64_t i = 0; i < n_read; i++) {
            if (!(qual_validity[i / 8] & (1 << (i % 8)))) {
                null_count++;
            }
        }
        arr->null_count = null_count;
        
        arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
        arr->buffers[0] = qual_validity;  // transfer ownership
        arr->buffers[1] = qual_data;      // transfer ownership
    }
    
    // =========================================================================
    // Child 6: FILTER (list<utf8>)
    // =========================================================================
    {
        struct ArrowArray* arr = out->children[6];
        arr->length = n_read;
        arr->null_count = 0;
        arr->offset = 0;
        arr->n_buffers = 2;
        arr->n_children = 1;
        
        arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
        arr->buffers[0] = NULL;
        arr->buffers[1] = filter_list_offsets;  // transfer ownership
        
        // Create child string array for FILTER values
        arr->children = (struct ArrowArray**)vcf_arrow_malloc(sizeof(struct ArrowArray*));
        arr->children[0] = (struct ArrowArray*)vcf_arrow_malloc(sizeof(struct ArrowArray));
        memset(arr->children[0], 0, sizeof(struct ArrowArray));
        
        struct ArrowArray* child = arr->children[0];
        child->release = &release_array_simple;
        
        int64_t total_filters = filter_list_offsets[n_read];
        child->length = total_filters;
        child->null_count = 0;
        child->offset = 0;
        child->n_buffers = 3;
        child->n_children = 0;
        
        // Calculate total string length
        size_t total_len = 0;
        for (int64_t i = 0; i < n_read; i++) {
            for (int j = 0; j < filter_counts[i]; j++) {
                total_len += strlen(filter_data[i][j]);
            }
        }
        
        int32_t* str_offsets = (int32_t*)vcf_arrow_malloc((total_filters + 1) * sizeof(int32_t));
        char* str_data = (char*)vcf_arrow_malloc(total_len > 0 ? total_len : 1);
        
        str_offsets[0] = 0;
        size_t pos = 0;
        int64_t idx = 0;
        for (int64_t i = 0; i < n_read; i++) {
            for (int j = 0; j < filter_counts[i]; j++) {
                size_t len = strlen(filter_data[i][j]);
                memcpy(str_data + pos, filter_data[i][j], len);
                pos += len;
                str_offsets[idx + 1] = pos;
                vcf_arrow_free(filter_data[i][j]);
                idx++;
            }
            vcf_arrow_free(filter_data[i]);
        }
        
        child->buffers = (const void**)vcf_arrow_malloc(3 * sizeof(void*));
        child->buffers[0] = NULL;
        child->buffers[1] = str_offsets;
        child->buffers[2] = str_data;
    }
    vcf_arrow_free(filter_data);
    vcf_arrow_free(filter_counts);
    
    // =========================================================================
    // Child 7: INFO struct (if include_info and INFO fields exist)
    // =========================================================================
    if (n_info > 0) {
        struct ArrowArray* info_arr = out->children[7];
        info_arr->length = n_read;
        info_arr->null_count = 0;
        info_arr->offset = 0;
        info_arr->n_buffers = 1;  // Struct has only validity buffer
        info_arr->n_children = n_info;
        
        info_arr->buffers = (const void**)vcf_arrow_malloc(sizeof(void*));
        info_arr->buffers[0] = NULL;  // All valid at struct level
        
        // Allocate children for INFO fields
        info_arr->children = (struct ArrowArray**)vcf_arrow_malloc(n_info * sizeof(struct ArrowArray*));
        
        int info_idx = 0;
        for (int i = 0; i < priv->hdr->n[BCF_DT_ID] && info_idx < n_info; i++) {
            if (priv->hdr->id[BCF_DT_ID][i].val && 
                priv->hdr->id[BCF_DT_ID][i].val->hrec[BCF_HL_INFO]) {
                
                struct ArrowArray* field_arr = (struct ArrowArray*)vcf_arrow_malloc(sizeof(struct ArrowArray));
                memset(field_arr, 0, sizeof(struct ArrowArray));
                field_arr->release = &release_array_simple;
                info_arr->children[info_idx] = field_arr;
                
                int type = bcf_hdr_id2type(priv->hdr, BCF_HL_INFO, i);
                int number = bcf_hdr_id2number(priv->hdr, BCF_HL_INFO, i);
                
                // Create empty/null arrays for INFO fields
                // In production this should be populated with actual INFO values
                // For now, create properly typed null arrays to match schema
                
                field_arr->length = n_read;
                field_arr->null_count = n_read;  // All null
                field_arr->offset = 0;
                
                // Allocate validity bitmap (all zeros = all null)
                uint8_t* validity = (uint8_t*)vcf_arrow_malloc((n_read + 7) / 8);
                memset(validity, 0, (n_read + 7) / 8);
                
                if (number != 1 && number != 0) {
                    // List type - need offsets buffer and child array
                    field_arr->n_buffers = 2;
                    field_arr->n_children = 1;
                    
                    int32_t* offsets = (int32_t*)vcf_arrow_malloc((n_read + 1) * sizeof(int32_t));
                    memset(offsets, 0, (n_read + 1) * sizeof(int32_t));
                    
                    field_arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                    field_arr->buffers[0] = validity;
                    field_arr->buffers[1] = offsets;
                    
                    // Create empty child array for list items
                    field_arr->children = (struct ArrowArray**)vcf_arrow_malloc(sizeof(struct ArrowArray*));
                    field_arr->children[0] = (struct ArrowArray*)vcf_arrow_malloc(sizeof(struct ArrowArray));
                    memset(field_arr->children[0], 0, sizeof(struct ArrowArray));
                    field_arr->children[0]->release = &release_array_simple;
                    field_arr->children[0]->length = 0;
                    field_arr->children[0]->null_count = 0;
                    field_arr->children[0]->offset = 0;
                    
                    // Set up child buffers based on type
                    if (type == BCF_HT_INT) {
                        field_arr->children[0]->n_buffers = 2;
                        field_arr->children[0]->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        field_arr->children[0]->buffers[0] = NULL;
                        field_arr->children[0]->buffers[1] = vcf_arrow_malloc(1);  // Empty data
                    } else if (type == BCF_HT_REAL) {
                        field_arr->children[0]->n_buffers = 2;
                        field_arr->children[0]->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        field_arr->children[0]->buffers[0] = NULL;
                        field_arr->children[0]->buffers[1] = vcf_arrow_malloc(1);
                    } else {
                        // String type
                        field_arr->children[0]->n_buffers = 3;
                        field_arr->children[0]->buffers = (const void**)vcf_arrow_malloc(3 * sizeof(void*));
                        field_arr->children[0]->buffers[0] = NULL;
                        int32_t* child_offsets = (int32_t*)vcf_arrow_malloc(sizeof(int32_t));
                        child_offsets[0] = 0;
                        field_arr->children[0]->buffers[1] = child_offsets;
                        field_arr->children[0]->buffers[2] = vcf_arrow_malloc(1);
                    }
                    field_arr->children[0]->n_children = 0;
                } else {
                    // Scalar type
                    field_arr->n_children = 0;
                    
                    if (type == BCF_HT_FLAG) {
                        // Boolean - 1 validity buffer + 1 data buffer
                        field_arr->n_buffers = 2;
                        uint8_t* data = (uint8_t*)vcf_arrow_malloc((n_read + 7) / 8);
                        memset(data, 0, (n_read + 7) / 8);
                        field_arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        field_arr->buffers[0] = validity;
                        field_arr->buffers[1] = data;
                    } else if (type == BCF_HT_INT) {
                        field_arr->n_buffers = 2;
                        int32_t* data = (int32_t*)vcf_arrow_malloc(n_read * sizeof(int32_t));
                        memset(data, 0, n_read * sizeof(int32_t));
                        field_arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        field_arr->buffers[0] = validity;
                        field_arr->buffers[1] = data;
                    } else if (type == BCF_HT_REAL) {
                        field_arr->n_buffers = 2;
                        float* data = (float*)vcf_arrow_malloc(n_read * sizeof(float));
                        memset(data, 0, n_read * sizeof(float));
                        field_arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        field_arr->buffers[0] = validity;
                        field_arr->buffers[1] = data;
                    } else {
                        // String type
                        field_arr->n_buffers = 3;
                        int32_t* offsets = (int32_t*)vcf_arrow_malloc((n_read + 1) * sizeof(int32_t));
                        memset(offsets, 0, (n_read + 1) * sizeof(int32_t));
                        field_arr->buffers = (const void**)vcf_arrow_malloc(3 * sizeof(void*));
                        field_arr->buffers[0] = validity;
                        field_arr->buffers[1] = offsets;
                        field_arr->buffers[2] = vcf_arrow_malloc(1);  // Empty data
                    }
                }
                
                info_idx++;
            }
        }
    }
    
    // =========================================================================
    // Child 8: samples struct (if include_format and samples exist)
    // Note: index is 7 if no INFO, 8 if INFO exists
    // =========================================================================
    if (include_samples) {
        int samples_child_idx = n_info > 0 ? 8 : 7;
        struct ArrowArray* samples_arr = out->children[samples_child_idx];
        samples_arr->length = n_read;
        samples_arr->null_count = 0;
        samples_arr->offset = 0;
        samples_arr->n_buffers = 1;
        samples_arr->n_children = n_samples;
        
        samples_arr->buffers = (const void**)vcf_arrow_malloc(sizeof(void*));
        samples_arr->buffers[0] = NULL;
        
        samples_arr->children = (struct ArrowArray**)vcf_arrow_malloc(n_samples * sizeof(struct ArrowArray*));
        
        for (int s = 0; s < n_samples; s++) {
            struct ArrowArray* sample_arr = (struct ArrowArray*)vcf_arrow_malloc(sizeof(struct ArrowArray));
            memset(sample_arr, 0, sizeof(struct ArrowArray));
            sample_arr->release = &release_array_simple;
            samples_arr->children[s] = sample_arr;
            
            sample_arr->length = n_read;
            sample_arr->null_count = 0;
            sample_arr->offset = 0;
            sample_arr->n_buffers = 1;
            sample_arr->n_children = n_fmt_fields;
            
            sample_arr->buffers = (const void**)vcf_arrow_malloc(sizeof(void*));
            sample_arr->buffers[0] = NULL;
            
            sample_arr->children = (struct ArrowArray**)vcf_arrow_malloc(n_fmt_fields * sizeof(struct ArrowArray*));
            
            // Build arrays for each FORMAT field using pre-collected data
            for (int f = 0; f < n_fmt_fields; f++) {
                struct ArrowArray* fmt_arr = (struct ArrowArray*)vcf_arrow_malloc(sizeof(struct ArrowArray));
                memset(fmt_arr, 0, sizeof(struct ArrowArray));
                fmt_arr->release = &release_array_simple;
                sample_arr->children[f] = fmt_arr;
                
                int type = fmt_types[f];
                int number = fmt_numbers[f];
                int is_list = (number != 1 && number != 0);
                
                fmt_arr->length = n_read;
                fmt_arr->offset = 0;
                
                // Use pre-collected validity bitmap for this sample
                // Transfer ownership of the validity array
                uint8_t* validity = fmt_validity[f * n_samples + s];
                fmt_validity[f * n_samples + s] = NULL;  // Ownership transferred
                
                // Count nulls
                int64_t null_count = 0;
                for (int64_t r = 0; r < n_read; r++) {
                    if (!(validity[r / 8] & (1 << (r % 8)))) {
                        null_count++;
                    }
                }
                fmt_arr->null_count = null_count;
                
                if (is_list) {
                    // List type
                    fmt_arr->n_buffers = 2;
                    fmt_arr->n_children = 1;
                    
                    int32_t* offsets = (int32_t*)vcf_arrow_malloc((n_read + 1) * sizeof(int32_t));
                    memset(offsets, 0, (n_read + 1) * sizeof(int32_t));
                    
                    fmt_arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                    fmt_arr->buffers[0] = validity;
                    fmt_arr->buffers[1] = offsets;
                    
                    // Create child array for list items (empty for now)
                    fmt_arr->children = (struct ArrowArray**)vcf_arrow_malloc(sizeof(struct ArrowArray*));
                    fmt_arr->children[0] = (struct ArrowArray*)vcf_arrow_malloc(sizeof(struct ArrowArray));
                    memset(fmt_arr->children[0], 0, sizeof(struct ArrowArray));
                    fmt_arr->children[0]->release = &release_array_simple;
                    fmt_arr->children[0]->length = 0;
                    fmt_arr->children[0]->null_count = 0;
                    fmt_arr->children[0]->offset = 0;
                    fmt_arr->children[0]->n_children = 0;
                    
                    if (type == BCF_HT_INT) {
                        fmt_arr->children[0]->n_buffers = 2;
                        fmt_arr->children[0]->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        fmt_arr->children[0]->buffers[0] = NULL;
                        fmt_arr->children[0]->buffers[1] = vcf_arrow_malloc(1);
                    } else if (type == BCF_HT_REAL) {
                        fmt_arr->children[0]->n_buffers = 2;
                        fmt_arr->children[0]->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        fmt_arr->children[0]->buffers[0] = NULL;
                        fmt_arr->children[0]->buffers[1] = vcf_arrow_malloc(1);
                    } else {
                        // String type
                        fmt_arr->children[0]->n_buffers = 3;
                        fmt_arr->children[0]->buffers = (const void**)vcf_arrow_malloc(3 * sizeof(void*));
                        fmt_arr->children[0]->buffers[0] = NULL;
                        int32_t* child_offsets = (int32_t*)vcf_arrow_malloc(sizeof(int32_t));
                        child_offsets[0] = 0;
                        fmt_arr->children[0]->buffers[1] = child_offsets;
                        fmt_arr->children[0]->buffers[2] = vcf_arrow_malloc(1);
                    }
                } else {
                    // Scalar type
                    fmt_arr->n_children = 0;
                    fmt_arr->children = NULL;
                    
                    if (type == BCF_HT_FLAG) {
                        // Boolean
                        fmt_arr->n_buffers = 2;
                        uint8_t* data = (uint8_t*)vcf_arrow_malloc((n_read + 7) / 8);
                        memset(data, 0, (n_read + 7) / 8);
                        fmt_arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        fmt_arr->buffers[0] = validity;
                        fmt_arr->buffers[1] = data;
                    } else if (type == BCF_HT_INT) {
                        // Integer - copy this sample's data from collected data
                        fmt_arr->n_buffers = 2;
                        int32_t* data = (int32_t*)vcf_arrow_malloc(n_read * sizeof(int32_t));
                        memset(data, 0, n_read * sizeof(int32_t));
                        if (fmt_data[f] != NULL) {
                            int32_t* src_data = (int32_t*)fmt_data[f];
                            for (int64_t r = 0; r < n_read; r++) {
                                data[r] = src_data[r * n_samples + s];
                            }
                        }
                        fmt_arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        fmt_arr->buffers[0] = validity;
                        fmt_arr->buffers[1] = data;
                    } else if (type == BCF_HT_REAL) {
                        // Float - copy this sample's data from collected data
                        fmt_arr->n_buffers = 2;
                        float* data = (float*)vcf_arrow_malloc(n_read * sizeof(float));
                        memset(data, 0, n_read * sizeof(float));
                        if (fmt_data[f] != NULL) {
                            float* src_data = (float*)fmt_data[f];
                            for (int64_t r = 0; r < n_read; r++) {
                                data[r] = src_data[r * n_samples + s];
                            }
                        }
                        fmt_arr->buffers = (const void**)vcf_arrow_malloc(2 * sizeof(void*));
                        fmt_arr->buffers[0] = validity;
                        fmt_arr->buffers[1] = data;
                    } else {
                        // String type (BCF_HT_STR) - empty for now
                        fmt_arr->n_buffers = 3;
                        int32_t* offsets = (int32_t*)vcf_arrow_malloc((n_read + 1) * sizeof(int32_t));
                        memset(offsets, 0, (n_read + 1) * sizeof(int32_t));
                        fmt_arr->buffers = (const void**)vcf_arrow_malloc(3 * sizeof(void*));
                        fmt_arr->buffers[0] = validity;
                        fmt_arr->buffers[1] = offsets;
                        fmt_arr->buffers[2] = vcf_arrow_malloc(1);
                    }
                }
            }
        }
    }
    
    // Free remaining FORMAT data storage (data that wasn't transferred)
    if (fmt_validity) {
        for (int i = 0; i < n_fmt_fields * n_samples; i++) {
            vcf_arrow_free(fmt_validity[i]);  // May be NULL if transferred
        }
        vcf_arrow_free(fmt_validity);
    }
    for (int f = 0; f < n_fmt_fields; f++) {
        vcf_arrow_free(fmt_data[f]);
        vcf_arrow_free(fmt_offsets[f]);
        vcf_arrow_free(fmt_lengths[f]);
    }
    vcf_arrow_free(fmt_ids);
    vcf_arrow_free(fmt_types);
    vcf_arrow_free(fmt_numbers);
    vcf_arrow_free(fmt_data);
    vcf_arrow_free(fmt_offsets);
    vcf_arrow_free(fmt_lengths);
    
    out->dictionary = NULL;
    
    return 0;

cleanup_error:
    for (int64_t i = 0; i < n_read; i++) {
        vcf_arrow_free(chrom_data[i]);
        vcf_arrow_free(id_data[i]);
        vcf_arrow_free(ref_data[i]);
        for (int j = 0; j < alt_counts[i]; j++) {
            if (alt_data[i]) vcf_arrow_free(alt_data[i][j]);
        }
        vcf_arrow_free(alt_data[i]);
        for (int j = 0; j < filter_counts[i]; j++) {
            if (filter_data[i]) vcf_arrow_free(filter_data[i][j]);
        }
        vcf_arrow_free(filter_data[i]);
    }
    vcf_arrow_free(chrom_data);
    vcf_arrow_free(pos_data);
    vcf_arrow_free(id_data);
    vcf_arrow_free(ref_data);
    vcf_arrow_free(qual_data);
    vcf_arrow_free(qual_validity);
    vcf_arrow_free(alt_list_offsets);
    vcf_arrow_free(alt_data);
    vcf_arrow_free(alt_counts);
    vcf_arrow_free(filter_list_offsets);
    vcf_arrow_free(filter_data);
    vcf_arrow_free(filter_counts);
    return EIO;
}

static const char* vcf_stream_get_last_error(struct ArrowArrayStream* stream) {
    vcf_arrow_private_t* priv = (vcf_arrow_private_t*)stream->private_data;
    return priv->error_msg[0] ? priv->error_msg : NULL;
}

static void vcf_stream_release(struct ArrowArrayStream* stream) {
    if (stream->private_data) {
        vcf_arrow_private_t* priv = (vcf_arrow_private_t*)stream->private_data;
        
        if (priv->rec) bcf_destroy(priv->rec);
        if (priv->itr) hts_itr_destroy(priv->itr);
        if (priv->idx) hts_idx_destroy(priv->idx);
        if (priv->hdr) bcf_hdr_destroy(priv->hdr);
        if (priv->fp) hts_close(priv->fp);
        
        if (priv->cached_schema && priv->cached_schema->release) {
            priv->cached_schema->release(priv->cached_schema);
            vcf_arrow_free(priv->cached_schema);
        }
        
        vcf_arrow_free(priv);
    }
    stream->release = NULL;
}

// =============================================================================
// Public API Implementation
// =============================================================================

void vcf_arrow_options_init(vcf_arrow_options_t* opts) {
    memset(opts, 0, sizeof(*opts));
    opts->batch_size = VCF_ARROW_DEFAULT_BATCH_SIZE;
    opts->include_info = 1;
    opts->include_format = 1;
    opts->region = NULL;
    opts->samples = NULL;
    opts->threads = 0;
}

int vcf_arrow_stream_init(struct ArrowArrayStream* stream,
                          const char* filename,
                          const vcf_arrow_options_t* opts) {
    // Allocate private data
    vcf_arrow_private_t* priv = (vcf_arrow_private_t*)vcf_arrow_malloc(sizeof(vcf_arrow_private_t));
    if (!priv) {
        return ENOMEM;
    }
    memset(priv, 0, sizeof(*priv));
    
    // Copy options
    if (opts) {
        priv->opts = *opts;
    } else {
        vcf_arrow_options_init(&priv->opts);
    }
    
    // Open file
    priv->fp = hts_open(filename, "r");
    if (!priv->fp) {
        snprintf(priv->error_msg, sizeof(priv->error_msg), 
                 "Failed to open file: %s", filename);
        vcf_arrow_free(priv);
        return ENOENT;
    }
    
    // Set threads if requested
    if (priv->opts.threads > 0) {
        hts_set_threads(priv->fp, priv->opts.threads);
    }
    
    // Read header
    priv->hdr = bcf_hdr_read(priv->fp);
    if (!priv->hdr) {
        snprintf(priv->error_msg, sizeof(priv->error_msg), 
                 "Failed to read VCF header");
        hts_close(priv->fp);
        vcf_arrow_free(priv);
        return EIO;
    }
    
    // Set up sample filtering if requested
    if (priv->opts.samples) {
        if (bcf_hdr_set_samples(priv->hdr, priv->opts.samples, 0) < 0) {
            snprintf(priv->error_msg, sizeof(priv->error_msg), 
                     "Failed to set samples filter");
            bcf_hdr_destroy(priv->hdr);
            hts_close(priv->fp);
            vcf_arrow_free(priv);
            return EINVAL;
        }
    }
    
    // Set up region filtering if requested
    if (priv->opts.region) {
        priv->idx = bcf_index_load(filename);
        if (!priv->idx) {
            // Try loading with different suffix
            priv->idx = bcf_index_load2(filename, NULL);
        }
        
        if (priv->idx) {
            priv->itr = bcf_itr_querys(priv->idx, priv->hdr, priv->opts.region);
            if (!priv->itr) {
                snprintf(priv->error_msg, sizeof(priv->error_msg), 
                         "Failed to query region: %s", priv->opts.region);
                hts_idx_destroy(priv->idx);
                bcf_hdr_destroy(priv->hdr);
                hts_close(priv->fp);
                vcf_arrow_free(priv);
                return EINVAL;
            }
        } else {
            snprintf(priv->error_msg, sizeof(priv->error_msg), 
                     "No index available for region query");
            bcf_hdr_destroy(priv->hdr);
            hts_close(priv->fp);
            vcf_arrow_free(priv);
            return ENOENT;
        }
    }
    
    // Allocate reusable record
    priv->rec = bcf_init();
    if (!priv->rec) {
        snprintf(priv->error_msg, sizeof(priv->error_msg), 
                 "Failed to allocate BCF record");
        if (priv->itr) hts_itr_destroy(priv->itr);
        if (priv->idx) hts_idx_destroy(priv->idx);
        bcf_hdr_destroy(priv->hdr);
        hts_close(priv->fp);
        vcf_arrow_free(priv);
        return ENOMEM;
    }
    
    // Initialize stream
    stream->get_schema = &vcf_stream_get_schema;
    stream->get_next = &vcf_stream_get_next;
    stream->get_last_error = &vcf_stream_get_last_error;
    stream->release = &vcf_stream_release;
    stream->private_data = priv;
    
    return 0;
}

int vcf_arrow_read_batch(htsFile* fp,
                         bcf_hdr_t* hdr,
                         hts_itr_t* itr,
                         int64_t batch_size,
                         struct ArrowArray* array,
                         const vcf_arrow_options_t* opts) {
    // Create a temporary stream and read one batch
    vcf_arrow_private_t priv;
    memset(&priv, 0, sizeof(priv));
    
    priv.fp = fp;
    priv.hdr = hdr;
    priv.itr = itr;
    priv.rec = bcf_init();
    
    if (opts) {
        priv.opts = *opts;
    } else {
        vcf_arrow_options_init(&priv.opts);
    }
    priv.opts.batch_size = batch_size;
    
    struct ArrowArrayStream stream;
    stream.private_data = &priv;
    
    int ret = vcf_stream_get_next(&stream, array);
    
    bcf_destroy(priv.rec);
    
    if (ret != 0) {
        return -1;
    }
    
    return array->length;
}
