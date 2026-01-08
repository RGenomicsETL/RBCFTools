/**
 * vep_parser_r.c - R bindings for VEP annotation parser
 *
 * Copyright (c) 2026 RBCFTools Authors
 * Licensed under MIT License
 */

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include "vep_parser.h"
#include <htslib/hts.h>

/**
 * RC_vep_detect_tag - Detect VEP annotation tag in VCF header
 *
 * @param filename_sexp Path to VCF/BCF file
 * @return Character vector with tag name (CSQ, BCSQ, ANN) or NA if not found
 */
SEXP RC_vep_detect_tag(SEXP filename_sexp) {
    if (TYPEOF(filename_sexp) != STRSXP || Rf_length(filename_sexp) != 1) {
        Rf_error("filename must be a single character string");
    }
    
    const char* filename = CHAR(STRING_ELT(filename_sexp, 0));
    
    htsFile* fp = hts_open(filename, "r");
    if (!fp) {
        Rf_error("Failed to open file: %s", filename);
    }
    
    bcf_hdr_t* hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        Rf_error("Failed to read VCF/BCF header");
    }
    
    const char* tag = vep_detect_tag(hdr);
    
    SEXP result = PROTECT(Rf_allocVector(STRSXP, 1));
    if (tag) {
        SET_STRING_ELT(result, 0, Rf_mkChar(tag));
    } else {
        SET_STRING_ELT(result, 0, NA_STRING);
    }
    
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    UNPROTECT(1);
    return result;
}

/**
 * RC_vep_has_annotation - Check if VCF has VEP-style annotations
 *
 * @param filename_sexp Path to VCF/BCF file
 * @return Logical scalar
 */
SEXP RC_vep_has_annotation(SEXP filename_sexp) {
    if (TYPEOF(filename_sexp) != STRSXP || Rf_length(filename_sexp) != 1) {
        Rf_error("filename must be a single character string");
    }
    
    const char* filename = CHAR(STRING_ELT(filename_sexp, 0));
    
    htsFile* fp = hts_open(filename, "r");
    if (!fp) {
        Rf_error("Failed to open file: %s", filename);
    }
    
    bcf_hdr_t* hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        Rf_error("Failed to read VCF/BCF header");
    }
    
    int has_ann = vep_has_annotation(hdr);
    
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    return Rf_ScalarLogical(has_ann);
}

/**
 * RC_vep_get_schema - Get VEP annotation schema from VCF header
 *
 * @param filename_sexp Path to VCF/BCF file
 * @param tag_sexp Optional tag name (NULL for auto-detect)
 * @return Data frame with columns: name, type, index
 */
SEXP RC_vep_get_schema(SEXP filename_sexp, SEXP tag_sexp) {
    if (TYPEOF(filename_sexp) != STRSXP || Rf_length(filename_sexp) != 1) {
        Rf_error("filename must be a single character string");
    }
    
    const char* filename = CHAR(STRING_ELT(filename_sexp, 0));
    const char* tag = NULL;
    
    if (!Rf_isNull(tag_sexp) && TYPEOF(tag_sexp) == STRSXP && Rf_length(tag_sexp) == 1) {
        tag = CHAR(STRING_ELT(tag_sexp, 0));
    }
    
    htsFile* fp = hts_open(filename, "r");
    if (!fp) {
        Rf_error("Failed to open file: %s", filename);
    }
    
    bcf_hdr_t* hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        Rf_error("Failed to read VCF/BCF header");
    }
    
    vep_schema_t* schema = vep_schema_parse(hdr, tag);
    
    if (!schema) {
        bcf_hdr_destroy(hdr);
        hts_close(fp);
        Rf_error("No VEP annotation found in header");
    }
    
    // Create result data frame
    int n = schema->n_fields;
    
    SEXP names_col = PROTECT(Rf_allocVector(STRSXP, n));
    SEXP types_col = PROTECT(Rf_allocVector(STRSXP, n));
    SEXP index_col = PROTECT(Rf_allocVector(INTSXP, n));
    SEXP is_list_col = PROTECT(Rf_allocVector(LGLSXP, n));
    
    for (int i = 0; i < n; i++) {
        SET_STRING_ELT(names_col, i, Rf_mkChar(schema->fields[i].name));
        SET_STRING_ELT(types_col, i, Rf_mkChar(vep_type_name(schema->fields[i].type)));
        INTEGER(index_col)[i] = schema->fields[i].index;
        LOGICAL(is_list_col)[i] = schema->fields[i].is_list;
    }
    
    // Build data frame
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 4));
    SET_VECTOR_ELT(result, 0, names_col);
    SET_VECTOR_ELT(result, 1, types_col);
    SET_VECTOR_ELT(result, 2, index_col);
    SET_VECTOR_ELT(result, 3, is_list_col);
    
    // Set column names
    SEXP col_names = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(col_names, 0, Rf_mkChar("name"));
    SET_STRING_ELT(col_names, 1, Rf_mkChar("type"));
    SET_STRING_ELT(col_names, 2, Rf_mkChar("index"));
    SET_STRING_ELT(col_names, 3, Rf_mkChar("is_list"));
    Rf_setAttrib(result, R_NamesSymbol, col_names);
    
    // Set row names
    SEXP row_names = PROTECT(Rf_allocVector(INTSXP, 2));
    INTEGER(row_names)[0] = NA_INTEGER;
    INTEGER(row_names)[1] = -n;
    Rf_setAttrib(result, R_RowNamesSymbol, row_names);
    
    // Set class
    SEXP class_name = PROTECT(Rf_allocVector(STRSXP, 1));
    SET_STRING_ELT(class_name, 0, Rf_mkChar("data.frame"));
    Rf_setAttrib(result, R_ClassSymbol, class_name);
    
    // Add tag as attribute
    SEXP tag_attr = PROTECT(Rf_allocVector(STRSXP, 1));
    SET_STRING_ELT(tag_attr, 0, Rf_mkChar(schema->tag_name));
    Rf_setAttrib(result, Rf_install("tag"), tag_attr);
    
    vep_schema_destroy(schema);
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    UNPROTECT(9);
    return result;
}

/**
 * RC_vep_infer_type - Infer type from field name
 *
 * @param field_name_sexp Field name (character vector)
 * @return Character vector of inferred types
 */
SEXP RC_vep_infer_type(SEXP field_name_sexp) {
    if (TYPEOF(field_name_sexp) != STRSXP) {
        Rf_error("field_name must be a character vector");
    }
    
    int n = Rf_length(field_name_sexp);
    SEXP result = PROTECT(Rf_allocVector(STRSXP, n));
    
    for (int i = 0; i < n; i++) {
        const char* name = CHAR(STRING_ELT(field_name_sexp, i));
        vep_field_type_t type = vep_infer_type(name);
        SET_STRING_ELT(result, i, Rf_mkChar(vep_type_name(type)));
    }
    
    UNPROTECT(1);
    return result;
}

/**
 * RC_vep_parse_record - Parse VEP annotation from a CSQ string
 *
 * @param csq_sexp CSQ string value
 * @param schema_sexp Schema data frame (from vep_get_schema)
 * @param filename_sexp VCF file path (for schema if schema_sexp is NULL)
 * @return List of data frames (one per transcript)
 */
SEXP RC_vep_parse_record(SEXP csq_sexp, SEXP schema_sexp, SEXP filename_sexp) {
    if (TYPEOF(csq_sexp) != STRSXP || Rf_length(csq_sexp) != 1) {
        Rf_error("csq must be a single character string");
    }
    
    const char* csq_value = CHAR(STRING_ELT(csq_sexp, 0));
    
    // Get schema from file
    if (TYPEOF(filename_sexp) != STRSXP || Rf_length(filename_sexp) != 1) {
        Rf_error("filename must be provided");
    }
    
    const char* filename = CHAR(STRING_ELT(filename_sexp, 0));
    
    htsFile* fp = hts_open(filename, "r");
    if (!fp) {
        Rf_error("Failed to open file: %s", filename);
    }
    
    bcf_hdr_t* hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        Rf_error("Failed to read VCF/BCF header");
    }
    
    vep_schema_t* schema = vep_schema_parse(hdr, NULL);
    if (!schema) {
        bcf_hdr_destroy(hdr);
        hts_close(fp);
        Rf_error("No VEP annotation found");
    }
    
    // Parse record
    vep_record_t* record = vep_record_parse(schema, csq_value);
    
    if (!record) {
        vep_schema_destroy(schema);
        bcf_hdr_destroy(hdr);
        hts_close(fp);
        return R_NilValue;
    }
    
    // Create result - list of data frames (one per transcript)
    int n_transcripts = record->n_transcripts;
    int n_fields = schema->n_fields;
    
    SEXP result = PROTECT(Rf_allocVector(VECSXP, n_transcripts));
    
    for (int t = 0; t < n_transcripts; t++) {
        vep_transcript_t* transcript = &record->transcripts[t];
        
        // Create data frame for this transcript
        SEXP df = PROTECT(Rf_allocVector(VECSXP, n_fields));
        SEXP col_names = PROTECT(Rf_allocVector(STRSXP, n_fields));
        
        for (int f = 0; f < n_fields; f++) {
            vep_field_t* field = &schema->fields[f];
            vep_value_t* value = &transcript->values[f];
            
            SET_STRING_ELT(col_names, f, Rf_mkChar(field->name));
            
            // Create appropriate vector based on type
            SEXP col;
            if (value->is_missing) {
                // Return NA of appropriate type
                switch (field->type) {
                    case VEP_TYPE_INTEGER:
                        col = PROTECT(Rf_allocVector(INTSXP, 1));
                        INTEGER(col)[0] = NA_INTEGER;
                        break;
                    case VEP_TYPE_FLOAT:
                        col = PROTECT(Rf_allocVector(REALSXP, 1));
                        REAL(col)[0] = NA_REAL;
                        break;
                    default:
                        col = PROTECT(Rf_allocVector(STRSXP, 1));
                        SET_STRING_ELT(col, 0, NA_STRING);
                        break;
                }
            } else {
                switch (field->type) {
                    case VEP_TYPE_INTEGER:
                        col = PROTECT(Rf_allocVector(INTSXP, 1));
                        if (value->int_value == INT32_MIN) {
                            INTEGER(col)[0] = NA_INTEGER;
                        } else {
                            INTEGER(col)[0] = value->int_value;
                        }
                        break;
                    case VEP_TYPE_FLOAT:
                        col = PROTECT(Rf_allocVector(REALSXP, 1));
                        if (isnan(value->float_value)) {
                            REAL(col)[0] = NA_REAL;
                        } else {
                            REAL(col)[0] = value->float_value;
                        }
                        break;
                    default:
                        col = PROTECT(Rf_allocVector(STRSXP, 1));
                        SET_STRING_ELT(col, 0, Rf_mkChar(value->str_value ? value->str_value : ""));
                        break;
                }
            }
            
            SET_VECTOR_ELT(df, f, col);
            UNPROTECT(1);  // col
        }
        
        Rf_setAttrib(df, R_NamesSymbol, col_names);
        
        // Set row names for single-row data frame
        SEXP row_names = PROTECT(Rf_allocVector(INTSXP, 2));
        INTEGER(row_names)[0] = NA_INTEGER;
        INTEGER(row_names)[1] = -1;
        Rf_setAttrib(df, R_RowNamesSymbol, row_names);
        
        // Set class
        SEXP class_name = PROTECT(Rf_allocVector(STRSXP, 1));
        SET_STRING_ELT(class_name, 0, Rf_mkChar("data.frame"));
        Rf_setAttrib(df, R_ClassSymbol, class_name);
        
        SET_VECTOR_ELT(result, t, df);
        UNPROTECT(4);  // df, col_names, row_names, class_name
    }
    
    vep_record_destroy(record);
    vep_schema_destroy(schema);
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    UNPROTECT(1);
    return result;
}
