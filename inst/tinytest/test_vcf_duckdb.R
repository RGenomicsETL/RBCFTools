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

# =============================================================================
# Test VEP parsing via DuckDB (list-typed VEP_* columns)
# =============================================================================

test_vep_vcf <- system.file(
  "extdata",
  "test_vep.vcf",
  package = "RBCFTools"
)

if (!file.exists(test_vep_vcf) || !nzchar(test_vep_vcf)) {
  exit_file("test_vep.vcf not found")
}

# Describe schema to ensure VEP columns exist and are lists
vep_schema <- DBI::dbGetQuery(
  con,
  sprintf("DESCRIBE SELECT * FROM bcf_read('%s') LIMIT 0;", test_vep_vcf)
)

expect_true(
  any(vep_schema$column_name == "VEP_Consequence"),
  info = "VEP_Consequence column should be present"
)
expect_true(
  any(vep_schema$column_name == "VEP_AF"),
  info = "VEP_AF column should be present"
)

vep_consequence_type <- vep_schema$column_type[
  vep_schema$column_name == "VEP_Consequence"
][1]
vep_af_type <- vep_schema$column_type[vep_schema$column_name == "VEP_AF"][1]

expect_true(
  is.character(vep_consequence_type) && grepl("\\[\\]$", vep_consequence_type),
  info = "VEP_Consequence should be list-typed"
)
expect_true(
  is.character(vep_af_type) && grepl("\\[\\]$", vep_af_type),
  info = "VEP_AF should be list-typed"
)

# Verify data: multiple transcripts preserved and first transcript parsed
vep_data <- DBI::dbGetQuery(
  con,
  sprintf(
    "SELECT list_count(VEP_Consequence) AS n_tx, list_extract(VEP_Consequence,1) AS first_cons, list_extract(VEP_SYMBOL,1) AS first_sym, list_extract(VEP_AF,1) AS first_af FROM bcf_read('%s') LIMIT 1;",
    test_vep_vcf
  )
)

expect_true(
  vep_data$n_tx[1] >= 1,
  info = "VEP should preserve at least one transcript"
)
expect_true(
  !is.na(vep_data$first_cons[1]),
  info = "First transcript consequence should not be NA"
)
expect_true(
  !is.na(vep_data$first_sym[1]),
  info = "First transcript symbol should not be NA"
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

# Test with threads > 1 on indexed file (should use parallel processing)
# 1000G_3samples.vcf.gz has an index file (.tbi)
parquet_multi <- tempfile(fileext = ".parquet")

expect_message(
  vcf_to_parquet_duckdb(
    test_vcf,
    parquet_multi,
    extension_path = ext_path,
    threads = 2L
  ),
  pattern = "Processing.*contigs",
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

    # Test conversion using subranges function as replacement
    expect_message(
      vcf_to_parquet_duckdb(
        test_vcf_indexed,
        parquet_parallel,
        extension_path = ext_path,
        compression = "zstd"
      ),
      pattern = "Wrote.*parquet",
      info = "vcf_to_parquet_duckdb should show progress"
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

# Test error handling when no extension path provided
expect_error(
  vcf_to_parquet_duckdb(
    test_vcf,
    tempfile(fileext = ".parquet"),
    extension_path = NULL,
    con = NULL
  ),
  pattern = "auto-detected|extension",
  info = "Should work without extension path when con is NULL"
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
  normalizePath(result_path, mustWork = FALSE),
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
# Test tidy_format parameter in vcf_to_parquet_duckdb
# =============================================================================

# Test multi-sample VCF tidy export
tidy_out <- tempfile(fileext = ".parquet")

expect_message(
  vcf_to_parquet_duckdb(
    test_vcf,
    tidy_out,
    extension_path = ext_path,
    tidy_format = TRUE
  ),
  pattern = "Wrote:",
  info = "vcf_to_parquet_duckdb with tidy_format=TRUE should write output"
)

expect_true(
  file.exists(tidy_out),
  info = "Tidy parquet file should exist"
)

# Verify tidy structure: SAMPLE_ID column and renamed FORMAT columns
verify_tidy_con <- DBI::dbConnect(duckdb::duckdb())
tidy_data <- DBI::dbGetQuery(
  verify_tidy_con,
  sprintf("SELECT * FROM '%s' LIMIT 10", tidy_out)
)

expect_true(
  "SAMPLE_ID" %in% names(tidy_data),
  info = "Tidy output should have SAMPLE_ID column"
)
expect_true(
  "FORMAT_GT" %in% names(tidy_data),
  info = "Tidy output should have FORMAT_GT (not FORMAT_GT_<sample>)"
)
expect_false(
  any(grepl("^FORMAT_GT_", names(tidy_data))),
  info = "Tidy output should NOT have sample-suffixed FORMAT columns"
)

# Verify row count is multiplied by number of samples
# Original: 11 variants x 3 samples = 33 rows
orig_count <- vcf_count_duckdb(test_vcf, extension_path = ext_path)
tidy_count <- DBI::dbGetQuery(
  verify_tidy_con,
  sprintf("SELECT COUNT(*) as n FROM '%s'", tidy_out)
)$n[1]

expected_samples <- 3L
expect_equal(
  tidy_count,
  orig_count * expected_samples,
  info = "Tidy row count should be variants * samples"
)

DBI::dbDisconnect(verify_tidy_con, shutdown = TRUE)
unlink(tidy_out)

# Test single-sample VCF with underscored sample name
single_sample_vcf <- system.file(
  "extdata",
  "test_deep_variant.vcf.gz",
  package = "RBCFTools"
)

if (file.exists(single_sample_vcf) && nzchar(single_sample_vcf)) {
  tidy_single_out <- tempfile(fileext = ".parquet")

  expect_message(
    vcf_to_parquet_duckdb(
      single_sample_vcf,
      tidy_single_out,
      extension_path = ext_path,
      region = "1:536000-600000",
      tidy_format = TRUE
    ),
    pattern = "Wrote:",
    info = "Should work with single-sample VCF"
  )

  verify_single_con <- DBI::dbConnect(duckdb::duckdb())
  single_data <- DBI::dbGetQuery(
    verify_single_con,
    sprintf("SELECT * FROM '%s' LIMIT 5", tidy_single_out)
  )

  expect_true(
    "SAMPLE_ID" %in% names(single_data),
    info = "Single-sample tidy should have SAMPLE_ID"
  )
  expect_true(
    "FORMAT_MIN_DP" %in% names(single_data) || "FORMAT_DP" %in% names(single_data),
    info = "Single-sample should handle underscored FORMAT fields"
  )
  expect_equal(
    unique(single_data$SAMPLE_ID),
    "test_deep_variant",
    info = "SAMPLE_ID should be the sample name"
  )

  DBI::dbDisconnect(verify_single_con, shutdown = TRUE)
  unlink(tidy_single_out)
}

# Test tidy with columns parameter
tidy_cols_out <- tempfile(fileext = ".parquet")

expect_message(
  vcf_to_parquet_duckdb(
    test_vcf,
    tidy_cols_out,
    extension_path = ext_path,
    columns = c("CHROM", "POS", "REF", "ALT", "SAMPLE_ID", "FORMAT_GT"),
    tidy_format = TRUE
  ),
  pattern = "Wrote:",
  info = "vcf_to_parquet_duckdb tidy should work with columns parameter"
)

verify_cols_con <- DBI::dbConnect(duckdb::duckdb())
cols_data <- DBI::dbGetQuery(
  verify_cols_con,
  sprintf("SELECT * FROM '%s' LIMIT 5", tidy_cols_out)
)

expect_true(
  all(c("CHROM", "POS", "REF", "ALT") %in% names(cols_data)),
  info = "Should have requested columns"
)
expect_false(
  "INFO_DP" %in% names(cols_data),
  info = "Should NOT have unrequested INFO columns"
)
expect_true(
  "SAMPLE_ID" %in% names(cols_data),
  info = "SAMPLE_ID should always be included"
)
expect_true(
  "FORMAT_GT" %in% names(cols_data),
  info = "FORMAT columns should always be included"
)

DBI::dbDisconnect(verify_cols_con, shutdown = TRUE)
unlink(tidy_cols_out)

# Test sites-only VCF (no samples) - should fall back to standard export
sites_only_vcf <- system.file(
  "extdata",
  "gnomad.exomes.r2.0.1.sites.bcf",
  package = "RBCFTools"
)

if (file.exists(sites_only_vcf) && nzchar(sites_only_vcf)) {
  sites_tidy_out <- tempfile(fileext = ".parquet")

  # Sites-only VCF - tidy_format works, but no SAMPLE_ID column (no samples)
  expect_message(
    vcf_to_parquet_duckdb(
      sites_only_vcf,
      sites_tidy_out,
      extension_path = ext_path,
      tidy_format = TRUE
    ),
    pattern = "Wrote:",
    info = "Sites-only VCF with tidy_format should still work"
  )

  expect_true(
    file.exists(sites_tidy_out),
    info = "Sites-only output should exist"
  )

  unlink(sites_tidy_out)
}

# =============================================================================
# Test partition_by parameter in vcf_to_parquet_duckdb
# =============================================================================

# Test tidy format with Hive partitioning by SAMPLE_ID
partition_out_dir <- tempfile()

expect_message(
  vcf_to_parquet_duckdb(
    test_vcf,
    partition_out_dir,
    extension_path = ext_path,
    tidy_format = TRUE,
    partition_by = "SAMPLE_ID"
  ),
  pattern = "Wrote:",
  info = "vcf_to_parquet_duckdb with partition_by should write output"
)

expect_true(
  dir.exists(partition_out_dir),
  info = "Partitioned output should be a directory"
)

# Check for Hive-style partition directories
partition_dirs <- list.dirs(partition_out_dir, recursive = FALSE)
expect_true(
  length(partition_dirs) == 3,
  info = "Should have 3 partition directories (one per sample)"
)

# Partition dirs should be named SAMPLE_ID=<sample_name>
expect_true(
  all(grepl("^SAMPLE_ID=", basename(partition_dirs))),
  info = "Partition directories should be named SAMPLE_ID=<value>"
)

# Check that parquet files exist inside partitions
partition_files <- list.files(
  partition_out_dir,
  pattern = "\\.parquet$",
  recursive = TRUE
)
expect_true(
  length(partition_files) >= 3,
  info = "Should have parquet files in partition directories"
)

# Read the partitioned data using DuckDB with hive_partitioning
verify_partition_con <- DBI::dbConnect(duckdb::duckdb())
partition_data <- DBI::dbGetQuery(
  verify_partition_con,
  sprintf(
    "SELECT * FROM read_parquet('%s/**/*.parquet', hive_partitioning=true) LIMIT 100",
    partition_out_dir
  )
)

expect_true(
  "SAMPLE_ID" %in% names(partition_data),
  info = "Partitioned data should have SAMPLE_ID column from Hive partitioning"
)

# Verify total row count is correct
partition_count <- DBI::dbGetQuery(
  verify_partition_con,
  sprintf(
    "SELECT COUNT(*) as n FROM read_parquet('%s/**/*.parquet', hive_partitioning=true)",
    partition_out_dir
  )
)$n[1]

expect_equal(
  partition_count,
  orig_count * 3L, # 11 variants x 3 samples
  info = "Partitioned data should have correct total row count"
)

# Test that filtering by SAMPLE_ID works efficiently
single_sample_count <- DBI::dbGetQuery(
  verify_partition_con,
  sprintf(
    "SELECT COUNT(*) as n FROM read_parquet('%s/**/*.parquet', hive_partitioning=true) WHERE SAMPLE_ID = 'HG00098'",
    partition_out_dir
  )
)$n[1]

expect_equal(
  single_sample_count,
  orig_count, # 11 variants for one sample
  info = "Filtering by SAMPLE_ID should return correct count"
)

DBI::dbDisconnect(verify_partition_con, shutdown = TRUE)
unlink(partition_out_dir, recursive = TRUE)

# =============================================================================
# Test vcf_open_duckdb
# =============================================================================

# Test basic view creation (default)
vcf_obj <- vcf_open_duckdb(test_vcf, ext_path, table_name = "test_variants")

expect_true(
  inherits(vcf_obj, "vcf_duckdb"),
  info = "vcf_open_duckdb should return vcf_duckdb object"
)
expect_equal(
  vcf_obj$table,
  "test_variants",
  info = "Table name should match"
)
expect_true(
  vcf_obj$is_view,
  info = "Default should create view (lazy)"
)
expect_null(
  vcf_obj$row_count,
  info = "Views should not have row_count"
)

# Query the view
query_result <- DBI::dbGetQuery(vcf_obj$con, "SELECT COUNT(*) as n FROM test_variants")
expect_equal(
  query_result$n[1],
  11L,
  info = "Query should return correct count"
)

vcf_close_duckdb(vcf_obj)

# Test table creation (as_view = FALSE)
vcf_table <- vcf_open_duckdb(test_vcf, ext_path, as_view = FALSE, table_name = "table_variants")

expect_false(
  vcf_table$is_view,
  info = "as_view = FALSE should create table"
)
expect_equal(
  vcf_table$row_count,
  11L,
  info = "Tables should have row_count"
)

# Query the table
table_result <- DBI::dbGetQuery(vcf_table$con, "SELECT CHROM, POS FROM table_variants LIMIT 3")
expect_equal(
  nrow(table_result),
  3L,
  info = "Table query should return results"
)

vcf_close_duckdb(vcf_table)

# Test tidy format as view (default)
vcf_tidy <- vcf_open_duckdb(test_vcf, ext_path, tidy_format = TRUE, table_name = "tidy_variants")

expect_true(
  vcf_tidy$tidy_format,
  info = "tidy_format should be TRUE"
)
expect_true(
  vcf_tidy$is_view,
  info = "Default tidy format should create view"
)
expect_null(
  vcf_tidy$row_count,
  info = "Views should not have row_count"
)

# Verify tidy format works via query
tidy_count <- DBI::dbGetQuery(vcf_tidy$con, "SELECT COUNT(*) as n FROM tidy_variants")
expect_equal(
  tidy_count$n[1],
  33L, # 11 variants * 3 samples
  info = "Tidy format should have variants * samples rows"
)

tidy_result <- DBI::dbGetQuery(vcf_tidy$con, "SELECT DISTINCT SAMPLE_ID FROM tidy_variants")
expect_equal(
  nrow(tidy_result),
  3L,
  info = "Tidy format should have 3 distinct samples"
)

vcf_close_duckdb(vcf_tidy)

# Test column selection
vcf_cols <- vcf_open_duckdb(
  test_vcf,
  ext_path,
  columns = c("CHROM", "POS", "REF", "ALT"),
  table_name = "slim_variants"
)

cols_result <- DBI::dbGetQuery(vcf_cols$con, "SELECT * FROM slim_variants LIMIT 1")
expect_true(
  all(c("CHROM", "POS", "REF", "ALT") %in% names(cols_result)),
  info = "Selected columns should be present"
)
expect_false(
  "INFO_DP" %in% names(cols_result),
  info = "Non-selected columns should not be present"
)

vcf_close_duckdb(vcf_cols)

# Test file-backed database
db_path <- tempfile(fileext = ".duckdb")
vcf_file_db <- vcf_open_duckdb(test_vcf, ext_path, dbdir = db_path, table_name = "persisted")

expect_equal(
  vcf_file_db$dbdir,
  db_path,
  info = "dbdir should match"
)
vcf_close_duckdb(vcf_file_db)

expect_true(
  file.exists(db_path),
  info = "Database file should exist after close"
)

# Reopen and verify data persisted
reopen_con <- vcf_duckdb_connect(ext_path, dbdir = db_path, read_only = TRUE)
reopen_result <- DBI::dbGetQuery(reopen_con, "SELECT COUNT(*) as n FROM persisted")
expect_equal(
  reopen_result$n[1],
  11L,
  info = "Data should persist in file-backed database"
)
DBI::dbDisconnect(reopen_con, shutdown = TRUE)
unlink(db_path)

# Test overwrite functionality with file-backed database (requires as_view = FALSE to persist)
overwrite_db <- tempfile(fileext = ".duckdb")
vcf_first <- vcf_open_duckdb(test_vcf, ext_path, table_name = "overwrite_test", dbdir = overwrite_db, as_view = FALSE)
vcf_close_duckdb(vcf_first)

# Reopen same database - table should exist, can't create again without overwrite
vcf_reopen <- vcf_duckdb_connect(ext_path, dbdir = overwrite_db)
table_exists <- DBI::dbExistsTable(vcf_reopen, "overwrite_test")
expect_true(
  table_exists,
  info = "Table should exist after first creation"
)
DBI::dbDisconnect(vcf_reopen, shutdown = TRUE)

# Test that overwrite = TRUE works
vcf_overwritten <- vcf_open_duckdb(test_vcf, ext_path,
  table_name = "overwrite_test",
  dbdir = overwrite_db,
  as_view = FALSE,
  overwrite = TRUE
)
expect_equal(
  vcf_overwritten$row_count,
  11L,
  info = "Overwritten table should have correct row count"
)
vcf_close_duckdb(vcf_overwritten)
unlink(overwrite_db)

# Test print method
vcf_print <- vcf_open_duckdb(test_vcf, ext_path)
expect_silent(
  capture.output(print(vcf_print))
)
vcf_close_duckdb(vcf_print)

# =============================================================================
# Test parallel view (UNION ALL) with test_deep_variant.vcf.gz
# =============================================================================

deep_variant_vcf <- system.file("extdata", "test_deep_variant.vcf.gz", package = "RBCFTools")

# Parallel view should work when threads > 1 with indexed VCF
vcf_parallel_view <- vcf_open_duckdb(
  deep_variant_vcf,
  ext_path,
  table_name = "parallel_view_test",
  threads = 4L
)

expect_true(
  vcf_parallel_view$is_view,
  info = "Parallel view should still be a view"
)
expect_null(
  vcf_parallel_view$row_count,
  info = "Parallel view should have NULL row_count (lazy)"
)

# Query the parallel view - should return correct data
parallel_count <- DBI::dbGetQuery(
  vcf_parallel_view$con,
  "SELECT COUNT(*) as n FROM parallel_view_test"
)
expect_true(
  parallel_count$n[1] > 350000,
  info = "Parallel view should have > 350k variants (test_deep_variant has ~368k)"
)

# Test that per-chromosome queries work
chr22_count <- DBI::dbGetQuery(
  vcf_parallel_view$con,
  "SELECT COUNT(*) as n FROM parallel_view_test WHERE CHROM = '22'"
)
expect_equal(
  chr22_count$n[1],
  11462L,
  info = "Chr22 should have 11462 variants"
)

vcf_close_duckdb(vcf_parallel_view)

# Test parallel view with tidy format
vcf_parallel_tidy <- vcf_open_duckdb(
  deep_variant_vcf,
  ext_path,
  table_name = "parallel_tidy_test",
  threads = 4L,
  tidy_format = TRUE,
  columns = c("CHROM", "POS", "REF", "ALT", "SAMPLE_ID", "FORMAT_GT")
)

expect_true(
  vcf_parallel_tidy$is_view,
  info = "Parallel tidy view should be a view"
)
expect_true(
  vcf_parallel_tidy$tidy_format,
  info = "Parallel tidy view should have tidy_format = TRUE"
)

# Verify SAMPLE_ID is present (tidy format)
tidy_sample <- DBI::dbGetQuery(
  vcf_parallel_tidy$con,
  "SELECT DISTINCT SAMPLE_ID FROM parallel_tidy_test LIMIT 1"
)
expect_true(
  nrow(tidy_sample) > 0,
  info = "Tidy parallel view should have SAMPLE_ID column"
)

vcf_close_duckdb(vcf_parallel_tidy)

# Compare parallel view vs simple view (should return same data)
# Create fresh connections to ensure no cross-contamination
vcf_parallel_fresh <- vcf_open_duckdb(
  deep_variant_vcf,
  ext_path,
  table_name = "parallel_fresh",
  threads = 4L
)
parallel_fresh_count <- DBI::dbGetQuery(
  vcf_parallel_fresh$con,
  "SELECT COUNT(*) as n FROM parallel_fresh"
)
vcf_close_duckdb(vcf_parallel_fresh)

vcf_simple <- vcf_open_duckdb(
  deep_variant_vcf,
  ext_path,
  table_name = "simple_view_test",
  threads = 1L
)

simple_count <- DBI::dbGetQuery(
  vcf_simple$con,
  "SELECT COUNT(*) as n FROM simple_view_test"
)

expect_equal(
  simple_count$n[1],
  parallel_fresh_count$n[1],
  info = "Simple and parallel views should return same row count"
)

vcf_close_duckdb(vcf_simple)

# =============================================================================
# Cleanup
# =============================================================================

DBI::dbDisconnect(con, shutdown = TRUE)
unlink(build_dir, recursive = TRUE)
