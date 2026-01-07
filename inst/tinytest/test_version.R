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

# =============================================================================
# Additional tests for capabilities
# =============================================================================

# Test that feature_string is non-empty
expect_true(
  nchar(htslib_feature_string()) > 0,
  info = "htslib_feature_string() should return non-empty string"
)

# Test that feature bitfield is non-negative
expect_true(
  htslib_features() >= 0L,
  info = "htslib_features() should return non-negative integer"
)

# Test individual feature checks
expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_LIBCURL)),
  info = "Should be able to check for libcurl feature"
)

expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_S3)),
  info = "Should be able to check for S3 feature"
)

expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_GCS)),
  info = "Should be able to check for GCS feature"
)

expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_LIBDEFLATE)),
  info = "Should be able to check for libdeflate feature"
)

expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_LZMA)),
  info = "Should be able to check for LZMA feature"
)

expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_BZIP2)),
  info = "Should be able to check for BZIP2 feature"
)

expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_HTSCODECS)),
  info = "Should be able to check for htscodecs feature"
)

expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_CONFIGURE)),
  info = "Should be able to check for configure feature"
)

expect_true(
  is.logical(htslib_has_feature(HTS_FEATURE_PLUGINS)),
  info = "Should be able to check for plugins feature"
)

# Test consistency between capabilities() and has_feature()
caps <- htslib_capabilities()

expect_equal(
  caps$configure,
  htslib_has_feature(HTS_FEATURE_CONFIGURE),
  info = "capabilities()$configure should match has_feature(HTS_FEATURE_CONFIGURE)"
)

expect_equal(
  caps$plugins,
  htslib_has_feature(HTS_FEATURE_PLUGINS),
  info = "capabilities()$plugins should match has_feature(HTS_FEATURE_PLUGINS)"
)

expect_equal(
  caps$libcurl,
  htslib_has_feature(HTS_FEATURE_LIBCURL),
  info = "capabilities()$libcurl should match has_feature(HTS_FEATURE_LIBCURL)"
)

expect_equal(
  caps$s3,
  htslib_has_feature(HTS_FEATURE_S3),
  info = "capabilities()$s3 should match has_feature(HTS_FEATURE_S3)"
)

expect_equal(
  caps$gcs,
  htslib_has_feature(HTS_FEATURE_GCS),
  info = "capabilities()$gcs should match has_feature(HTS_FEATURE_GCS)"
)

expect_equal(
  caps$libdeflate,
  htslib_has_feature(HTS_FEATURE_LIBDEFLATE),
  info = "capabilities()$libdeflate should match has_feature(HTS_FEATURE_LIBDEFLATE)"
)

expect_equal(
  caps$lzma,
  htslib_has_feature(HTS_FEATURE_LZMA),
  info = "capabilities()$lzma should match has_feature(HTS_FEATURE_LZMA)"
)

expect_equal(
  caps$bzip2,
  htslib_has_feature(HTS_FEATURE_BZIP2),
  info = "capabilities()$bzip2 should match has_feature(HTS_FEATURE_BZIP2)"
)

expect_equal(
  caps$htscodecs,
  htslib_has_feature(HTS_FEATURE_HTSCODECS),
  info = "capabilities()$htscodecs should match has_feature(HTS_FEATURE_HTSCODECS)"
)

# Test that versions are consistent
hts_ver <- htslib_version()
bcf_ver <- bcftools_version()

expect_true(
  nchar(hts_ver) > 0 && nchar(bcf_ver) > 0,
  info = "Both versions should be non-empty"
)

# Test feature constants are unique
feature_constants <- c(
  HTS_FEATURE_CONFIGURE,
  HTS_FEATURE_PLUGINS,
  HTS_FEATURE_LIBCURL,
  HTS_FEATURE_S3,
  HTS_FEATURE_GCS,
  HTS_FEATURE_LIBDEFLATE,
  HTS_FEATURE_LZMA,
  HTS_FEATURE_BZIP2,
  HTS_FEATURE_HTSCODECS
)

expect_equal(
  length(unique(feature_constants)),
  length(feature_constants),
  info = "All feature constants should be unique"
)

# Test that feature constants are positive
expect_true(
  all(feature_constants > 0),
  info = "All feature constants should be positive"
)
