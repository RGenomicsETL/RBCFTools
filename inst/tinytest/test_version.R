# Test version and capability functions

# Test htslib_version returns a non-empty string
expect_true(
  is.character(htslib_version()),
  info = "htslib_version() should return a character"
)
expect_true(
  nchar(htslib_version()) > 0,
  info = "htslib_version() should return a non-empty string"
)

# Test bcftools_version returns a non-empty string
expect_true(
  is.character(bcftools_version()),
  info = "bcftools_version() should return a character"
)
expect_true(
  nchar(bcftools_version()) > 0,
  info = "bcftools_version() should return a non-empty string"
)

# Test htslib_features returns an integer
expect_true(
  is.integer(htslib_features()),
  info = "htslib_features() should return an integer"
)

# Test htslib_feature_string returns a character
expect_true(
  is.character(htslib_feature_string()),
  info = "htslib_feature_string() should return a character"
)

# Test htslib_capabilities returns a named list
caps <- htslib_capabilities()
expect_true(
  is.list(caps),
  info = "htslib_capabilities() should return a list"
)
expect_true(
  length(names(caps)) > 0,
  info = "htslib_capabilities() should return a named list"
)
expect_true(
  all(vapply(caps, is.logical, logical(1))),
  info = "All elements of htslib_capabilities() should be logical"
)

# Test expected capability names
expected_names <- c(
  "configure",
  "plugins",
  "libcurl",
  "s3",
  "gcs",
  "libdeflate",
  "lzma",
  "bzip2",
  "htscodecs"
)
expect_true(
  all(expected_names %in% names(caps)),
  info = "htslib_capabilities() should include all expected capability names"
)

# Test htslib_has_feature with valid input
expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_CONFIGURE)),
  info = "htslib_has_feature() should return a logical"
)

# Test htslib_has_feature with invalid input
expect_error(
  htslib_has_feature("invalid"),
  info = "htslib_has_feature() should error on non-integer input"
)
expect_error(
  htslib_has_feature(c(1L, 2L)),
  info = "htslib_has_feature() should error on multi-element input"
)

# Test feature constants are defined and are integers
expect_true(is.integer(HTS_FEATURE_CONFIGURE))
expect_true(is.integer(HTS_FEATURE_PLUGINS))
expect_true(is.integer(HTS_FEATURE_LIBCURL))
expect_true(is.integer(HTS_FEATURE_S3))
expect_true(is.integer(HTS_FEATURE_GCS))
expect_true(is.integer(HTS_FEATURE_LIBDEFLATE))
expect_true(is.integer(HTS_FEATURE_LZMA))
expect_true(is.integer(HTS_FEATURE_BZIP2))
expect_true(is.integer(HTS_FEATURE_HTSCODECS))

# Test version formats look reasonable (e.g., "1.23" pattern)
expect_true(
  grepl("^[0-9]+\\.[0-9]+", htslib_version()),
  info = "htslib_version() should match version pattern"
)
expect_true(
  grepl("^[0-9]+\\.[0-9]+", bcftools_version()),
  info = "bcftools_version() should match version pattern"
)
