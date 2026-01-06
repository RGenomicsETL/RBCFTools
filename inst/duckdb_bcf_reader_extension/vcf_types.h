/**
 * VCF Type System for DuckDB BCF Reader Extension
 * 
 * This header provides VCF-spec compliant type definitions that match
 * the nanoarrow vcf_arrow_stream implementation for type consistency.
 * 
 * Based on htslib's bcf_hdr_check_sanity() and VCF specification.
 */

#ifndef VCF_TYPES_H
#define VCF_TYPES_H

#include <htslib/vcf.h>
#include <string.h>
#include <stdio.h>

// =============================================================================
// DuckDB Type Mapping
// =============================================================================

// Arrow format strings (for reference, matching nanoarrow implementation)
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
#define ARROW_FORMAT_BOOL    "b"
#define ARROW_FORMAT_STRUCT  "+s"
#define ARROW_FORMAT_LIST    "+l"

// =============================================================================
// VCF Field Specification (matching nanoarrow's vcf_fmt_spec_t)
// =============================================================================

/**
 * VCF field specification from VCF standard.
 * Used for schema validation and type correction.
 */
typedef struct {
    const char* name;        // Field name (e.g., "AD", "GT", "DP")
    const char* number_str;  // Number string for warnings ("1", "R", "G", "A", ".")
    int vl_type;             // BCF_VL_* constant (FIXED=0, VAR=1, A=2, G=3, R=4)
    int count;               // For BCF_VL_FIXED: the actual count. Ignored for variable.
    int type;                // BCF_HT_* constant (INT, REAL, STR, FLAG)
} vcf_field_spec_t;

// Human-readable type names for warning messages
static const char* vcf_type_names[] = {"Flag", "Integer", "Float", "String"};

// =============================================================================
// Standard FORMAT Field Definitions (from VCF spec / htslib vcf.c)
// =============================================================================

static const vcf_field_spec_t VCF_FORMAT_SPECS[] = {
    // Field   Number  VL_type        count  Type
    {"AD",     "R",    BCF_VL_R,      0,     BCF_HT_INT},   // Allelic depths (ref, alts)
    {"ADF",    "R",    BCF_VL_R,      0,     BCF_HT_INT},   // Allelic depths forward strand
    {"ADR",    "R",    BCF_VL_R,      0,     BCF_HT_INT},   // Allelic depths reverse strand
    {"EC",     "A",    BCF_VL_A,      0,     BCF_HT_INT},   // Expected alternate allele counts
    {"GL",     "G",    BCF_VL_G,      0,     BCF_HT_REAL},  // Genotype likelihoods (log10)
    {"GP",     "G",    BCF_VL_G,      0,     BCF_HT_REAL},  // Genotype posterior probabilities
    {"PL",     "G",    BCF_VL_G,      0,     BCF_HT_INT},   // Phred-scaled genotype likelihoods
    {"PP",     "G",    BCF_VL_G,      0,     BCF_HT_INT},   // Phred-scaled posterior probabilities
    {"DP",     "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Read depth
    {"LEN",    "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Length of variant
    {"FT",     "1",    BCF_VL_FIXED,  1,     BCF_HT_STR},   // Filter (per-sample)
    {"GQ",     "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Genotype quality
    {"GT",     "1",    BCF_VL_FIXED,  1,     BCF_HT_STR},   // Genotype
    {"HQ",     "2",    BCF_VL_FIXED,  2,     BCF_HT_INT},   // Haplotype qualities
    {"MQ",     "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Mapping quality
    {"PQ",     "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Phasing quality
    {"PS",     "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Phase set
    {NULL,     NULL,   0,             0,     0}
};

// =============================================================================
// Standard INFO Field Definitions (from VCF spec / htslib vcf.c)
// =============================================================================

static const vcf_field_spec_t VCF_INFO_SPECS[] = {
    // Field       Number  VL_type        count  Type
    {"AD",         "R",    BCF_VL_R,      0,     BCF_HT_INT},   // Total allelic depths
    {"ADF",        "R",    BCF_VL_R,      0,     BCF_HT_INT},   // Total allelic depths forward
    {"ADR",        "R",    BCF_VL_R,      0,     BCF_HT_INT},   // Total allelic depths reverse
    {"AC",         "A",    BCF_VL_A,      0,     BCF_HT_INT},   // Allele count in genotypes
    {"AF",         "A",    BCF_VL_A,      0,     BCF_HT_REAL},  // Allele frequency
    {"CIGAR",      "A",    BCF_VL_A,      0,     BCF_HT_STR},   // CIGAR string for each allele
    {"AA",         "1",    BCF_VL_FIXED,  1,     BCF_HT_STR},   // Ancestral allele
    {"AN",         "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Total number of alleles in genotypes
    {"BQ",         "1",    BCF_VL_FIXED,  1,     BCF_HT_REAL},  // RMS base quality
    {"DB",         "0",    BCF_VL_FIXED,  0,     BCF_HT_FLAG},  // dbSNP membership
    {"DP",         "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Combined depth
    {"END",        "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // End position
    {"H2",         "0",    BCF_VL_FIXED,  0,     BCF_HT_FLAG},  // HapMap2 membership
    {"H3",         "0",    BCF_VL_FIXED,  0,     BCF_HT_FLAG},  // HapMap3 membership
    {"MQ",         "1",    BCF_VL_FIXED,  1,     BCF_HT_REAL},  // RMS mapping quality
    {"MQ0",        "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Number of MAPQ == 0 reads
    {"NS",         "1",    BCF_VL_FIXED,  1,     BCF_HT_INT},   // Number of samples with data
    {"SB",         "4",    BCF_VL_FIXED,  4,     BCF_HT_INT},   // Strand bias
    {"SOMATIC",    "0",    BCF_VL_FIXED,  0,     BCF_HT_FLAG},  // Somatic mutation
    {"VALIDATED",  "0",    BCF_VL_FIXED,  0,     BCF_HT_FLAG},  // Validated by follow-up
    {"1000G",      "0",    BCF_VL_FIXED,  0,     BCF_HT_FLAG},  // 1000 Genomes membership
    {NULL,         NULL,   0,             0,     0}
};

// =============================================================================
// Lookup Functions
// =============================================================================

/**
 * Look up a FORMAT field specification by name.
 * Returns NULL if not a standard VCF field.
 */
static inline const vcf_field_spec_t* vcf_lookup_format_spec(const char* name) {
    for (int i = 0; VCF_FORMAT_SPECS[i].name != NULL; i++) {
        if (strcmp(name, VCF_FORMAT_SPECS[i].name) == 0) {
            return &VCF_FORMAT_SPECS[i];
        }
    }
    return NULL;
}

/**
 * Look up an INFO field specification by name.
 * Returns NULL if not a standard VCF field.
 */
static inline const vcf_field_spec_t* vcf_lookup_info_spec(const char* name) {
    for (int i = 0; VCF_INFO_SPECS[i].name != NULL; i++) {
        if (strcmp(name, VCF_INFO_SPECS[i].name) == 0) {
            return &VCF_INFO_SPECS[i];
        }
    }
    return NULL;
}

// =============================================================================
// Validation Functions
// =============================================================================

/**
 * Check if Number (BCF_VL_* type) needs correction based on VCF spec.
 * Returns 1 if correction is needed, 0 if OK.
 */
static inline int vcf_check_number(const vcf_field_spec_t* spec, int header_vl_type) {
    if (!spec) return 0;
    
    if (spec->vl_type == BCF_VL_FIXED) {
        // Fixed-count field - header must also be fixed
        return (header_vl_type != BCF_VL_FIXED);
    } else {
        // Variable length field - header should match the specific type
        // We tolerate BCF_VL_VAR (Number=.) as a fallback
        if (header_vl_type == spec->vl_type || header_vl_type == BCF_VL_VAR) {
            return 0;  // OK
        }
        return 1;  // Wrong variable type
    }
}

/**
 * Check if Type (BCF_HT_*) matches VCF spec.
 * Returns 1 if mismatch, 0 if OK.
 */
static inline int vcf_check_type(const vcf_field_spec_t* spec, int header_type) {
    if (!spec) return 0;
    return (header_type != spec->type);
}

// =============================================================================
// Warning Message Generation (for use with fprintf or duckdb logging)
// =============================================================================

// Callback type for emitting warnings
typedef void (*vcf_warning_func_t)(const char* msg, void* ctx);

// Global warning callback (can be set by extension)
static vcf_warning_func_t g_vcf_warning_func = NULL;
static void* g_vcf_warning_ctx = NULL;

static inline void vcf_set_warning_callback(vcf_warning_func_t func, void* ctx) {
    g_vcf_warning_func = func;
    g_vcf_warning_ctx = ctx;
}

static inline void vcf_emit_warning(const char* msg) {
    if (g_vcf_warning_func) {
        g_vcf_warning_func(msg, g_vcf_warning_ctx);
    } else {
        fprintf(stderr, "Warning: %s\n", msg);
    }
}

/**
 * Validate and correct FORMAT field, emitting warnings if needed.
 * Returns corrected vl_type.
 */
static inline int vcf_validate_format_field(const char* field_name, 
                                            int header_vl_type, 
                                            int header_type,
                                            int* corrected_type) {
    const vcf_field_spec_t* spec = vcf_lookup_format_spec(field_name);
    int corrected_vl_type = header_vl_type;
    *corrected_type = header_type;
    
    if (spec) {
        // Check Number
        if (vcf_check_number(spec, header_vl_type)) {
            char msg[256];
            snprintf(msg, sizeof(msg), 
                     "FORMAT/%s should be Number=%s per VCF spec; correcting schema",
                     field_name, spec->number_str);
            vcf_emit_warning(msg);
            corrected_vl_type = spec->vl_type;
        }
        
        // Check Type (warn but don't correct - data matches header)
        if (vcf_check_type(spec, header_type)) {
            char msg[256];
            snprintf(msg, sizeof(msg),
                     "FORMAT/%s should be Type=%s per VCF spec, but header declares Type=%s; using header type",
                     field_name, vcf_type_names[spec->type], vcf_type_names[header_type]);
            vcf_emit_warning(msg);
            // Don't correct type - data is stored according to header
        }
    }
    
    return corrected_vl_type;
}

/**
 * Validate and correct INFO field, emitting warnings if needed.
 * Returns corrected vl_type.
 */
static inline int vcf_validate_info_field(const char* field_name,
                                          int header_vl_type,
                                          int header_type,
                                          int* corrected_type) {
    const vcf_field_spec_t* spec = vcf_lookup_info_spec(field_name);
    int corrected_vl_type = header_vl_type;
    *corrected_type = header_type;
    
    if (spec) {
        // Check Number
        if (vcf_check_number(spec, header_vl_type)) {
            char msg[256];
            snprintf(msg, sizeof(msg),
                     "INFO/%s should be Number=%s per VCF spec; correcting schema",
                     field_name, spec->number_str);
            vcf_emit_warning(msg);
            corrected_vl_type = spec->vl_type;
        }
        
        // Check Type (warn but don't correct)
        if (vcf_check_type(spec, header_type)) {
            char msg[256];
            snprintf(msg, sizeof(msg),
                     "INFO/%s should be Type=%s per VCF spec, but header declares Type=%s; using header type",
                     field_name, vcf_type_names[spec->type], vcf_type_names[header_type]);
            vcf_emit_warning(msg);
        }
    }
    
    return corrected_vl_type;
}

// =============================================================================
// Type Mapping Utilities
// =============================================================================

/**
 * Determine if a field should be represented as a list based on BCF_VL_* type.
 * BCF_VL_FIXED (0) = scalar
 * BCF_VL_VAR (1), BCF_VL_A (2), BCF_VL_G (3), BCF_VL_R (4) = list
 */
static inline int vcf_is_list_type(int vl_type) {
    return (vl_type != BCF_VL_FIXED);
}

/**
 * Get the expected count for a field at a specific variant.
 * Used for allocating buffers.
 */
static inline int vcf_get_expected_count(int vl_type, int n_allele, int ploidy) {
    switch (vl_type) {
        case BCF_VL_FIXED:
            return 1;  // Scalar
        case BCF_VL_VAR:
            return -1;  // Variable, unknown
        case BCF_VL_A:
            return n_allele - 1;  // Number of alternate alleles
        case BCF_VL_G:
            // Number of genotypes: (n * (n+1)) / 2 for diploid
            // General formula: combination with replacement
            return (n_allele * (n_allele + 1)) / 2;
        case BCF_VL_R:
            return n_allele;  // Number of alleles (ref + alt)
        default:
            return -1;
    }
}

#endif // VCF_TYPES_H
