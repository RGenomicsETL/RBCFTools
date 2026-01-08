/**
 * vep_parser.h - VEP/SnpEff/BCSQ Annotation Parser
 *
 * Parses structured annotation fields (CSQ, BCSQ, ANN) from VCF headers
 * and records. Provides type inference based on field names following
 * bcftools split-vep conventions.
 *
 * Copyright (c) 2026 RBCFTools Authors
 * Licensed under MIT License
 */

#ifndef VEP_PARSER_H
#define VEP_PARSER_H

#include <htslib/vcf.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Constants
// =============================================================================

/** Maximum number of fields in a VEP annotation */
#define VEP_MAX_FIELDS 256

/** Maximum field name length */
#define VEP_MAX_FIELD_NAME 128

/** Known annotation tags (in priority order for auto-detection) */
#define VEP_TAG_CSQ   "CSQ"
#define VEP_TAG_BCSQ  "BCSQ"
#define VEP_TAG_ANN   "ANN"

// =============================================================================
// Type Definitions
// =============================================================================

/**
 * Inferred field types (matching BCF_HT_* for compatibility)
 */
typedef enum {
    VEP_TYPE_STRING  = BCF_HT_STR,
    VEP_TYPE_INTEGER = BCF_HT_INT,
    VEP_TYPE_FLOAT   = BCF_HT_REAL,
    VEP_TYPE_FLAG    = BCF_HT_FLAG
} vep_field_type_t;

/**
 * Metadata for a single annotation field
 */
typedef struct {
    char* name;              /**< Field name (e.g., "Consequence", "SYMBOL", "AF") */
    vep_field_type_t type;   /**< Inferred or explicit type */
    int index;               /**< Position in the pipe-delimited string (0-based) */
    int is_list;             /**< Whether values can be comma-separated (e.g., Consequence) */
} vep_field_t;

/**
 * Parsed annotation schema from VCF header
 */
typedef struct {
    char* tag_name;          /**< Tag name (CSQ, BCSQ, ANN) */
    int n_fields;            /**< Number of fields */
    vep_field_t* fields;     /**< Array of field metadata */
    int header_id;           /**< BCF header ID for bcf_get_info_* */
} vep_schema_t;

/**
 * Single parsed value (union for different types)
 */
typedef struct {
    char* str_value;         /**< Raw string value (always set if present) */
    int32_t int_value;       /**< Parsed integer (INT32_MIN if missing) */
    float float_value;       /**< Parsed float (NaN if missing) */
    int is_missing;          /**< 1 if value is empty/missing */
} vep_value_t;

/**
 * Parsed annotation for a single transcript/consequence
 */
typedef struct {
    int n_values;            /**< Number of values (equals schema->n_fields) */
    vep_value_t* values;     /**< Array of parsed values */
} vep_transcript_t;

/**
 * All transcripts for a single variant record
 */
typedef struct {
    int n_transcripts;              /**< Number of transcripts/consequences */
    vep_transcript_t* transcripts;  /**< Array of transcript annotations */
} vep_record_t;

/**
 * Options for parsing behavior
 */
typedef struct {
    const char* tag;         /**< Tag to parse (NULL = auto-detect) */
    const char* columns;     /**< Comma-separated column names to extract (NULL = all) */
    int transcript_mode;     /**< 0=all, 1=first (worst), 2=canonical */
} vep_options_t;

// =============================================================================
// Schema Functions
// =============================================================================

/**
 * Initialize default options
 *
 * @param opts Options structure to initialize
 */
void vep_options_init(vep_options_t* opts);

/**
 * Parse annotation schema from VCF header
 *
 * Extracts field names and types from the Description field of INFO/CSQ, 
 * INFO/BCSQ, or INFO/ANN. If tag is NULL, auto-detects the annotation tag.
 *
 * @param hdr VCF/BCF header
 * @param tag Annotation tag name (CSQ, BCSQ, ANN) or NULL for auto-detect
 * @return Allocated schema, or NULL on error. Caller must free with vep_schema_destroy()
 */
vep_schema_t* vep_schema_parse(const bcf_hdr_t* hdr, const char* tag);

/**
 * Destroy a schema and free all memory
 *
 * @param schema Schema to destroy (may be NULL)
 */
void vep_schema_destroy(vep_schema_t* schema);

/**
 * Get field index by name
 *
 * @param schema Parsed schema
 * @param name Field name to look up
 * @return Field index (0-based), or -1 if not found
 */
int vep_schema_get_field_index(const vep_schema_t* schema, const char* name);

/**
 * Get field by index
 *
 * @param schema Parsed schema
 * @param index Field index (0-based)
 * @return Pointer to field metadata, or NULL if out of bounds
 */
const vep_field_t* vep_schema_get_field(const vep_schema_t* schema, int index);

// =============================================================================
// Type Inference
// =============================================================================

/**
 * Infer type from field name using bcftools split-vep conventions
 *
 * Known integer fields: DISTANCE, STRAND, TSL, GENE_PHENO, HGVS_OFFSET,
 *   MOTIF_POS, existing_*ORFs, SpliceAI_pred_DP_*
 * Known float fields: AF, *_AF, MAX_AF_*, MOTIF_SCORE_CHANGE, SpliceAI_pred_DS_*
 * All others default to string.
 *
 * @param field_name Name of the field
 * @return Inferred type
 */
vep_field_type_t vep_infer_type(const char* field_name);

/**
 * Get type name as string
 *
 * @param type Field type
 * @return Type name ("Integer", "Float", "String")
 */
const char* vep_type_name(vep_field_type_t type);

// =============================================================================
// Record Parsing
// =============================================================================

/**
 * Parse annotation string into structured record
 *
 * Splits the annotation by comma (transcripts) and pipe (fields), parsing
 * values according to their types.
 *
 * @param schema Parsed schema
 * @param csq_value Raw CSQ/BCSQ/ANN string value from bcf_get_info_string
 * @return Allocated record, or NULL on error. Caller must free with vep_record_destroy()
 */
vep_record_t* vep_record_parse(const vep_schema_t* schema, const char* csq_value);

/**
 * Parse annotation directly from BCF record
 *
 * Convenience wrapper that extracts the annotation string and parses it.
 *
 * @param schema Parsed schema
 * @param hdr VCF/BCF header
 * @param rec VCF/BCF record (must be unpacked)
 * @return Allocated record, or NULL on error. Caller must free with vep_record_destroy()
 */
vep_record_t* vep_record_parse_bcf(const vep_schema_t* schema, 
                                    const bcf_hdr_t* hdr, 
                                    bcf1_t* rec);

/**
 * Destroy a record and free all memory
 *
 * @param record Record to destroy (may be NULL)
 */
void vep_record_destroy(vep_record_t* record);

/**
 * Get a specific value from a transcript
 *
 * @param record Parsed record
 * @param transcript_idx Transcript index (0-based)
 * @param field_idx Field index (0-based)
 * @return Pointer to value, or NULL if out of bounds
 */
const vep_value_t* vep_record_get_value(const vep_record_t* record,
                                         int transcript_idx,
                                         int field_idx);

// =============================================================================
// Utility Functions
// =============================================================================

/**
 * Detect which annotation tag is present in header
 *
 * Checks for CSQ, BCSQ, ANN in that order.
 *
 * @param hdr VCF/BCF header
 * @return Tag name (CSQ, BCSQ, or ANN), or NULL if none found
 */
const char* vep_detect_tag(const bcf_hdr_t* hdr);

/**
 * Check if a VCF header has VEP-style annotations
 *
 * @param hdr VCF/BCF header
 * @return 1 if annotation found, 0 otherwise
 */
int vep_has_annotation(const bcf_hdr_t* hdr);

/**
 * Parse value string to integer
 *
 * @param str String value
 * @param result Output integer
 * @return 1 on success, 0 if empty/missing, -1 on parse error
 */
int vep_parse_int(const char* str, int32_t* result);

/**
 * Parse value string to float
 *
 * @param str String value
 * @param result Output float
 * @return 1 on success, 0 if empty/missing, -1 on parse error
 */
int vep_parse_float(const char* str, float* result);

#ifdef __cplusplus
}
#endif

#endif /* VEP_PARSER_H */
