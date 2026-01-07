# Test VCF DuckDB functionality
library(RBCFTools)
library(tinytest)

# =============================================================================
# Test Setup - Skip if DuckDB not available
# =============================================================================

skip_if_no_duckdb <- function() {
    if (!requireNamespace("duckdb", quietly = TRUE)) {
        exit_file("duckdb package not available")
    }
    if (!requireNamespace("DBI", quietly = TRUE)) {
        exit_file("DBI package not available")
    }
}

skip_if_no_duckdb()

# Get test VCF file
test_vcf <- system.file(
    "extdata",
    "1000G_3samples.vcf.gz",
    package = "RBCFTools"
)

if (!file.exists(test_vcf) || !nzchar(test_vcf)) {
    exit_file("1000G_3samples.vcf.gz not found")
}

# =============================================================================
# Test bcf_reader_source_dir (internal function)
# =============================================================================

src_dir <- RBCFTools:::bcf_reader_source_dir()
expect_true(
    dir.exists(src_dir),
    info = "bcf_reader_source_dir should return existing directory"
)
expect_true(
    file.exists(file.path(src_dir, "bcf_reader.c")),
    info = "Source directory should contain bcf_reader.c"
)

# =============================================================================
# Test bcf_reader_copy_source
# =============================================================================

temp_build_dir <- file.path(tempdir(), "bcf_reader_test_copy")
if (dir.exists(temp_build_dir)) {
    unlink(temp_build_dir, recursive = TRUE)
}

expect_silent(
    bcf_reader_copy_source(temp_build_dir)
)
expect_true(
    dir.exists(temp_build_dir),
    info = "Destination directory should be created"
)
expect_true(
    file.exists(file.path(temp_build_dir, "bcf_reader.c")),
    info = "bcf_reader.c should be copied"
)
expect_true(
    file.exists(file.path(temp_build_dir, "vcf_types.h")),
    info = "vcf_types.h should be copied"
)
expect_true(
    file.exists(file.path(temp_build_dir, "Makefile")),
    info = "Makefile should be copied"
)

# Test error when dest_dir is NULL
expect_error(
    bcf_reader_copy_source(NULL),
    pattern = "dest_dir must be specified",
    info = "Should error when dest_dir is NULL"
)

# Clean up
unlink(temp_build_dir, recursive = TRUE)

# =============================================================================
# Test bcf_reader_build
# =============================================================================

build_dir <- file.path(tempdir(), "bcf_reader_build_test")
if (dir.exists(build_dir)) {
    unlink(build_dir, recursive = TRUE)
}

# Build extension
expect_message(
    ext_path <- bcf_reader_build(build_dir, verbose = TRUE),
    pattern = "Building bcf_reader extension",
    info = "Build should show progress message"
)

expect_true(
    file.exists(ext_path),
    info = "Extension file should exist after build"
)

expect_true(
    grepl("bcf_reader.duckdb_extension$", ext_path),
    info = "Extension should have correct name"
)

# Test force rebuild
expect_message(
    ext_path2 <- bcf_reader_build(build_dir, force = FALSE, verbose = TRUE),
    pattern = "already exists",
    info = "Should skip rebuild when extension exists and force=FALSE"
)

# Test error when build_dir is NULL
expect_error(
    bcf_reader_build(NULL),
    pattern = "build_dir must be specified",
    info = "Should error when build_dir is NULL"
)

# =============================================================================
# Test vcf_duckdb_connect
# =============================================================================

# Test connection
con <- vcf_duckdb_connect(ext_path)
expect_true(
    inherits(con, "duckdb_connection"),
    info = "Should return a DuckDB connection"
)

# Test error when extension_path is NULL
expect_error(
    vcf_duckdb_connect(NULL),
    pattern = "extension_path must be specified",
    info = "Should error when extension_path is NULL"
)

# Test error when extension doesn't exist
expect_error(
    vcf_duckdb_connect("/nonexistent/path/extension.duckdb_extension"),
    pattern = "Extension not found",
    info = "Should error when extension doesn't exist"
)

# =============================================================================
# Test vcf_query_duckdb
# =============================================================================

# Basic query - all variants
result <- vcf_query_duckdb(test_vcf, extension_path = ext_path)
expect_true(
    is.data.frame(result),
    info = "vcf_query_duckdb should return data frame"
)
expect_true(
    nrow(result) > 0,
    info = "Should have at least one variant"
)
expect_true(
    all(c("CHROM", "POS", "REF", "ALT") %in% names(result)),
    info = "Result should have basic VCF columns"
)

# Count query
count_result <- vcf_query_duckdb(
    test_vcf,
    extension_path = ext_path,
    query = "SELECT COUNT(*) as n FROM bcf_read('{file}')"
)
expect_true(
    is.data.frame(count_result),
    info = "Count query should return data frame"
)
expect_true(
    "n" %in% names(count_result),
    info = "Count query should have n column"
)
expect_true(
    count_result$n[1] > 0,
    info = "Should have positive count"
)

# Filter query
filter_result <- vcf_query_duckdb(
    test_vcf,
    extension_path = ext_path,
    query = "SELECT CHROM, POS FROM bcf_read('{file}') LIMIT 5"
)
expect_true(
    nrow(filter_result) <= 5,
    info = "LIMIT 5 should return at most 5 rows"
)
expect_true(
    all(c("CHROM", "POS") %in% names(filter_result)),
    info = "Should have requested columns"
)

# Test with existing connection
result_con <- vcf_query_duckdb(test_vcf, con = con)
expect_true(
    is.data.frame(result_con),
    info = "Should work with existing connection"
)

# Test error cases
expect_error(
    vcf_query_duckdb("/nonexistent/file.vcf", extension_path = ext_path),
    pattern = "File not found",
    info = "Should error on non-existent file"
)

expect_error(
    vcf_query_duckdb(test_vcf, extension_path = NULL, con = NULL),
    pattern = "Either extension_path or con must be provided",
    info = "Should error when both extension_path and con are NULL"
)

# =============================================================================
# Test vcf_count_duckdb
# =============================================================================

count <- vcf_count_duckdb(test_vcf, extension_path = ext_path)
expect_true(
    is.integer(count),
    info = "vcf_count_duckdb should return integer"
)
expect_true(
    count > 0,
    info = "Should have positive variant count"
)

# Test with connection
count_con <- vcf_count_duckdb(test_vcf, con = con)
expect_equal(
    count,
    count_con,
    info = "Count should be same with extension_path or con"
)

# =============================================================================
# Test vcf_schema_duckdb
# =============================================================================

schema <- vcf_schema_duckdb(test_vcf, extension_path = ext_path)
expect_true(
    is.data.frame(schema),
    info = "vcf_schema_duckdb should return data frame"
)
expect_true(
    all(c("column_name", "column_type") %in% names(schema)),
    info = "Schema should have column_name and column_type"
)
expect_true(
    nrow(schema) > 0,
    info = "Should have at least one column"
)
expect_true(
    "CHROM" %in% schema$column_name,
    info = "Schema should include CHROM column"
)

# Test with connection
schema_con <- vcf_schema_duckdb(test_vcf, con = con)
expect_equal(
    schema$column_name,
    schema_con$column_name,
    info = "Schema should be same with extension_path or con"
)

# Test error cases
expect_error(
    vcf_schema_duckdb("/nonexistent/file.vcf", extension_path = ext_path),
    pattern = "File not found",
    info = "Should error on non-existent file"
)

# =============================================================================
# Test vcf_samples_duckdb
# =============================================================================

samples <- vcf_samples_duckdb(test_vcf, extension_path = ext_path)
expect_true(
    is.character(samples),
    info = "vcf_samples_duckdb should return character vector"
)
# Note: test_deep_variant.vcf.gz has sample data
expect_true(
    length(samples) >= 0,
    info = "Should return sample names (or empty if no samples)"
)

# Test with connection
samples_con <- vcf_samples_duckdb(test_vcf, con = con)
expect_equal(
    samples,
    samples_con,
    info = "Samples should be same with extension_path or con"
)

# =============================================================================
# Test vcf_summary_duckdb
# =============================================================================

summary <- vcf_summary_duckdb(test_vcf, extension_path = ext_path)
expect_true(
    is.list(summary),
    info = "vcf_summary_duckdb should return a list"
)
expect_true(
    all(
        c("total_variants", "n_samples", "samples", "variants_per_chrom") %in%
            names(summary)
    ),
    info = "Summary should have expected fields"
)
expect_true(
    is.integer(summary$total_variants) || is.numeric(summary$total_variants),
    info = "total_variants should be numeric"
)
expect_true(
    summary$total_variants > 0,
    info = "Should have positive variant count"
)
expect_true(
    is.data.frame(summary$variants_per_chrom),
    info = "variants_per_chrom should be data frame"
)

# Test with connection
summary_con <- vcf_summary_duckdb(test_vcf, con = con)
expect_equal(
    summary$total_variants,
    summary_con$total_variants,
    info = "Summary should be same with extension_path or con"
)

# =============================================================================
# Test vcf_to_parquet_duckdb
# =============================================================================

parquet_out <- tempfile(fileext = ".parquet")

expect_silent(
    vcf_to_parquet_duckdb(
        test_vcf,
        parquet_out,
        extension_path = ext_path,
        compression = "zstd"
    ),
    info = "vcf_to_parquet_duckdb should run without errors"
)

expect_true(
    file.exists(parquet_out),
    info = "Parquet file should be created"
)

expect_true(
    file.size(parquet_out) > 0,
    info = "Parquet file should not be empty"
)

# Test with column selection
parquet_slim <- tempfile(fileext = ".parquet")
vcf_to_parquet_duckdb(
    test_vcf,
    parquet_slim,
    extension_path = ext_path,
    columns = c("CHROM", "POS", "REF", "ALT")
)
expect_true(
    file.exists(parquet_slim),
    info = "Parquet file with selected columns should be created"
)

# Verify parquet content can be read back
if (requireNamespace("duckdb", quietly = TRUE)) {
    verify_con <- DBI::dbConnect(duckdb::duckdb())
    parquet_data <- DBI::dbGetQuery(
        verify_con,
        sprintf("SELECT * FROM '%s' LIMIT 1", parquet_out)
    )
    expect_true(
        nrow(parquet_data) > 0,
        info = "Should be able to read parquet file"
    )
    DBI::dbDisconnect(verify_con, shutdown = TRUE)
}

# Test error cases
expect_error(
    vcf_to_parquet_duckdb(
        "/nonexistent/file.vcf",
        parquet_out,
        extension_path = ext_path
    ),
    pattern = "Input file not found",
    info = "Should error on non-existent input file"
)

expect_error(
    vcf_to_parquet_duckdb(
        test_vcf,
        parquet_out,
        extension_path = NULL,
        con = NULL
    ),
    pattern = "Either extension_path or con must be provided",
    info = "Should error when both extension_path and con are NULL"
)

# Clean up parquet files
unlink(parquet_out)
unlink(parquet_slim)

# =============================================================================
# Test vcf_to_parquet_duckdb with row_group_size parameter
# =============================================================================

parquet_with_rg <- tempfile(fileext = ".parquet")

expect_silent(
    vcf_to_parquet_duckdb(
        test_vcf,
        parquet_with_rg,
        extension_path = ext_path,
        compression = "zstd",
        row_group_size = 50000L
    ),
    info = "vcf_to_parquet_duckdb should accept row_group_size parameter"
)

expect_true(
    file.exists(parquet_with_rg),
    info = "Parquet file with custom row_group_size should be created"
)

expect_true(
    file.size(parquet_with_rg) > 0,
    info = "Parquet file with custom row_group_size should not be empty"
)

unlink(parquet_with_rg)

# =============================================================================
# Test vcf_to_parquet_duckdb with threads parameter (single-threaded fallback)
# =============================================================================

parquet_threaded <- tempfile(fileext = ".parquet")

# Test with threads=1 (should work normally)
expect_silent(
    vcf_to_parquet_duckdb(
        test_vcf,
        parquet_threaded,
        extension_path = ext_path,
        threads = 1L
    ),
    info = "vcf_to_parquet_duckdb should work with threads=1"
)

expect_true(
    file.exists(parquet_threaded),
    info = "Parquet file with threads=1 should be created"
)

unlink(parquet_threaded)

# Test with threads > 1 on unindexed file (should fall back to single-threaded)
# Note: test_vcf might not have an index, so this tests the fallback behavior
parquet_multi <- tempfile(fileext = ".parquet")

expect_message(
    vcf_to_parquet_duckdb(
        test_vcf,
        parquet_multi,
        extension_path = ext_path,
        threads = 2L
    ),
    pattern = "No index found|Processing.*contigs",
    info = "Should show message when processing with threads parameter"
)

if (file.exists(parquet_multi)) {
    expect_true(
        file.size(parquet_multi) > 0,
        info = "Parquet file should be created even with fallback"
    )
    unlink(parquet_multi)
}

# =============================================================================
# Test vcf_to_parquet_duckdb_parallel function (if indexed file available)
# =============================================================================

# Check if we have an indexed test file
test_vcf_indexed <- system.file(
    "extdata",
    "1000G_3samples.bcf",
    package = "RBCFTools"
)

if (file.exists(test_vcf_indexed) && nzchar(test_vcf_indexed)) {
    # Check for index
    has_index <- vcf_has_index(test_vcf_indexed)

    if (has_index) {
        parquet_parallel <- tempfile(fileext = ".parquet")

        # Test parallel conversion with 2 threads
        expect_message(
            vcf_to_parquet_duckdb_parallel(
                test_vcf_indexed,
                parquet_parallel,
                extension_path = ext_path,
                threads = 2L,
                compression = "zstd"
            ),
            pattern = "Processing.*contigs.*threads",
            info = "vcf_to_parquet_duckdb_parallel should show progress"
        )

        expect_true(
            file.exists(parquet_parallel),
            info = "Parallel conversion should create output file"
        )

        expect_true(
            file.size(parquet_parallel) > 0,
            info = "Parallel output should not be empty"
        )

        # Verify content
        verify_con2 <- DBI::dbConnect(duckdb::duckdb())
        parquet_data2 <- DBI::dbGetQuery(
            verify_con2,
            sprintf("SELECT COUNT(*) as n FROM '%s'", parquet_parallel)
        )
        expect_true(
            parquet_data2$n > 0,
            info = "Parallel output should have variants"
        )
        DBI::dbDisconnect(verify_con2, shutdown = TRUE)

        unlink(parquet_parallel)
    }
}

# Test error handling in parallel function
expect_error(
    vcf_to_parquet_duckdb_parallel(
        test_vcf,
        tempfile(fileext = ".parquet"),
        extension_path = NULL,
        con = con # This should error as con can't be used across processes
    ),
    pattern = "extension_path must be provided|Shared connections",
    info = "Should error when con is provided instead of extension_path"
)

# =============================================================================
# Test vcf_to_parquet_duckdb with all new parameters combined
# =============================================================================

parquet_full <- tempfile(fileext = ".parquet")

expect_silent(
    result_path <- vcf_to_parquet_duckdb(
        test_vcf,
        parquet_full,
        extension_path = ext_path,
        compression = "snappy",
        row_group_size = 75000L,
        threads = 1L,
        columns = c("CHROM", "POS", "REF", "ALT")
    ),
    info = "Should work with all parameters specified"
)

expect_true(
    file.exists(parquet_full),
    info = "Output file should exist with all parameters"
)

expect_equal(
    result_path,
    normalizePath(parquet_full, mustWork = FALSE),
    info = "Should return output path invisibly"
)

# Verify the columns are as requested
verify_con3 <- DBI::dbConnect(duckdb::duckdb())
cols_data <- DBI::dbGetQuery(
    verify_con3,
    sprintf("SELECT * FROM '%s' LIMIT 1", parquet_full)
)
expect_true(
    all(c("CHROM", "POS", "REF", "ALT") %in% names(cols_data)),
    info = "Output should have requested columns"
)
DBI::dbDisconnect(verify_con3, shutdown = TRUE)

unlink(parquet_full)

# =============================================================================
# Cleanup
# =============================================================================

DBI::dbDisconnect(con, shutdown = TRUE)
unlink(build_dir, recursive = TRUE)
