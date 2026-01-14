# Test VCF Arrow functionality
library(RBCFTools)
library(tinytest)

# =============================================================================
# Test Setup - Skip if nanoarrow not available
# =============================================================================

skip_if_no_nanoarrow <- function() {
  if (!requireNamespace("nanoarrow", quietly = TRUE)) {
    exit_file("nanoarrow package not available")
  }
}

skip_if_no_nanoarrow()

# Get test VCF files
test_vcf <- system.file(
  "extdata",
  "1000G_3samples.vcf.gz",
  package = "RBCFTools"
)

test_simple_vcf <- system.file(
  "extdata",
  "test_format_simple.vcf",
  package = "RBCFTools"
)

if (!file.exists(test_vcf) || !nzchar(test_vcf)) {
  exit_file("1000G_3samples.vcf.gz not found")
}

# =============================================================================
# Test vcf_open_arrow - Basic Usage
# =============================================================================

stream <- vcf_open_arrow(test_vcf)
expect_true(
  inherits(stream, "nanoarrow_array_stream"),
  info = "Should return nanoarrow_array_stream object"
)

# Read first batch
batch <- stream$get_next()
expect_true(
  !is.null(batch),
  info = "First batch should not be NULL"
)

# Convert batch to data frame
df <- as.data.frame(nanoarrow::convert_array(batch))
expect_true(
  is.data.frame(df),
  info = "Batch should convert to data frame"
)

expect_true(
  nrow(df) > 0,
  info = "Data frame should have rows"
)

expect_true(
  all(c("CHROM", "POS", "REF", "ALT") %in% names(df)),
  info = "Should have basic VCF columns"
)

# =============================================================================
# Test vcf_open_arrow - Options
# =============================================================================

# Test with custom batch size
stream_small <- vcf_open_arrow(test_vcf, batch_size = 100L)
expect_true(
  inherits(stream_small, "nanoarrow_array_stream"),
  info = "Should work with custom batch_size"
)

# Test include_info parameter
stream_no_info <- vcf_open_arrow(test_vcf, include_info = FALSE)
batch_no_info <- stream_no_info$get_next()
df_no_info <- as.data.frame(nanoarrow::convert_array(batch_no_info))
expect_true(
  is.data.frame(df_no_info),
  info = "Should work with include_info=FALSE"
)

# Test include_format parameter
stream_no_format <- vcf_open_arrow(test_vcf, include_format = FALSE)
batch_no_format <- stream_no_format$get_next()
df_no_format <- as.data.frame(nanoarrow::convert_array(batch_no_format))
expect_true(
  is.data.frame(df_no_format),
  info = "Should work with include_format=FALSE"
)

# Test with samples parameter
if (file.exists(test_simple_vcf)) {
  stream_samples <- vcf_open_arrow(
    test_simple_vcf,
    samples = "sample1"
  )
  expect_true(
    inherits(stream_samples, "nanoarrow_array_stream"),
    info = "Should work with samples parameter"
  )
}

# Test with threads parameter
stream_threads <- vcf_open_arrow(test_vcf, threads = 2L)
expect_true(
  inherits(stream_threads, "nanoarrow_array_stream"),
  info = "Should work with threads parameter"
)

# =============================================================================
# Test vcf_arrow_schema
# =============================================================================

schema <- vcf_arrow_schema(test_vcf)
expect_true(
  inherits(schema, "nanoarrow_schema"),
  info = "Should return nanoarrow_schema object"
)

# =============================================================================
# Test vcf_to_arrow - data.frame output
# =============================================================================

df_full <- vcf_to_arrow(test_vcf, as = "data.frame")
expect_true(
  is.data.frame(df_full),
  info = "Should return data.frame when as='data.frame'"
)

expect_true(
  nrow(df_full) > 0,
  info = "Data frame should have rows"
)

expect_true(
  all(c("CHROM", "POS", "REF", "ALT") %in% names(df_full)),
  info = "Should have basic VCF columns"
)

# =============================================================================
# Test vcf_to_arrow - tibble output (if tibble available)
# =============================================================================

# Note: vcf_to_arrow with as="tibble" returns a regular data.frame if tibble
# package is not available, so we only test if tibble is actually installed
if (
  requireNamespace("tibble", quietly = TRUE) &&
    "package:tibble" %in% search()
) {
  tbl <- vcf_to_arrow(test_vcf, as = "tibble")
  expect_true(
    inherits(tbl, "tbl_df"),
    info = "Should return tibble when as='tibble' and tibble is loaded"
  )
}

# =============================================================================
# Test vcf_to_arrow - batches output
# =============================================================================

batches <- vcf_to_arrow(test_vcf, as = "batches")
expect_true(
  is.list(batches),
  info = "Should return list when as='batches'"
)

expect_true(
  length(batches) > 0,
  info = "Should have at least one batch"
)

expect_true(
  all(sapply(batches, function(b) inherits(b, "nanoarrow_array"))),
  info = "All elements should be nanoarrow_array objects"
)

# =============================================================================
# Test vcf_to_arrow - with options
# =============================================================================

# Test with include_info
df_no_info <- vcf_to_arrow(
  test_vcf,
  as = "data.frame",
  include_info = FALSE
)
expect_true(
  is.data.frame(df_no_info),
  info = "Should work with include_info=FALSE"
)

# Test with include_format
df_no_format <- vcf_to_arrow(
  test_vcf,
  as = "data.frame",
  include_format = FALSE
)
expect_true(
  is.data.frame(df_no_format),
  info = "Should work with include_format=FALSE"
)

# Test with batch_size
df_small_batch <- vcf_to_arrow(
  test_vcf,
  as = "data.frame",
  batch_size = 100L
)
expect_true(
  is.data.frame(df_small_batch),
  info = "Should work with custom batch_size"
)
expect_equal(
  nrow(df_small_batch),
  nrow(df_full),
  info = "Should have same number of rows regardless of batch_size"
)

# =============================================================================
# Test vcf_to_parquet
# =============================================================================

skip_if_no_duckdb <- function() {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    exit_file("duckdb package not available for parquet tests")
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    exit_file("DBI package not available for parquet tests")
  }
}

skip_if_no_duckdb()

parquet_file <- tempfile(fileext = ".parquet")

# Create parquet file
vcf_to_parquet_arrow(test_vcf, parquet_file)

expect_true(
  file.exists(parquet_file),
  info = "Parquet file should be created"
)

expect_true(
  file.size(parquet_file) > 0,
  info = "Parquet file should not be empty"
)

# Verify parquet content
con <- DBI::dbConnect(duckdb::duckdb())
parquet_data <- DBI::dbGetQuery(
  con,
  sprintf("SELECT * FROM '%s' LIMIT 5", parquet_file)
)
expect_true(
  nrow(parquet_data) > 0,
  info = "Should be able to read parquet file"
)
expect_true(
  all(c("CHROM", "POS", "REF", "ALT") %in% names(parquet_data)),
  info = "Parquet should have VCF columns"
)
DBI::dbDisconnect(con, shutdown = TRUE)

# Test with compression options
parquet_zstd <- tempfile(fileext = ".parquet")
vcf_to_parquet_arrow(test_vcf, parquet_zstd, compression = "zstd")
expect_true(
  file.exists(parquet_zstd),
  info = "Should create parquet with zstd compression"
)

parquet_snappy <- tempfile(fileext = ".parquet")
vcf_to_parquet_arrow(test_vcf, parquet_snappy, compression = "snappy")
expect_true(
  file.exists(parquet_snappy),
  info = "Should create parquet with snappy compression"
)

parquet_gzip <- tempfile(fileext = ".parquet")
vcf_to_parquet_arrow(test_vcf, parquet_gzip, compression = "gzip")
expect_true(
  file.exists(parquet_gzip),
  info = "Should create parquet with gzip compression"
)

# Test with row_group_size
parquet_custom_rows <- tempfile(fileext = ".parquet")
vcf_to_parquet_arrow(test_vcf, parquet_custom_rows, row_group_size = 5000L)
expect_true(
  file.exists(parquet_custom_rows),
  info = "Should work with custom row_group_size"
)

# Test streaming mode
parquet_streaming <- tempfile(fileext = ".parquet")
vcf_to_parquet_arrow(test_vcf, parquet_streaming, streaming = TRUE)
expect_true(
  file.exists(parquet_streaming),
  info = "Should work with streaming=TRUE"
)

# Clean up parquet files
unlink(c(
  parquet_file,
  parquet_zstd,
  parquet_snappy,
  parquet_gzip,
  parquet_custom_rows,
  parquet_streaming
))

# =============================================================================
# Test vcf_query
# =============================================================================

# Basic query
query_result <- vcf_query_arrow(
  test_vcf,
  "SELECT CHROM, POS, REF, ALT FROM vcf LIMIT 5"
)
expect_true(
  is.data.frame(query_result),
  info = "vcf_query should return data frame"
)
expect_true(
  nrow(query_result) <= 5,
  info = "LIMIT 5 should return at most 5 rows"
)
expect_true(
  all(c("CHROM", "POS", "REF", "ALT") %in% names(query_result)),
  info = "Should have requested columns"
)

# Aggregation query
count_result <- vcf_query_arrow(
  test_vcf,
  "SELECT COUNT(*) as n FROM vcf"
)
expect_true(
  is.data.frame(count_result),
  info = "Count query should return data frame"
)
expect_true(
  count_result$n[1] > 0,
  info = "Should have positive count"
)

# Group by query
group_result <- vcf_query_arrow(
  test_vcf,
  "SELECT CHROM, COUNT(*) as n FROM vcf GROUP BY CHROM"
)
expect_true(
  is.data.frame(group_result),
  info = "Group by query should return data frame"
)
expect_true(
  all(c("CHROM", "n") %in% names(group_result)),
  info = "Should have CHROM and n columns"
)

# =============================================================================
# Test vcf_to_arrow_ipc
# =============================================================================

ipc_file <- tempfile(fileext = ".arrow")

# Create IPC file (may produce warnings about VCF schema issues)
vcf_to_arrow_ipc(test_vcf, ipc_file)

expect_true(
  file.exists(ipc_file),
  info = "Arrow IPC file should be created"
)

expect_true(
  file.size(ipc_file) > 0,
  info = "Arrow IPC file should not be empty"
)

# Try to read it back if nanoarrow supports it
if (exists("read_ipc_stream", where = asNamespace("nanoarrow"))) {
  ipc_stream <- nanoarrow::read_ipc_stream(ipc_file)
  expect_true(
    inherits(ipc_stream, "nanoarrow_array_stream"),
    info = "Should be able to read IPC file back"
  )
}

# Clean up
unlink(ipc_file)

# =============================================================================
# Test error handling
# =============================================================================

# Non-existent file
expect_error(
  vcf_open_arrow("/nonexistent/file.vcf.gz"),
  info = "Should error on non-existent file"
)

expect_error(
  vcf_arrow_schema("/nonexistent/file.vcf.gz"),
  info = "vcf_arrow_schema should error on non-existent file"
)

expect_error(
  vcf_to_arrow("/nonexistent/file.vcf.gz"),
  info = "vcf_to_arrow should error on non-existent file"
)

# Invalid 'as' parameter
expect_error(
  vcf_to_arrow(test_vcf, as = "invalid"),
  info = "Should error on invalid 'as' parameter"
)
