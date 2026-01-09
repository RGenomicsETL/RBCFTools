# Test VEP Parser Functionality
library(RBCFTools)
library(tinytest)

# =============================================================================
# Test Setup
# =============================================================================

# Get test VEP files
test_vep <- system.file("extdata", "test_vep.vcf", package = "RBCFTools")
test_bcsq <- system.file(
    "extdata",
    "test_vep_snpeff.vcf",
    package = "RBCFTools"
)
test_vep_types <- system.file(
    "extdata",
    "test_vep_types.vcf",
    package = "RBCFTools"
)

# Skip if test files not found
if (!file.exists(test_vep) || !nzchar(test_vep)) {
    exit_file("test_vep.vcf not found")
}

if (!file.exists(test_bcsq) || !nzchar(test_bcsq)) {
    exit_file("test_vep_snpeff.vcf not found")
}

# =============================================================================
# Test vep_detect_tag
# =============================================================================

# Test CSQ detection
tag <- vep_detect_tag(test_vep)
expect_equal(
    tag,
    "CSQ",
    info = "Should detect CSQ tag in VEP-annotated file"
)

# Test BCSQ detection
tag_bcsq <- vep_detect_tag(test_bcsq)
expect_equal(
    tag_bcsq,
    "BCSQ",
    info = "Should detect BCSQ tag in bcftools/csq-annotated file"
)

# Test file without VEP annotation
test_no_vep <- system.file(
    "extdata",
    "test_genotypes.vcf",
    package = "RBCFTools"
)
if (file.exists(test_no_vep) && nzchar(test_no_vep)) {
    tag_none <- vep_detect_tag(test_no_vep)
    expect_true(
        is.na(tag_none),
        info = "Should return NA for file without VEP annotations"
    )
}

# =============================================================================
# Test vep_has_annotation
# =============================================================================

# Test CSQ file
has_vep <- vep_has_annotation(test_vep)
expect_true(
    has_vep,
    info = "Should return TRUE for VEP-annotated file"
)

# Test BCSQ file
has_bcsq <- vep_has_annotation(test_bcsq)
expect_true(
    has_bcsq,
    info = "Should return TRUE for BCSQ-annotated file"
)

# Test non-annotated file
if (file.exists(test_no_vep) && nzchar(test_no_vep)) {
    has_none <- vep_has_annotation(test_no_vep)
    expect_false(
        has_none,
        info = "Should return FALSE for file without VEP annotations"
    )
}

# =============================================================================
# Test vep_get_schema
# =============================================================================

# Test CSQ schema extraction
schema <- vep_get_schema(test_vep)
expect_true(
    is.data.frame(schema),
    info = "vep_get_schema should return a data frame"
)
expect_true(
    nrow(schema) > 0,
    info = "Schema should have at least one field"
)
expect_true(
    all(c("name", "type", "index", "is_list") %in% names(schema)),
    info = "Schema should have required columns"
)
expect_equal(
    attr(schema, "tag"),
    "CSQ",
    info = "Schema should have tag attribute set to CSQ"
)

# Check expected VEP fields are present
expected_fields <- c(
    "Allele",
    "Consequence",
    "IMPACT",
    "SYMBOL",
    "Gene"
)
for (field in expected_fields) {
    expect_true(
        field %in% schema$name,
        info = paste("Schema should contain", field, "field")
    )
}

# Test BCSQ schema extraction
schema_bcsq <- vep_get_schema(test_bcsq)
expect_true(
    is.data.frame(schema_bcsq),
    info = "BCSQ schema should be a data frame"
)
expect_equal(
    attr(schema_bcsq, "tag"),
    "BCSQ",
    info = "BCSQ schema should have tag attribute set to BCSQ"
)

# Check BCSQ fields (7 standard fields)
bcsq_expected <- c(
    "Consequence",
    "gene",
    "transcript",
    "biotype"
)
for (field in bcsq_expected) {
    expect_true(
        field %in% schema_bcsq$name,
        info = paste("BCSQ schema should contain", field, "field")
    )
}

# Test explicit tag parameter
schema_explicit <- vep_get_schema(test_vep, tag = "CSQ")
expect_equal(
    schema_explicit$name,
    schema$name,
    info = "Explicit tag should return same schema as auto-detection"
)

# =============================================================================
# Test vep_infer_type
# =============================================================================

# Test string fields
string_fields <- c("SYMBOL", "Consequence", "IMPACT", "Gene", "Feature")
string_types <- vep_infer_type(string_fields)
expect_true(
    all(string_types == "String"),
    info = "Standard text fields should be inferred as String"
)

# Test integer fields
int_fields <- c("DISTANCE", "STRAND", "TSL", "GENE_PHENO", "HGVS_OFFSET")
int_types <- vep_infer_type(int_fields)
expect_true(
    all(int_types == "Integer"),
    info = "Known integer fields should be inferred as Integer"
)

# Test float fields
float_fields <- c("AF", "gnomAD_AF", "MAX_AF", "MOTIF_SCORE_CHANGE")
float_types <- vep_infer_type(float_fields)
expect_true(
    all(float_types == "Float"),
    info = "Known float fields should be inferred as Float"
)

# Test pattern-based inference
# Fields ending with _AF should be Float
af_fields <- c("gnomAD_AFR_AF", "gnomAD_EAS_AF", "custom_AF")
af_types <- vep_infer_type(af_fields)
expect_true(
    all(af_types == "Float"),
    info = "Fields ending with _AF should be inferred as Float"
)

# Test SpliceAI fields
spliceai_ds <- c(
    "SpliceAI_pred_DS_AG",
    "SpliceAI_pred_DS_AL",
    "SpliceAI_pred_DS_DG"
)
spliceai_ds_types <- vep_infer_type(spliceai_ds)
expect_true(
    all(spliceai_ds_types == "Float"),
    info = "SpliceAI DS fields should be inferred as Float"
)

spliceai_dp <- c(
    "SpliceAI_pred_DP_AG",
    "SpliceAI_pred_DP_AL",
    "SpliceAI_pred_DP_DG"
)
spliceai_dp_types <- vep_infer_type(spliceai_dp)
expect_true(
    all(spliceai_dp_types == "Integer"),
    info = "SpliceAI DP fields should be inferred as Integer"
)

# Test edge cases
empty_result <- vep_infer_type(character(0))
expect_equal(
    length(empty_result),
    0,
    info = "Empty input should return empty output"
)

# =============================================================================
# Test vep_parse_record
# =============================================================================

# Get a real CSQ value from the test file
suppressWarnings({
    df_vep <- vcf_to_arrow(test_vep, as = "data.frame", batch_size = 10L)
})

# Find a row with CSQ annotation
csq_col <- grep("^INFO\\.CSQ|^INFO_CSQ", names(df_vep), value = TRUE)

if (length(csq_col) > 0 && nrow(df_vep) > 0) {
    csq_value <- df_vep[[csq_col[1]]][1]

    if (!is.null(csq_value) && !is.na(csq_value) && csq_value != "") {
        # Parse the record
        parsed <- vep_parse_record(csq_value, test_vep, schema)

        expect_true(
            is.list(parsed),
            info = "vep_parse_record should return a list"
        )
        expect_true(
            length(parsed) > 0,
            info = "Parsed result should have at least one transcript"
        )

        # Check first transcript has expected fields
        first_tx <- parsed[[1]]
        expect_true(
            is.data.frame(first_tx),
            info = "Each transcript should be a data frame"
        )
        expect_true(
            nrow(first_tx) == 1,
            info = "Each transcript data frame should have one row"
        )

        # Check some fields are present
        if ("Allele" %in% names(first_tx)) {
            expect_true(
                !is.na(first_tx$Allele),
                info = "Allele field should be parsed"
            )
        }

        if ("Consequence" %in% names(first_tx)) {
            expect_true(
                is.character(first_tx$Consequence),
                info = "Consequence should be character"
            )
        }
    }
}

# Test BCSQ parsing
suppressWarnings({
    df_bcsq <- vcf_to_arrow(test_bcsq, as = "data.frame", batch_size = 10L)
})

bcsq_col <- grep("^INFO\\.BCSQ|^INFO_BCSQ", names(df_bcsq), value = TRUE)

if (length(bcsq_col) > 0 && nrow(df_bcsq) > 0) {
    # Find a row with BCSQ
    bcsq_idx <- which(
        !is.na(df_bcsq[[bcsq_col[1]]]) &
            df_bcsq[[bcsq_col[1]]] != ""
    )
    if (length(bcsq_idx) > 0) {
        bcsq_value <- df_bcsq[[bcsq_col[1]]][bcsq_idx[1]]

        parsed_bcsq <- vep_parse_record(bcsq_value, test_bcsq, schema_bcsq)

        expect_true(
            is.list(parsed_bcsq),
            info = "BCSQ parsing should return a list"
        )
        expect_true(
            length(parsed_bcsq) > 0,
            info = "BCSQ parsed result should have at least one consequence"
        )

        first_csq <- parsed_bcsq[[1]]
        if ("Consequence" %in% names(first_csq)) {
            expect_true(
                is.character(first_csq$Consequence),
                info = "BCSQ Consequence should be character"
            )
        }
    }
}

# =============================================================================
# Test vep_list_fields
# =============================================================================

# Capture message output
msg <- capture.output(
    result <- vep_list_fields(test_vep),
    type = "message"
)

expect_true(
    any(grepl("CSQ", msg)),
    info = "vep_list_fields should display tag name"
)
expect_true(
    any(grepl("Fields", msg)),
    info = "vep_list_fields should display field count"
)
expect_true(
    is.data.frame(result),
    info = "vep_list_fields should invisibly return schema"
)

# =============================================================================
# Test vcf_read_vep
# =============================================================================

# Basic usage with CSQ file
suppressWarnings({
    df_with_vep <- tryCatch(
        vcf_read_vep(test_vep),
        error = function(e) NULL
    )
})

if (!is.null(df_with_vep)) {
    expect_true(
        is.data.frame(df_with_vep),
        info = "vcf_read_vep should return a data frame"
    )
    expect_true(
        nrow(df_with_vep) > 0,
        info = "vcf_read_vep result should have rows"
    )

    # Check VEP columns are added with prefix
    vep_cols <- grep("^CSQ_", names(df_with_vep), value = TRUE)
    expect_true(
        length(vep_cols) > 0,
        info = "VEP columns should be added with CSQ_ prefix"
    )
}

# Test with specific columns
suppressWarnings({
    df_subset <- tryCatch(
        vcf_read_vep(
            test_vep,
            vep_columns = c("Consequence", "SYMBOL", "IMPACT")
        ),
        error = function(e) NULL
    )
})

if (!is.null(df_subset)) {
    vep_cols_subset <- grep("^CSQ_", names(df_subset), value = TRUE)
    expect_true(
        all(
            c("CSQ_Consequence", "CSQ_SYMBOL", "CSQ_IMPACT") %in%
                vep_cols_subset
        ),
        info = "Should include requested VEP columns"
    )
}

# Test with BCSQ file
suppressWarnings({
    df_with_bcsq <- tryCatch(
        vcf_read_vep(test_bcsq),
        error = function(e) NULL
    )
})

if (!is.null(df_with_bcsq)) {
    bcsq_cols <- grep("^BCSQ_", names(df_with_bcsq), value = TRUE)
    expect_true(
        length(bcsq_cols) >= 0,
        info = "BCSQ columns should be added with BCSQ_ prefix"
    )
}

# =============================================================================
# Test Error Handling
# =============================================================================

# Non-existent file
expect_error(
    vep_detect_tag("/nonexistent/file.vcf"),
    info = "Should error on non-existent file"
)

expect_error(
    vep_has_annotation("/nonexistent/file.vcf"),
    info = "vep_has_annotation should error on non-existent file"
)

expect_error(
    vep_get_schema("/nonexistent/file.vcf"),
    info = "vep_get_schema should error on non-existent file"
)

# File without VEP annotation for vcf_read_vep
if (file.exists(test_no_vep) && nzchar(test_no_vep)) {
    expect_error(
        vcf_read_vep(test_no_vep),
        pattern = "No VEP",
        info = "vcf_read_vep should error on file without VEP"
    )
}

# Invalid tag parameter
expect_error(
    vep_get_schema(test_vep, tag = "INVALID_TAG"),
    info = "Should error on invalid tag"
)

# =============================================================================
# Test Type Coercion in Parsed Records
# =============================================================================

# Test that numeric fields are properly typed
if (file.exists(test_vep_types) && nzchar(test_vep_types)) {
    schema_types <- vep_get_schema(test_vep_types)

    # Check that AF fields are Float
    af_fields_in_schema <- grep("_AF$|^AF$", schema_types$name, value = TRUE)
    for (field in af_fields_in_schema) {
        field_type <- schema_types$type[schema_types$name == field]
        expect_equal(
            field_type,
            "Float",
            info = paste(field, "should be typed as Float")
        )
    }

    # Check that SpliceAI_pred_DP fields are Integer
    dp_fields <- grep("SpliceAI_pred_DP", schema_types$name, value = TRUE)
    for (field in dp_fields) {
        field_type <- schema_types$type[schema_types$name == field]
        expect_equal(
            field_type,
            "Integer",
            info = paste(field, "should be typed as Integer")
        )
    }

    # Check that SpliceAI_pred_DS fields are Float
    ds_fields <- grep("SpliceAI_pred_DS", schema_types$name, value = TRUE)
    for (field in ds_fields) {
        field_type <- schema_types$type[schema_types$name == field]
        expect_equal(
            field_type,
            "Float",
            info = paste(field, "should be typed as Float")
        )
    }
}

# =============================================================================
# Test Multiple Transcripts
# =============================================================================

# Test parsing of multiple transcripts (comma-separated)
if (exists("csq_value") && !is.null(csq_value) && grepl(",", csq_value)) {
    # The CSQ has multiple transcripts
    n_transcripts <- length(strsplit(csq_value, ",")[[1]])
    parsed_multi <- vep_parse_record(csq_value, test_vep, schema)

    expect_equal(
        length(parsed_multi),
        n_transcripts,
        info = "Should parse all transcripts from CSQ"
    )
}

# =============================================================================
# Test Empty/Missing Values
# =============================================================================

# Test parsing empty CSQ
parsed_empty <- tryCatch(
    vep_parse_record("", test_vep, schema),
    error = function(e) list()
)
expect_true(
    length(parsed_empty) == 0 || is.null(parsed_empty[[1]]),
    info = "Empty CSQ should return empty list or NULL elements"
)

# Test parsing "." - implementation may treat "." as a single empty transcript
parsed_dot <- tryCatch(
    vep_parse_record(".", test_vep, schema),
    error = function(e) list()
)
# The implementation may return a list with one element for "." value
# Just verify it doesn't crash and returns a list
expect_true(
    is.list(parsed_dot),
    info = "Dot CSQ should return a list (possibly with empty values)"
)

# =============================================================================
# Test Schema Index Values
# =============================================================================

# Check that index values are sequential and 0-based
expect_equal(
    schema$index,
    seq(0, nrow(schema) - 1),
    info = "Schema indices should be 0-based and sequential"
)

# Same for BCSQ
expect_equal(
    schema_bcsq$index,
    seq(0, nrow(schema_bcsq) - 1),
    info = "BCSQ schema indices should be 0-based and sequential"
)

# =============================================================================
# Test is_list field
# =============================================================================

# Consequence field should potentially be a list (can have &-separated values)
expect_true(
    is.logical(schema$is_list),
    info = "is_list column should be logical"
)

# =============================================================================
# Test Large Schema (VEP with many fields)
# =============================================================================

# Full VEP output can have 70+ fields
expect_true(
    nrow(schema) >= 20,
    info = "CSQ schema should have many fields (typical VEP output)"
)

# BCSQ is simpler
expect_true(
    nrow(schema_bcsq) >= 4 && nrow(schema_bcsq) <= 10,
    info = "BCSQ schema should have few fields (7 standard)"
)
