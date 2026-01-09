# Test VEP in-stream parsing functionality
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

# Get test VEP file
test_vep <- system.file("extdata", "test_vep.vcf", package = "RBCFTools")

if (!file.exists(test_vep) || !nzchar(test_vep)) {
  exit_file("test_vep.vcf not found")
}

# =============================================================================
# Test vcf_open_arrow with parse_vep = FALSE (default behavior)
# =============================================================================

stream_no_vep <- vcf_open_arrow(test_vep, parse_vep = FALSE)
expect_true(
  inherits(stream_no_vep, "nanoarrow_array_stream"),
  info = "Should return nanoarrow_array_stream with parse_vep=FALSE"
)

batch_no_vep <- stream_no_vep$get_next()
df_no_vep <- as.data.frame(nanoarrow::convert_array(batch_no_vep))

expect_true(
  is.data.frame(df_no_vep),
  info = "Should convert to data frame without VEP parsing"
)

expect_true(
  all(c("CHROM", "POS", "REF", "ALT") %in% names(df_no_vep)),
  info = "Should have basic VCF columns without VEP parsing"
)

# No VEP columns should be present
vep_cols_no_parse <- grep("^VEP_", names(df_no_vep), value = TRUE)
expect_equal(
  length(vep_cols_no_parse),
  0,
  info = "Should have no VEP columns when parse_vep=FALSE"
)

n_cols_no_vep <- ncol(df_no_vep)

# =============================================================================
# Test vcf_open_arrow with parse_vep = TRUE (all fields)
# =============================================================================

stream_vep <- vcf_open_arrow(test_vep, parse_vep = TRUE)
expect_true(
  inherits(stream_vep, "nanoarrow_array_stream"),
  info = "Should return nanoarrow_array_stream with parse_vep=TRUE"
)

batch_vep <- stream_vep$get_next()
df_vep <- as.data.frame(nanoarrow::convert_array(batch_vep))

expect_true(
  is.data.frame(df_vep),
  info = "Should convert to data frame with VEP parsing"
)

expect_true(
  all(c("CHROM", "POS", "REF", "ALT") %in% names(df_vep)),
  info = "Should have basic VCF columns with VEP parsing"
)

# VEP columns should be present
vep_cols <- grep("^VEP_", names(df_vep), value = TRUE)
expect_true(
  length(vep_cols) > 0,
  info = "Should have VEP columns when parse_vep=TRUE"
)

expect_true(
  ncol(df_vep) > n_cols_no_vep,
  info = "Should have more columns with VEP parsing than without"
)

# Check for expected VEP column names
expect_true(
  "VEP_Consequence" %in% names(df_vep),
  info = "Should have VEP_Consequence column"
)

expect_true(
  "VEP_SYMBOL" %in% names(df_vep),
  info = "Should have VEP_SYMBOL column"
)

expect_true(
  "VEP_IMPACT" %in% names(df_vep),
  info = "Should have VEP_IMPACT column"
)

# =============================================================================
# Test vcf_open_arrow with vep_columns parameter (column selection)
# =============================================================================

selected_cols <- c("Consequence", "SYMBOL", "IMPACT", "Gene")
stream_selected <- vcf_open_arrow(
  test_vep,
  parse_vep = TRUE,
  vep_columns = selected_cols
)

batch_selected <- stream_selected$get_next()
df_selected <- as.data.frame(nanoarrow::convert_array(batch_selected))

vep_cols_selected <- grep("^VEP_", names(df_selected), value = TRUE)

expect_equal(
  length(vep_cols_selected),
  length(selected_cols),
  info = "Should have exactly the number of selected VEP columns"
)

expect_true(
  all(paste0("VEP_", selected_cols) %in% names(df_selected)),
  info = "Should have all selected VEP columns"
)

expect_true(
  ncol(df_selected) < ncol(df_vep),
  info = "Selected columns should result in fewer total columns"
)

# =============================================================================
# Test vcf_open_arrow with vep_transcript = "first" (default)
# =============================================================================

stream_first <- vcf_open_arrow(
  test_vep,
  parse_vep = TRUE,
  vep_columns = c("Consequence", "SYMBOL"),
  vep_transcript = "first"
)

batch_first <- stream_first$get_next()
df_first <- as.data.frame(nanoarrow::convert_array(batch_first))

# In "first" mode, VEP columns should be scalar (not lists)
# Note: Currently returning NULL placeholders, but schema should be scalar
expect_true(
  "VEP_Consequence" %in% names(df_first),
  info = "Should have VEP_Consequence with vep_transcript='first'"
)

expect_true(
  "VEP_SYMBOL" %in% names(df_first),
  info = "Should have VEP_SYMBOL with vep_transcript='first'"
)

# =============================================================================
# Test vcf_open_arrow with vep_transcript = "all"
# =============================================================================

stream_all <- vcf_open_arrow(
  test_vep,
  parse_vep = TRUE,
  vep_columns = c("Consequence", "SYMBOL"),
  vep_transcript = "all"
)

batch_all <- stream_all$get_next()
df_all <- as.data.frame(nanoarrow::convert_array(batch_all))

# In "all" mode, VEP columns should be lists
expect_true(
  "VEP_Consequence" %in% names(df_all),
  info = "Should have VEP_Consequence with vep_transcript='all'"
)

expect_true(
  "VEP_SYMBOL" %in% names(df_all),
  info = "Should have VEP_SYMBOL with vep_transcript='all'"
)

# =============================================================================
# Test vcf_open_arrow with vep_tag parameter (explicit tag)
# =============================================================================

stream_csq <- vcf_open_arrow(
  test_vep,
  parse_vep = TRUE,
  vep_tag = "CSQ",
  vep_columns = c("Consequence", "SYMBOL")
)

batch_csq <- stream_csq$get_next()
df_csq <- as.data.frame(nanoarrow::convert_array(batch_csq))

expect_true(
  "VEP_Consequence" %in% names(df_csq),
  info = "Should parse VEP with explicit vep_tag='CSQ'"
)

# =============================================================================
# Test vcf_open_arrow with non-existent vep_tag (should have no VEP columns)
# =============================================================================

stream_nonexistent <- vcf_open_arrow(
  test_vep,
  parse_vep = TRUE,
  vep_tag = "NONEXISTENT_TAG"
)

batch_nonexistent <- stream_nonexistent$get_next()
df_nonexistent <- as.data.frame(nanoarrow::convert_array(batch_nonexistent))

vep_cols_nonexistent <- grep("^VEP_", names(df_nonexistent), value = TRUE)
expect_equal(
  length(vep_cols_nonexistent),
  0,
  info = "Should have no VEP columns with non-existent tag"
)

# =============================================================================
# Test vcf_open_arrow VEP parsing with other options combined
# =============================================================================

# Test VEP parsing with include_info = FALSE
stream_no_info <- vcf_open_arrow(
  test_vep,
  parse_vep = TRUE,
  vep_columns = c("Consequence", "SYMBOL"),
  include_info = FALSE
)

batch_no_info <- stream_no_info$get_next()
df_no_info <- as.data.frame(nanoarrow::convert_array(batch_no_info))

expect_true(
  "VEP_Consequence" %in% names(df_no_info),
  info = "Should have VEP columns even with include_info=FALSE"
)

# INFO struct should not be present
expect_false(
  "INFO" %in% names(df_no_info),
  info = "Should not have INFO struct when include_info=FALSE"
)

# Test VEP parsing with include_format = FALSE
stream_no_fmt <- vcf_open_arrow(
  test_vep,
  parse_vep = TRUE,
  vep_columns = c("Consequence", "SYMBOL"),
  include_format = FALSE
)

batch_no_fmt <- stream_no_fmt$get_next()
df_no_fmt <- as.data.frame(nanoarrow::convert_array(batch_no_fmt))

expect_true(
  "VEP_Consequence" %in% names(df_no_fmt),
  info = "Should have VEP columns even with include_format=FALSE"
)

# samples struct should not be present
expect_false(
  "samples" %in% names(df_no_fmt),
  info = "Should not have samples struct when include_format=FALSE"
)

# =============================================================================
# Test vcf_to_arrow with VEP parsing
# =============================================================================

df_arrow <- vcf_to_arrow(
  test_vep,
  as = "data.frame",
  parse_vep = TRUE,
  vep_columns = c("Consequence", "SYMBOL", "IMPACT")
)

expect_true(
  is.data.frame(df_arrow),
  info = "vcf_to_arrow should work with VEP parsing"
)

expect_true(
  all(c("VEP_Consequence", "VEP_SYMBOL", "VEP_IMPACT") %in% names(df_arrow)),
  info = "vcf_to_arrow should include VEP columns"
)

# =============================================================================
# Test row count consistency
# =============================================================================

# Row count should be the same with and without VEP parsing
expect_equal(
  nrow(df_vep),
  nrow(df_no_vep),
  info = "Row count should be same with and without VEP parsing"
)

# =============================================================================
# Test VEP column ordering
# =============================================================================

# VEP columns should appear after core columns (CHROM, POS, etc.)
# and before INFO/samples
col_names <- names(df_vep)
vep_indices <- grep("^VEP_", col_names)
core_end <- which(col_names == "FILTER")

expect_true(
  all(vep_indices > core_end),
  info = "VEP columns should appear after FILTER column"
)

# If INFO is present, VEP should come before it
if ("INFO" %in% col_names) {
  info_idx <- which(col_names == "INFO")
  expect_true(
    all(vep_indices < info_idx),
    info = "VEP columns should appear before INFO struct"
  )
}

# =============================================================================
# Test with file that has no VEP annotations
# =============================================================================

test_no_vep <- system.file(
  "extdata",
  "1000G_3samples.bcf",
  package = "RBCFTools"
)

if (file.exists(test_no_vep) && nzchar(test_no_vep)) {
  suppressWarnings({
    stream_no_ann <- vcf_open_arrow(
      test_no_vep,
      parse_vep = TRUE
    )
    batch_no_ann <- stream_no_ann$get_next()
  })

  df_no_ann <- as.data.frame(nanoarrow::convert_array(batch_no_ann))

  vep_cols_no_ann <- grep("^VEP_", names(df_no_ann), value = TRUE)
  expect_equal(
    length(vep_cols_no_ann),
    0,
    info = "Should have no VEP columns for file without VEP annotations"
  )
}

# =============================================================================
# Test schema retrieval with VEP
# =============================================================================

# Test that Arrow schema includes VEP fields
# Note: vcf_arrow_schema doesn't support VEP options yet, but stream schema does
stream_schema <- vcf_open_arrow(
  test_vep,
  parse_vep = TRUE,
  vep_columns = c("Consequence", "SYMBOL")
)

schema <- stream_schema$get_schema()
expect_true(
  !is.null(schema),
  info = "Should be able to get schema from VEP-enabled stream"
)
