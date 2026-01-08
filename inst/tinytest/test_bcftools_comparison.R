# Test VCF parsing by comparing Arrow/DuckDB output against bcftools query
library(RBCFTools)
library(tinytest)

# =============================================================================
# Test Setup
# =============================================================================

skip_if_no_deps <- function() {
  if (!requireNamespace("nanoarrow", quietly = TRUE)) {
    exit_file("nanoarrow package not available")
  }
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    exit_file("duckdb package not available")
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    exit_file("DBI package not available")
  }
}

skip_if_no_deps()

# Get test VCF file
test_vcf <- system.file(
  "extdata",
  "1000G_3samples.vcf.gz",
  package = "RBCFTools"
)

if (!file.exists(test_vcf) || !nzchar(test_vcf)) {
  exit_file("1000G_3samples.vcf.gz not found")
}

# Build DuckDB extension once for all tests
ext_path <- bcf_reader_build(tempdir(), verbose = FALSE)

# Helper function to run bcftools query
run_bcftools_query <- function(vcf_file, format_string, region = NULL) {
  bcftools <- bcftools_path()
  # Use system() instead of system2() to handle format string escaping properly
  region_arg <- if (!is.null(region)) paste("-r", shQuote(region)) else ""
  cmd <- sprintf(
    "%s query -f %s %s %s 2>/dev/null",
    shQuote(bcftools),
    shQuote(format_string),
    region_arg,
    shQuote(vcf_file)
  )
  result <- system(cmd, intern = TRUE)
  if (length(result) == 0) {
    return(character(0))
  }
  result
}

# =============================================================================
# Test Basic Fields: CHROM, POS, REF, ALT
# =============================================================================

# Get expected output from bcftools
bcftools_output <- run_bcftools_query(
  test_vcf,
  "%CHROM\\t%POS\\t%REF\\t%ALT\\n"
)

# Parse bcftools output
expected <- do.call(rbind, strsplit(bcftools_output, "\t"))
expected_df <- data.frame(
  CHROM = expected[, 1],
  POS = as.numeric(expected[, 2]),
  REF = expected[, 3],
  ALT_raw = expected[, 4],
  stringsAsFactors = FALSE
)

# Test Arrow stream - read all batches
stream <- vcf_open_arrow(test_vcf)
arrow_batches <- list()
repeat {
  batch <- stream$get_next()
  if (is.null(batch)) {
    break
  }
  arrow_batches[[
    length(arrow_batches) + 1
  ]] <- as.data.frame(nanoarrow::convert_array(batch))
}
stream$release()

# Combine all batches

arrow_df <- do.call(rbind, arrow_batches)


expect_equal(
  arrow_df$CHROM,
  expected_df$CHROM,
  info = "Arrow CHROM should match bcftools"
)

expect_equal(
  arrow_df$POS,
  expected_df$POS,
  info = "Arrow POS should match bcftools"
)

expect_equal(
  arrow_df$REF,
  expected_df$REF,
  info = "Arrow REF should match bcftools"
)

# For ALT, compare reconstructed comma-separated string
arrow_alt_str <- sapply(arrow_df$ALT, function(x) paste(x, collapse = ","))
expect_equal(
  arrow_alt_str,
  expected_df$ALT_raw,
  info = "Arrow ALT (as comma-separated) should match bcftools"
)

# Test DuckDB
con <- vcf_duckdb_connect(extension_path = ext_path)
duckdb_df <- vcf_query_duckdb(
  test_vcf,
  con = con,
  query = "SELECT CHROM, POS, REF, ALT FROM bcf_read('{file}')"
)
DBI::dbDisconnect(con, shutdown = TRUE)

expect_equal(
  duckdb_df$CHROM,
  expected_df$CHROM,
  info = "DuckDB CHROM should match bcftools"
)

expect_equal(
  duckdb_df$POS,
  expected_df$POS,
  info = "DuckDB POS should match bcftools"
)

expect_equal(
  duckdb_df$REF,
  expected_df$REF,
  info = "DuckDB REF should match bcftools"
)

# For DuckDB ALT, compare reconstructed comma-separated string
duckdb_alt_str <- sapply(duckdb_df$ALT, function(x) paste(x, collapse = ","))
expect_equal(
  duckdb_alt_str,
  expected_df$ALT_raw,
  info = "DuckDB ALT (as comma-separated) should match bcftools"
)

# =============================================================================
# Test QUAL and FILTER Fields
# =============================================================================

bcftools_qual_filter <- run_bcftools_query(
  test_vcf,
  "%QUAL\\t%FILTER\\n"
)

qual_filter <- do.call(rbind, strsplit(bcftools_qual_filter, "\t"))
expected_qual <- suppressWarnings(as.numeric(qual_filter[, 1]))
expected_filter <- qual_filter[, 2]

# Test Arrow - read all batches
stream <- vcf_open_arrow(test_vcf)
arrow_batches <- list()
repeat {
  batch <- stream$get_next()
  if (is.null(batch)) {
    break
  }
  arrow_batches[[
    length(arrow_batches) + 1
  ]] <- as.data.frame(nanoarrow::convert_array(batch))
}
stream$release()
arrow_df <- do.call(rbind, arrow_batches)

# Handle missing QUAL (represented as "." in bcftools)
bcftools_qual_na <- is.na(expected_qual) | expected_qual == "."
arrow_qual_na <- is.na(arrow_df$QUAL)

expect_equal(
  bcftools_qual_na,
  arrow_qual_na,
  info = "Arrow QUAL NA values should match bcftools"
)

# Compare non-NA QUAL values with tolerance for floating point
if (any(!arrow_qual_na)) {
  expect_true(
    all(
      abs(arrow_df$QUAL[!arrow_qual_na] - expected_qual[!arrow_qual_na]) < 1e-6
    ),
    info = "Arrow QUAL values should match bcftools"
  )
}

# Test DuckDB QUAL
con <- vcf_duckdb_connect(extension_path = ext_path)
duckdb_df <- vcf_query_duckdb(
  test_vcf,
  con = con,
  query = "SELECT QUAL, FILTER FROM bcf_read('{file}')"
)
DBI::dbDisconnect(con, shutdown = TRUE)

duckdb_qual_na <- is.na(duckdb_df$QUAL)
expect_equal(
  bcftools_qual_na,
  duckdb_qual_na,
  info = "DuckDB QUAL NA values should match bcftools"
)

if (any(!duckdb_qual_na)) {
  expect_true(
    all(
      abs(
        duckdb_df$QUAL[!duckdb_qual_na] - expected_qual[!duckdb_qual_na]
      ) <
        1e-6
    ),
    info = "DuckDB QUAL values should match bcftools"
  )
}

# =============================================================================
# Test ID Field
# =============================================================================

bcftools_id <- run_bcftools_query(test_vcf, "%ID\\n")

# Test Arrow - read all batches
stream <- vcf_open_arrow(test_vcf)
arrow_batches <- list()
repeat {
  batch <- stream$get_next()
  if (is.null(batch)) {
    break
  }
  arrow_batches[[
    length(arrow_batches) + 1
  ]] <- as.data.frame(nanoarrow::convert_array(batch))
}
stream$release()
arrow_df <- do.call(rbind, arrow_batches)

# bcftools returns "." for missing ID, which should be NA or empty in Arrow/DuckDB
expected_id <- ifelse(bcftools_id == ".", NA_character_, bcftools_id)
arrow_id <- arrow_df$ID
arrow_id[arrow_id == ""] <- NA_character_

expect_equal(
  arrow_id,
  expected_id,
  info = "Arrow ID should match bcftools"
)

# Test DuckDB
con <- vcf_duckdb_connect(extension_path = ext_path)
duckdb_df <- vcf_query_duckdb(
  test_vcf,
  con = con,
  query = "SELECT ID FROM bcf_read('{file}')"
)
DBI::dbDisconnect(con, shutdown = TRUE)

duckdb_id <- duckdb_df$ID
duckdb_id[duckdb_id == ""] <- NA_character_

expect_equal(
  duckdb_id,
  expected_id,
  info = "DuckDB ID should match bcftools"
)

# =============================================================================
# Test INFO Fields (if present in test file)
# =============================================================================

# Check if test file has AC INFO field
bcftools_info_check <- tryCatch(
  run_bcftools_query(test_vcf, "%INFO/AC\\n"),
  error = function(e) NULL
)

if (!is.null(bcftools_info_check) && length(bcftools_info_check) > 0) {
  # Parse AC values (can be multi-valued, comma-separated)
  expected_ac_raw <- bcftools_info_check

  # Test Arrow - read all batches
  stream <- vcf_open_arrow(test_vcf)
  arrow_batches <- list()
  repeat {
    batch <- stream$get_next()
    if (is.null(batch)) {
      break
    }
    arrow_batches[[
      length(arrow_batches) + 1
    ]] <- as.data.frame(nanoarrow::convert_array(batch))
  }
  stream$release()
  arrow_df <- do.call(rbind, arrow_batches)

  if ("AC" %in% names(arrow_df)) {
    # Compare AC values
    arrow_ac_str <- sapply(arrow_df$AC, function(x) {
      if (is.null(x) || all(is.na(x))) {
        return(".")
      }
      paste(x, collapse = ",")
    })

    expect_equal(
      arrow_ac_str,
      expected_ac_raw,
      info = "Arrow INFO/AC should match bcftools"
    )
  }

  # Test DuckDB
  con <- vcf_duckdb_connect(extension_path = ext_path)
  duckdb_df <- tryCatch(
    {
      vcf_query_duckdb(
        test_vcf,
        con = con,
        query = "SELECT AC FROM bcf_read('{file}')"
      )
    },
    error = function(e) NULL
  )
  DBI::dbDisconnect(con, shutdown = TRUE)

  if (!is.null(duckdb_df) && "AC" %in% names(duckdb_df)) {
    duckdb_ac_str <- sapply(duckdb_df$AC, function(x) {
      if (is.null(x) || all(is.na(x))) {
        return(".")
      }
      paste(x, collapse = ",")
    })

    expect_equal(
      duckdb_ac_str,
      expected_ac_raw,
      info = "DuckDB INFO/AC should match bcftools"
    )
  }
}

# =============================================================================
# Test Row Count
# =============================================================================

# Count variants with bcftools
bcftools_count <- length(run_bcftools_query(test_vcf, "%CHROM\\n"))

# Test Arrow count
stream <- vcf_open_arrow(test_vcf)
arrow_count <- 0
repeat {
  batch <- stream$get_next()
  if (is.null(batch)) {
    break
  }
  arrow_count <- arrow_count +
    nrow(as.data.frame(nanoarrow::convert_array(batch)))
}
stream$release()

expect_equal(
  arrow_count,
  bcftools_count,
  info = "Arrow total row count should match bcftools"
)

# Test DuckDB count
con <- vcf_duckdb_connect(extension_path = ext_path)
duckdb_count_df <- vcf_query_duckdb(
  test_vcf,
  con = con,
  query = "SELECT COUNT(*) as cnt FROM bcf_read('{file}')"
)
DBI::dbDisconnect(con, shutdown = TRUE)

expect_equal(
  duckdb_count_df$cnt,
  bcftools_count,
  info = "DuckDB total row count should match bcftools"
)
