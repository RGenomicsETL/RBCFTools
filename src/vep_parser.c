/**
 * vep_parser.c - VEP/SnpEff/BCSQ Annotation Parser Implementation
 *
 * Copyright (c) 2026 RBCFTools Authors
 * Licensed under MIT License
 */

#include "vep_parser.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <math.h>
#include <regex.h>

// =============================================================================
// Memory Management
// =============================================================================

static void* vep_malloc(size_t size) {
    return malloc(size);
}

static void vep_free(void* ptr) {
    free(ptr);
}

static char* vep_strdup(const char* s) {
    if (s == NULL) return NULL;
    size_t len = strlen(s) + 1;
    char* copy = (char*)vep_malloc(len);
    if (copy) memcpy(copy, s, len);
    return copy;
}

// =============================================================================
// Type Inference Patterns
// =============================================================================

/** Type inference rule */
typedef struct {
    const char* pattern;     /**< Regex pattern (anchored with ^$) */
    vep_field_type_t type;   /**< Type to assign */
    int is_regex;            /**< 1 if pattern contains regex chars */
} type_rule_t;

/**
 * Default type inference rules from bcftools split-vep
 * Order matters - first match wins
 */
static const type_rule_t DEFAULT_TYPE_RULES[] = {
    // Exact matches (faster, checked first)
    {"DISTANCE",                   VEP_TYPE_INTEGER, 0},
    {"STRAND",                     VEP_TYPE_INTEGER, 0},
    {"TSL",                        VEP_TYPE_INTEGER, 0},
    {"GENE_PHENO",                 VEP_TYPE_INTEGER, 0},
    {"HGVS_OFFSET",                VEP_TYPE_INTEGER, 0},
    {"MOTIF_POS",                  VEP_TYPE_INTEGER, 0},
    {"MOTIF_SCORE_CHANGE",         VEP_TYPE_FLOAT,   0},
    {"AF",                         VEP_TYPE_FLOAT,   0},
    {"existing_InFrame_oORFs",     VEP_TYPE_INTEGER, 0},
    {"existing_OutOfFrame_oORFs",  VEP_TYPE_INTEGER, 0},
    {"existing_uORFs",             VEP_TYPE_INTEGER, 0},
    {"ALLELE_NUM",                 VEP_TYPE_INTEGER, 0},
    {"PICK",                       VEP_TYPE_INTEGER, 0},
    {"CANONICAL",                  VEP_TYPE_INTEGER, 0},
    
    // Regex patterns (checked if no exact match)
    {".*_AF$",                     VEP_TYPE_FLOAT,   1},  // gnomAD_AF, etc.
    {"^MAX_AF_.*",                 VEP_TYPE_FLOAT,   1},  // MAX_AF_POPS is string though
    {"^SpliceAI_pred_DP_.*",       VEP_TYPE_INTEGER, 1},  // SpliceAI_pred_DP_AG, etc.
    {"^SpliceAI_pred_DS_.*",       VEP_TYPE_FLOAT,   1},  // SpliceAI_pred_DS_AG, etc.
    {".*_POPS$",                   VEP_TYPE_STRING,  1},  // MAX_AF_POPS
    
    // Sentinel
    {NULL, VEP_TYPE_STRING, 0}
};

vep_field_type_t vep_infer_type(const char* field_name) {
    if (!field_name || !*field_name) {
        return VEP_TYPE_STRING;
    }
    
    // First try exact matches (fast path)
    for (int i = 0; DEFAULT_TYPE_RULES[i].pattern != NULL; i++) {
        if (!DEFAULT_TYPE_RULES[i].is_regex) {
            if (strcmp(field_name, DEFAULT_TYPE_RULES[i].pattern) == 0) {
                return DEFAULT_TYPE_RULES[i].type;
            }
        }
    }
    
    // Then try regex patterns
    for (int i = 0; DEFAULT_TYPE_RULES[i].pattern != NULL; i++) {
        if (DEFAULT_TYPE_RULES[i].is_regex) {
            // Build anchored pattern
            char pattern[256];
            snprintf(pattern, sizeof(pattern), "^%s$", DEFAULT_TYPE_RULES[i].pattern);
            
            regex_t regex;
            if (regcomp(&regex, pattern, REG_EXTENDED | REG_NOSUB) == 0) {
                int match = regexec(&regex, field_name, 0, NULL, 0) == 0;
                regfree(&regex);
                if (match) {
                    return DEFAULT_TYPE_RULES[i].type;
                }
            }
        }
    }
    
    return VEP_TYPE_STRING;
}

const char* vep_type_name(vep_field_type_t type) {
    switch (type) {
        case VEP_TYPE_INTEGER: return "Integer";
        case VEP_TYPE_FLOAT:   return "Float";
        case VEP_TYPE_FLAG:    return "Flag";
        case VEP_TYPE_STRING:
        default:               return "String";
    }
}

// =============================================================================
// Options
// =============================================================================

void vep_options_init(vep_options_t* opts) {
    if (!opts) return;
    memset(opts, 0, sizeof(*opts));
    opts->tag = NULL;
    opts->columns = NULL;
    opts->transcript_mode = 0;  // all
}

// =============================================================================
// Tag Detection
// =============================================================================

const char* vep_detect_tag(const bcf_hdr_t* hdr) {
    if (!hdr) return NULL;
    
    // Check in priority order: CSQ, BCSQ, ANN
    const char* tags[] = {VEP_TAG_CSQ, VEP_TAG_BCSQ, VEP_TAG_ANN, NULL};
    
    for (int i = 0; tags[i] != NULL; i++) {
        int id = bcf_hdr_id2int(hdr, BCF_DT_ID, tags[i]);
        if (id >= 0 && bcf_hdr_idinfo_exists(hdr, BCF_HL_INFO, id)) {
            return tags[i];
        }
    }
    
    return NULL;
}

int vep_has_annotation(const bcf_hdr_t* hdr) {
    return vep_detect_tag(hdr) != NULL;
}

// =============================================================================
// Schema Parsing
// =============================================================================

/**
 * Parse Format string from VEP header Description
 * 
 * Example: "...Format: Allele|Consequence|IMPACT|SYMBOL|..."
 * Returns allocated array of field names, sets *n_fields.
 */
static char** parse_format_string(const char* description, int* n_fields) {
    *n_fields = 0;
    
    if (!description) return NULL;
    
    // Find "Format: " or "Format:" in description
    const char* format_start = strstr(description, "Format: ");
    if (!format_start) {
        format_start = strstr(description, "Format:");
    }
    if (!format_start) {
        // Try just looking for the pipe-delimited part after a common pattern
        // Some VEPs use "...fields: Allele|..."
        format_start = strstr(description, "fields: ");
    }
    if (!format_start) {
        return NULL;
    }
    
    // Skip to the field list
    format_start = strchr(format_start, ':');
    if (!format_start) return NULL;
    format_start++;  // skip ':'
    
    // Skip whitespace
    while (*format_start && isspace((unsigned char)*format_start)) {
        format_start++;
    }
    
    if (!*format_start) return NULL;
    
    // Find end - either end of string, quote, or newline
    const char* format_end = format_start;
    while (*format_end && *format_end != '"' && *format_end != '\n' && *format_end != '>') {
        format_end++;
    }
    
    // Copy the format string
    size_t len = format_end - format_start;
    char* format_copy = (char*)vep_malloc(len + 1);
    if (!format_copy) return NULL;
    memcpy(format_copy, format_start, len);
    format_copy[len] = '\0';
    
    // Trim trailing whitespace
    while (len > 0 && isspace((unsigned char)format_copy[len-1])) {
        format_copy[--len] = '\0';
    }
    
    // Count fields (pipes + 1)
    int count = 1;
    for (size_t i = 0; i < len; i++) {
        if (format_copy[i] == '|') count++;
    }
    
    // Allocate field array
    char** fields = (char**)vep_malloc(count * sizeof(char*));
    if (!fields) {
        vep_free(format_copy);
        return NULL;
    }
    
    // Parse fields
    int field_idx = 0;
    char* saveptr = NULL;
    char* token = strtok_r(format_copy, "|", &saveptr);
    
    while (token && field_idx < count) {
        // Trim whitespace
        while (*token && isspace((unsigned char)*token)) token++;
        char* end = token + strlen(token) - 1;
        while (end > token && isspace((unsigned char)*end)) *end-- = '\0';
        
        fields[field_idx++] = vep_strdup(token);
        token = strtok_r(NULL, "|", &saveptr);
    }
    
    vep_free(format_copy);
    *n_fields = field_idx;
    return fields;
}

vep_schema_t* vep_schema_parse(const bcf_hdr_t* hdr, const char* tag) {
    if (!hdr) return NULL;
    
    // Auto-detect tag if not specified
    const char* detected_tag = tag;
    if (!detected_tag) {
        detected_tag = vep_detect_tag(hdr);
    }
    if (!detected_tag) {
        return NULL;  // No annotation found
    }
    
    // Get header ID
    int id = bcf_hdr_id2int(hdr, BCF_DT_ID, detected_tag);
    if (id < 0 || !bcf_hdr_idinfo_exists(hdr, BCF_HL_INFO, id)) {
        return NULL;
    }
    
    // Get the header record to extract Description
    bcf_hrec_t* hrec = bcf_hdr_get_hrec(hdr, BCF_HL_INFO, "ID", detected_tag, NULL);
    if (!hrec) {
        return NULL;
    }
    
    // Find Description field
    const char* description = NULL;
    for (int i = 0; i < hrec->nkeys; i++) {
        if (strcmp(hrec->keys[i], "Description") == 0) {
            description = hrec->vals[i];
            break;
        }
    }
    
    if (!description) {
        return NULL;
    }
    
    // Parse format string
    int n_fields = 0;
    char** field_names = parse_format_string(description, &n_fields);
    
    if (!field_names || n_fields == 0) {
        return NULL;
    }
    
    // Create schema
    vep_schema_t* schema = (vep_schema_t*)vep_malloc(sizeof(vep_schema_t));
    if (!schema) {
        for (int i = 0; i < n_fields; i++) vep_free(field_names[i]);
        vep_free(field_names);
        return NULL;
    }
    
    schema->tag_name = vep_strdup(detected_tag);
    schema->n_fields = n_fields;
    schema->header_id = id;
    schema->fields = (vep_field_t*)vep_malloc(n_fields * sizeof(vep_field_t));
    
    if (!schema->fields) {
        vep_free(schema->tag_name);
        vep_free(schema);
        for (int i = 0; i < n_fields; i++) vep_free(field_names[i]);
        vep_free(field_names);
        return NULL;
    }
    
    // Initialize fields with inferred types
    for (int i = 0; i < n_fields; i++) {
        schema->fields[i].name = field_names[i];  // Transfer ownership
        schema->fields[i].type = vep_infer_type(field_names[i]);
        schema->fields[i].index = i;
        
        // Consequence field can have multiple values (e.g., "missense_variant&splice_region_variant")
        schema->fields[i].is_list = (strcmp(field_names[i], "Consequence") == 0 ||
                                     strcmp(field_names[i], "FLAGS") == 0 ||
                                     strcmp(field_names[i], "CLIN_SIG") == 0);
    }
    
    vep_free(field_names);  // Array only, strings transferred
    
    return schema;
}

void vep_schema_destroy(vep_schema_t* schema) {
    if (!schema) return;
    
    if (schema->fields) {
        for (int i = 0; i < schema->n_fields; i++) {
            vep_free(schema->fields[i].name);
        }
        vep_free(schema->fields);
    }
    
    vep_free(schema->tag_name);
    vep_free(schema);
}

int vep_schema_get_field_index(const vep_schema_t* schema, const char* name) {
    if (!schema || !name) return -1;
    
    for (int i = 0; i < schema->n_fields; i++) {
        if (schema->fields[i].name && strcmp(schema->fields[i].name, name) == 0) {
            return i;
        }
    }
    
    return -1;
}

const vep_field_t* vep_schema_get_field(const vep_schema_t* schema, int index) {
    if (!schema || index < 0 || index >= schema->n_fields) {
        return NULL;
    }
    return &schema->fields[index];
}

// =============================================================================
// Value Parsing
// =============================================================================

int vep_parse_int(const char* str, int32_t* result) {
    if (!str || !*str || strcmp(str, ".") == 0) {
        *result = INT32_MIN;
        return 0;  // Empty/missing
    }
    
    char* endptr;
    long val = strtol(str, &endptr, 10);
    
    if (endptr == str || *endptr != '\0') {
        *result = INT32_MIN;
        return -1;  // Parse error
    }
    
    *result = (int32_t)val;
    return 1;  // Success
}

int vep_parse_float(const char* str, float* result) {
    if (!str || !*str || strcmp(str, ".") == 0) {
        *result = NAN;
        return 0;  // Empty/missing
    }
    
    char* endptr;
    double val = strtod(str, &endptr);
    
    if (endptr == str || *endptr != '\0') {
        *result = NAN;
        return -1;  // Parse error
    }
    
    *result = (float)val;
    return 1;  // Success
}

// =============================================================================
// Record Parsing
// =============================================================================

/**
 * Count occurrences of a character in a string
 */
static int count_char(const char* s, char c) {
    int count = 0;
    while (*s) {
        if (*s == c) count++;
        s++;
    }
    return count;
}

/**
 * Parse a single transcript annotation
 */
static vep_transcript_t* parse_single_transcript(const vep_schema_t* schema, 
                                                  const char* transcript_str) {
    if (!schema || !transcript_str) return NULL;
    
    vep_transcript_t* transcript = (vep_transcript_t*)vep_malloc(sizeof(vep_transcript_t));
    if (!transcript) return NULL;
    
    transcript->n_values = schema->n_fields;
    transcript->values = (vep_value_t*)vep_malloc(schema->n_fields * sizeof(vep_value_t));
    
    if (!transcript->values) {
        vep_free(transcript);
        return NULL;
    }
    
    // Initialize all values as missing
    for (int i = 0; i < schema->n_fields; i++) {
        transcript->values[i].str_value = NULL;
        transcript->values[i].int_value = INT32_MIN;
        transcript->values[i].float_value = NAN;
        transcript->values[i].is_missing = 1;
    }
    
    // Make a copy for tokenization
    char* copy = vep_strdup(transcript_str);
    if (!copy) {
        vep_free(transcript->values);
        vep_free(transcript);
        return NULL;
    }
    
    // Parse pipe-delimited fields
    int field_idx = 0;
    char* token = copy;
    char* next_pipe;
    
    while (field_idx < schema->n_fields) {
        // Find next pipe or end of string
        next_pipe = strchr(token, '|');
        if (next_pipe) {
            *next_pipe = '\0';
        }
        
        // Skip leading/trailing whitespace
        while (*token && isspace((unsigned char)*token)) token++;
        char* end = token + strlen(token) - 1;
        while (end > token && isspace((unsigned char)*end)) *end-- = '\0';
        
        // Store value
        if (*token && strcmp(token, ".") != 0) {
            transcript->values[field_idx].str_value = vep_strdup(token);
            transcript->values[field_idx].is_missing = 0;
            
            // Parse typed value
            const vep_field_t* field = &schema->fields[field_idx];
            if (field->type == VEP_TYPE_INTEGER) {
                vep_parse_int(token, &transcript->values[field_idx].int_value);
            } else if (field->type == VEP_TYPE_FLOAT) {
                vep_parse_float(token, &transcript->values[field_idx].float_value);
            }
        }
        
        field_idx++;
        
        if (!next_pipe) break;
        token = next_pipe + 1;
    }
    
    vep_free(copy);
    return transcript;
}

vep_record_t* vep_record_parse(const vep_schema_t* schema, const char* csq_value) {
    if (!schema || !csq_value || !*csq_value) {
        return NULL;
    }
    
    // Count transcripts (comma-separated)
    int n_transcripts = count_char(csq_value, ',') + 1;
    
    // Allocate record
    vep_record_t* record = (vep_record_t*)vep_malloc(sizeof(vep_record_t));
    if (!record) return NULL;
    
    record->n_transcripts = 0;
    record->transcripts = (vep_transcript_t*)vep_malloc(n_transcripts * sizeof(vep_transcript_t));
    
    if (!record->transcripts) {
        vep_free(record);
        return NULL;
    }
    
    // Parse each transcript
    char* copy = vep_strdup(csq_value);
    if (!copy) {
        vep_free(record->transcripts);
        vep_free(record);
        return NULL;
    }
    
    char* saveptr = NULL;
    char* token = strtok_r(copy, ",", &saveptr);
    
    while (token && record->n_transcripts < n_transcripts) {
        vep_transcript_t* transcript = parse_single_transcript(schema, token);
        if (transcript) {
            // Copy transcript data
            record->transcripts[record->n_transcripts] = *transcript;
            vep_free(transcript);  // Free struct only, data transferred
            record->n_transcripts++;
        }
        token = strtok_r(NULL, ",", &saveptr);
    }
    
    vep_free(copy);
    
    if (record->n_transcripts == 0) {
        vep_free(record->transcripts);
        vep_free(record);
        return NULL;
    }
    
    return record;
}

vep_record_t* vep_record_parse_bcf(const vep_schema_t* schema, 
                                    const bcf_hdr_t* hdr, 
                                    bcf1_t* rec) {
    if (!schema || !hdr || !rec) return NULL;
    
    // Get annotation string
    char* csq_value = NULL;
    int n_csq = 0;
    int ret = bcf_get_info_string(hdr, rec, schema->tag_name, &csq_value, &n_csq);
    
    if (ret <= 0 || !csq_value) {
        free(csq_value);
        return NULL;
    }
    
    vep_record_t* record = vep_record_parse(schema, csq_value);
    free(csq_value);
    
    return record;
}

void vep_record_destroy(vep_record_t* record) {
    if (!record) return;
    
    if (record->transcripts) {
        for (int i = 0; i < record->n_transcripts; i++) {
            if (record->transcripts[i].values) {
                for (int j = 0; j < record->transcripts[i].n_values; j++) {
                    vep_free(record->transcripts[i].values[j].str_value);
                }
                vep_free(record->transcripts[i].values);
            }
        }
        vep_free(record->transcripts);
    }
    
    vep_free(record);
}

const vep_value_t* vep_record_get_value(const vep_record_t* record,
                                         int transcript_idx,
                                         int field_idx) {
    if (!record) return NULL;
    if (transcript_idx < 0 || transcript_idx >= record->n_transcripts) return NULL;
    
    const vep_transcript_t* transcript = &record->transcripts[transcript_idx];
    if (field_idx < 0 || field_idx >= transcript->n_values) return NULL;
    
    return &transcript->values[field_idx];
}
