# VEP/SnpEff/BCSQ Annotation Parser
#
# Functions for parsing structured annotation fields (CSQ, BCSQ, ANN)
# from VCF files with proper type inference.
#
# @name vep_parser
# @rdname vep_parser
NULL

# =============================================================================
# Detection and Schema Functions
# =============================================================================

#' Detect VEP annotation tag in VCF file
#'
#' Checks for the presence of CSQ, BCSQ, or ANN annotation tags in the VCF
#' header and returns the first one found.
#'
#' @param filename Path to VCF/BCF file
#' @return Character string with tag name ("CSQ", "BCSQ", or "ANN"),
#'   or NA if no annotation found
#'
#' @examples
#' \dontrun{
#' vep_detect_tag("annotated.vcf.gz")  # Returns "CSQ"
#' }
#'
#' @export
vep_detect_tag <- function(filename) {
    filename <- normalizePath(filename, mustWork = TRUE)
    .Call(RC_vep_detect_tag, filename, PACKAGE = "RBCFTools")
}

#' Check if VCF has VEP-style annotations
#'
#' @param filename Path to VCF/BCF file
#' @return Logical indicating presence of CSQ, BCSQ, or ANN
#'
#' @examples
#' \dontrun{
#' if (vep_has_annotation("file.vcf.gz")) {
#'   schema <- vep_get_schema("file.vcf.gz")
#' }
#' }
#'
#' @export
vep_has_annotation <- function(filename) {
    filename <- normalizePath(filename, mustWork = TRUE)
    .Call(RC_vep_has_annotation, filename, PACKAGE = "RBCFTools")
}

#' Get VEP annotation schema from VCF header
#'
#' Parses the VEP/BCSQ/ANN header to extract field names and inferred types.
#' Types are inferred using bcftools split-vep conventions.
#'
#' @param filename Path to VCF/BCF file
#' @param tag Optional annotation tag ("CSQ", "BCSQ", "ANN").
#'   If NULL (default), auto-detects.
#'
#' @return Data frame with columns:
#'   \describe{
#'     \item{name}{Field name (e.g., "Consequence", "SYMBOL", "AF")}
#'     \item{type}{Inferred type ("Integer", "Float", "String")}
#'     \item{index}{Position in pipe-delimited string (0-based)}
#'     \item{is_list}{Whether field can have multiple values}
#'   }
#'   The tag name is stored as an attribute.
#'
#' @examples
#' \dontrun{
#' schema <- vep_get_schema("vep_annotated.vcf.gz")
#' print(schema)
#' #       name    type index is_list
#' # 1   Allele  String     0   FALSE
#' # 2   Consequence String  1    TRUE
#' # 3   IMPACT  String     2   FALSE
#' # ...
#' attr(schema, "tag")  # "CSQ"
#' }
#'
#' @export
vep_get_schema <- function(filename, tag = NULL) {
    filename <- normalizePath(filename, mustWork = TRUE)
    .Call(RC_vep_get_schema, filename, tag, PACKAGE = "RBCFTools")
}

#' Infer type from VEP field name
#'
#' Uses bcftools split-vep conventions to infer the type of a VEP field
#' from its name.
#'
#' @param field_name Character vector of field names
#' @return Character vector of inferred types ("Integer", "Float", "String")
#'
#' @details
#' Known integer fields: DISTANCE, STRAND, TSL, GENE_PHENO, HGVS_OFFSET,
#' MOTIF_POS, existing_*ORFs, SpliceAI_pred_DP_*
#'
#' Known float fields: AF, *_AF (e.g., gnomAD_AF), MAX_AF_*,
#' MOTIF_SCORE_CHANGE, SpliceAI_pred_DS_*
#'
#' All others default to String.
#'
#' @examples
#' vep_infer_type(c("SYMBOL", "AF", "gnomAD_AF", "DISTANCE", "SpliceAI_pred_DS_AG"))
#' # [1] "String" "Float" "Float" "Integer" "Float"
#'
#' @export
vep_infer_type <- function(field_name) {
    .Call(RC_vep_infer_type, as.character(field_name), PACKAGE = "RBCFTools")
}

# =============================================================================
# Record Parsing Functions
# =============================================================================

#' Parse VEP annotation string
#'
#' Parses a CSQ/BCSQ/ANN annotation string into a structured list of
#' data frames, one per transcript/consequence.
#'
#' @param csq_value Raw annotation string (pipe-delimited, comma-separated
#'   for multiple transcripts)
#' @param filename Path to VCF file (for schema extraction)
#' @param schema Optional pre-parsed schema from \code{vep_get_schema()}.
#'   If NULL, extracted from filename.
#'
#' @return List of data frames, one per transcript. Each data frame has
#'   one row with columns corresponding to annotation fields, properly typed.
#'
#' @examples
#' \dontrun{
#' # Get a CSQ value from a VCF
#' csq <- "A|missense_variant|MODERATE|BRCA1|..."
#' result <- vep_parse_record(csq, "annotated.vcf.gz")
#' result[[1]]$Consequence  # "missense_variant"
#' result[[1]]$AF           # 0.001 (numeric)
#' }
#'
#' @export
vep_parse_record <- function(csq_value, filename, schema = NULL) {
    filename <- normalizePath(filename, mustWork = TRUE)
    .Call(
        RC_vep_parse_record,
        as.character(csq_value)[1],
        schema,
        filename,
        PACKAGE = "RBCFTools"
    )
}

# =============================================================================
# High-Level Convenience Functions
# =============================================================================

#' Read VCF with parsed VEP annotations
#'
#' Opens a VCF file and parses VEP/BCSQ/ANN annotations into structured
#' columns. This is a convenience wrapper around \code{vcf_open_arrow}
#' with VEP parsing enabled.
#'
#' @param filename Path to VCF/BCF file
#' @param vep_tag Annotation tag to parse ("CSQ", "BCSQ", "ANN") or NULL
#'   for auto-detection
#' @param vep_columns Character vector of VEP fields to extract, or NULL
#'   for all fields
#' @param ... Additional arguments passed to \code{vcf_to_arrow}
#'
#' @return Data frame with VCF columns plus parsed VEP fields as separate
#'   columns prefixed with the tag name (e.g., "CSQ_Consequence",
#'   "CSQ_SYMBOL", etc.)
#'
#' @examples
#' \dontrun{
#' df <- vcf_read_vep("annotated.vcf.gz",
#'   vep_columns = c("Consequence", "SYMBOL", "AF", "gnomAD_AF")
#' )
#'
#' # Filter by gnomAD frequency
#' rare <- df[!is.na(df$CSQ_gnomAD_AF) & df$CSQ_gnomAD_AF < 0.001, ]
#' }
#'
#' @export
vcf_read_vep <- function(
    filename,
    vep_tag = NULL,
    vep_columns = NULL,
    ...
) {
    filename <- normalizePath(filename, mustWork = TRUE)

    # Check for VEP annotation
    if (!vep_has_annotation(filename)) {
        stop("No VEP/BCSQ/ANN annotation found in VCF header")
    }

    # Get schema
    schema <- vep_get_schema(filename, vep_tag)
    tag <- attr(schema, "tag")

    # Get base VCF data
    df <- vcf_to_arrow(filename, as = "data.frame", ...)

    # Parse VEP annotations for each row
    if (nrow(df) == 0) {
        return(df)
    }

    # Get the INFO field containing annotations
    info_col_name <- paste0("INFO.", tag)

    # Check if INFO is nested or flat
    if (info_col_name %in% names(df)) {
        csq_values <- df[[info_col_name]]
    } else if ("INFO" %in% names(df) && is.list(df$INFO)) {
        # Try nested INFO structure
        csq_values <- sapply(df$INFO, function(x) {
            if (is.list(x) && tag %in% names(x)) {
                x[[tag]]
            } else {
                NA_character_
            }
        })
    } else {
        message(
            "VEP annotation column not found in data. Returning base VCF data."
        )
        return(df)
    }

    # Parse each CSQ value
    parsed_list <- lapply(seq_along(csq_values), function(i) {
        csq <- csq_values[i]
        if (is.na(csq) || csq == "" || csq == ".") {
            return(NULL)
        }
        tryCatch(
            {
                result <- vep_parse_record(csq, filename, schema)
                if (length(result) > 0) {
                    # Take first transcript (or could aggregate)
                    result[[1]]
                } else {
                    NULL
                }
            },
            error = function(e) {
                NULL
            }
        )
    })

    # Filter columns if requested
    if (!is.null(vep_columns)) {
        valid_cols <- intersect(vep_columns, schema$name)
        if (length(valid_cols) == 0) {
            warning("None of the requested VEP columns found in schema")
            return(df)
        }
        vep_columns <- valid_cols
    } else {
        vep_columns <- schema$name
    }

    # Build VEP columns
    for (col_name in vep_columns) {
        new_col_name <- paste0(tag, "_", col_name)
        col_type <- schema$type[schema$name == col_name]

        # Extract values from parsed list
        values <- sapply(parsed_list, function(x) {
            if (is.null(x) || !(col_name %in% names(x))) {
                return(NA)
            }
            x[[col_name]]
        })

        # Coerce to appropriate type
        if (col_type == "Integer") {
            df[[new_col_name]] <- as.integer(values)
        } else if (col_type == "Float") {
            df[[new_col_name]] <- as.numeric(values)
        } else {
            df[[new_col_name]] <- as.character(values)
        }
    }

    df
}

#' List VEP annotation fields in a VCF file
#'
#' Convenience function to display available VEP fields and their types.
#'
#' @param filename Path to VCF/BCF file
#' @return Invisibly returns the schema data frame
#'
#' @examples
#' \dontrun{
#' vep_list_fields("annotated.vcf.gz")
#' # VEP Annotation Tag: CSQ
#' # Fields (78 total):
#' #   1. Allele (String)
#' #   2. Consequence (String, list)
#' #   3. IMPACT (String)
#' #   ...
#' }
#'
#' @export
vep_list_fields <- function(filename) {
    filename <- normalizePath(filename, mustWork = TRUE)

    if (!vep_has_annotation(filename)) {
        message("No VEP/BCSQ/ANN annotation found in file")
        return(invisible(NULL))
    }

    schema <- vep_get_schema(filename)
    tag <- attr(schema, "tag")

    message(sprintf("VEP Annotation Tag: %s", tag))
    message(sprintf("Fields (%d total):", nrow(schema)))

    for (i in seq_len(nrow(schema))) {
        list_marker <- if (schema$is_list[i]) ", list" else ""
        message(sprintf(
            "  %d. %s (%s%s)",
            i,
            schema$name[i],
            schema$type[i],
            list_marker
        ))
    }

    invisible(schema)
}
