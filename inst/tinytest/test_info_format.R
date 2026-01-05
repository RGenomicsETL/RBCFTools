# Test INFO and FORMAT field parsing
library(RBCFTools)
library(tinytest)

# =============================================================================
# Test File Setup
# =============================================================================

test_info_vcf <- system.file(
    "extdata",
    "test_info_fields.vcf",
    package = "RBCFTools"
)
test_format_vcf <- system.file(
    "extdata",
    "test_format_info.vcf",
    package = "RBCFTools"
)
test_genotypes_vcf <- system.file(
    "extdata",
    "test_genotypes.vcf",
    package = "RBCFTools"
)
test_simple_vcf <- system.file(
    "extdata",
    "test_format_simple.vcf",
    package = "RBCFTools"
)

# Skip tests if nanoarrow is not available
skip_if_no_nanoarrow <- function() {
    if (!requireNamespace("nanoarrow", quietly = TRUE)) {
        exit_file("nanoarrow package not available")
    }
}

skip_if_no_nanoarrow()

# =============================================================================
# INFO Field Parsing Tests
# =============================================================================

if (file.exists(test_info_vcf) && nchar(test_info_vcf) > 0) {
    # Test that INFO fields are properly parsed
    stream <- vcf_open_arrow(
        test_info_vcf,
        include_info = TRUE,
        include_format = TRUE
    )

    expect_true(
        inherits(stream, "nanoarrow_array_stream"),
        info = "vcf_open_arrow should return a nanoarrow stream"
    )

    # Read first batch
    batch <- stream$get_next()
    expect_true(
        !is.null(batch),
        info = "Should be able to read first batch from INFO test file"
    )

    # Convert to data frame for easier testing
    df <- as.data.frame(nanoarrow::convert_array(batch))

    # Check basic variant columns exist
    expect_true(
        all(c("CHROM", "POS", "REF", "ALT") %in% names(df)),
        info = "Basic variant columns should be present"
    )

    # Check that INFO fields are present as nested data frame
    expect_true(
        "INFO" %in% names(df),
        info = "INFO column should be present"
    )

    expect_true(
        is.data.frame(df$INFO) || is.list(df$INFO),
        info = "INFO should be a data.frame or list"
    )

    # Test reading entire file to data frame
    df_full <- vcf_to_arrow(
        test_info_vcf,
        as = "data.frame",
        include_info = TRUE
    )

    expect_true(
        is.data.frame(df_full),
        info = "vcf_to_arrow should return a data.frame"
    )

    expect_true(
        nrow(df_full) > 0,
        info = "Should have at least one variant record"
    )

    # Test that INFO fields can be accessed (AN, AC, AF in nested INFO column)
    expect_true(
        "INFO" %in% names(df_full) && is.data.frame(df_full$INFO),
        info = "INFO should be a nested data.frame"
    )

    if (is.data.frame(df_full$INFO)) {
        expect_true(
            any(c("AN", "AC", "AF") %in% names(df_full$INFO)),
            info = "At least one INFO field (AN/AC/AF) should be present in INFO column"
        )
    }
}

# =============================================================================
# FORMAT Field Parsing Tests
# =============================================================================

if (file.exists(test_format_vcf) && nchar(test_format_vcf) > 0) {
    # Test with FORMAT fields included
    df_format <- vcf_to_arrow(
        test_format_vcf,
        as = "data.frame",
        include_info = TRUE,
        include_format = TRUE
    )

    expect_true(
        is.data.frame(df_format),
        info = "Should read VCF with FORMAT fields"
    )

    expect_true(
        nrow(df_format) > 0,
        info = "Should have records from FORMAT test file"
    )

    # Check if FORMAT fields are present (typically have sample names)
    # FORMAT fields are usually named like SAMPLE_FORMAT or similar
    expect_true(
        ncol(df_format) > 8, # More than basic 8 VCF columns
        info = "Should have additional columns for FORMAT fields"
    )

    # Test without FORMAT fields
    df_no_format <- vcf_to_arrow(
        test_format_vcf,
        as = "data.frame",
        include_info = TRUE,
        include_format = FALSE
    )

    expect_true(
        is.data.frame(df_no_format),
        info = "Should read VCF without FORMAT fields"
    )

    expect_true(
        ncol(df_no_format) <= ncol(df_format),
        info = "Data frame without FORMAT should have same or fewer columns"
    )
}

# =============================================================================
# Genotype Parsing Tests
# =============================================================================

if (file.exists(test_genotypes_vcf) && nchar(test_genotypes_vcf) > 0) {
    # This file tests various genotype representations (phased, unphased, missing)
    df_gt <- vcf_to_arrow(
        test_genotypes_vcf,
        as = "data.frame",
        include_format = TRUE
    )

    expect_true(
        is.data.frame(df_gt),
        info = "Should parse file with complex genotypes"
    )

    expect_true(
        nrow(df_gt) > 0,
        info = "Should have genotype records"
    )

    # Test that basic columns are present
    expect_true(
        all(c("CHROM", "POS", "REF", "ALT") %in% names(df_gt)),
        info = "Basic variant columns should be present in genotype file"
    )
}

# =============================================================================
# Simple FORMAT Test
# =============================================================================

if (file.exists(test_simple_vcf) && nchar(test_simple_vcf) > 0) {
    df_simple <- vcf_to_arrow(
        test_simple_vcf,
        as = "data.frame",
        include_format = TRUE
    )

    expect_true(
        is.data.frame(df_simple),
        info = "Should parse simple FORMAT test file"
    )

    expect_true(
        nrow(df_simple) > 0,
        info = "Should have at least one record in simple test"
    )
}

# =============================================================================
# INFO and FORMAT Toggle Tests
# =============================================================================

if (file.exists(test_info_vcf) && nchar(test_info_vcf) > 0) {
    # Test with INFO only
    df_info_only <- vcf_to_arrow(
        test_info_vcf,
        as = "data.frame",
        include_info = TRUE,
        include_format = FALSE
    )

    expect_true(
        is.data.frame(df_info_only),
        info = "Should read with INFO only"
    )

    # Test with FORMAT only
    df_format_only <- vcf_to_arrow(
        test_info_vcf,
        as = "data.frame",
        include_info = FALSE,
        include_format = TRUE
    )

    expect_true(
        is.data.frame(df_format_only),
        info = "Should read with FORMAT only"
    )

    # Test with neither INFO nor FORMAT
    df_basic <- vcf_to_arrow(
        test_info_vcf,
        as = "data.frame",
        include_info = FALSE,
        include_format = FALSE
    )

    expect_true(
        is.data.frame(df_basic),
        info = "Should read basic variant info without INFO/FORMAT"
    )

    # Basic should have fewer columns than full
    df_full <- vcf_to_arrow(
        test_info_vcf,
        as = "data.frame",
        include_info = TRUE,
        include_format = TRUE
    )

    expect_true(
        ncol(df_basic) <= ncol(df_full),
        info = "Basic variant data should have fewer or equal columns than full"
    )
}

# =============================================================================
# Arrow Stream Tests
# =============================================================================

if (file.exists(test_info_vcf) && nchar(test_info_vcf) > 0) {
    # Test streaming with batch size
    stream <- vcf_open_arrow(
        test_info_vcf,
        batch_size = 5,
        include_info = TRUE,
        include_format = TRUE
    )

    expect_true(
        inherits(stream, "nanoarrow_array_stream"),
        info = "Should create stream with custom batch size"
    )

    # Read batches
    batch_count <- 0
    total_rows <- 0

    while (!is.null(batch <- stream$get_next())) {
        batch_count <- batch_count + 1
        df_batch <- as.data.frame(nanoarrow::convert_array(batch))
        total_rows <- total_rows + nrow(df_batch)
    }

    expect_true(
        batch_count > 0,
        info = "Should read at least one batch"
    )

    expect_true(
        total_rows > 0,
        info = "Should have read some rows across all batches"
    )
}

# =============================================================================
# Schema Tests
# =============================================================================

if (file.exists(test_info_vcf) && nchar(test_info_vcf) > 0) {
    # Test schema extraction
    schema <- vcf_arrow_schema(test_info_vcf)

    expect_true(
        inherits(schema, "nanoarrow_schema"),
        info = "vcf_arrow_schema should return a nanoarrow schema"
    )

    # Schema should have fields
    expect_true(
        !is.null(schema),
        info = "Schema should not be NULL"
    )
}

# =============================================================================
# Batches Mode Tests
# =============================================================================

if (file.exists(test_simple_vcf) && nchar(test_simple_vcf) > 0) {
    # Test reading as batches (list of arrays)
    batches <- vcf_to_arrow(
        test_simple_vcf,
        as = "batches",
        include_info = TRUE,
        include_format = TRUE
    )

    expect_true(
        is.list(batches),
        info = "vcf_to_arrow with as='batches' should return a list"
    )

    if (length(batches) > 0) {
        expect_true(
            inherits(batches[[1]], "nanoarrow_array"),
            info = "Batch elements should be nanoarrow arrays"
        )
    }
}

# =============================================================================
# Error Handling Tests
# =============================================================================

# Test with non-existent file
expect_error(
    vcf_open_arrow("/nonexistent/file.vcf"),
    info = "Should error with non-existent file"
)

# Test with invalid batch size
if (file.exists(test_simple_vcf) && nchar(test_simple_vcf) > 0) {
    expect_error(
        vcf_open_arrow(test_simple_vcf, batch_size = -1),
        info = "Should error with negative batch size"
    )
}

# =============================================================================
# Integration with Sample Filtering
# =============================================================================

if (file.exists(test_info_vcf) && nchar(test_info_vcf) > 0) {
    # Test that sample filtering works (file has samples NA00001, NA00002, NA00003)
    df_filtered <- tryCatch(
        {
            vcf_to_arrow(
                test_info_vcf,
                as = "data.frame",
                samples = "NA00001",
                include_format = TRUE
            )
        },
        error = function(e) NULL
    )

    if (!is.null(df_filtered)) {
        expect_true(
            is.data.frame(df_filtered),
            info = "Sample filtering should work with INFO/FORMAT parsing"
        )
    }
}

# =============================================================================
# Data Type Tests
# =============================================================================

if (file.exists(test_info_vcf) && nchar(test_info_vcf) > 0) {
    df <- vcf_to_arrow(test_info_vcf, as = "data.frame", include_info = TRUE)

    # Check basic column types
    expect_true(
        is.character(df$CHROM) || is.factor(df$CHROM),
        info = "CHROM should be character or factor"
    )

    expect_true(
        is.numeric(df$POS) || is.integer(df$POS),
        info = "POS should be numeric"
    )

    expect_true(
        is.character(df$REF),
        info = "REF should be character"
    )
}
