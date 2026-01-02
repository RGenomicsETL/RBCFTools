# Version and Capability Functions
#
# Functions to retrieve version information and capabilities of the

# bundled htslib and bcftools libraries.

#' Get htslib Version
#'
#' Returns the version string of the bundled htslib library.
#'
#' @return A character string containing the htslib version.
#'
#' @examples
#' htslib_version()
#'
#' @export
htslib_version <- function() {
    .Call(RC_htslib_version)
}

#' Get bcftools Version
#'
#' Returns the version string of the bundled bcftools library.
#'
#' @return A character string containing the bcftools version.
#'
#' @examples
#' bcftools_version()
#'
#' @export
bcftools_version <- function() {
    .Call(RC_bcftools_version)
}

#' Get htslib Features Bitfield
#'
#' Returns the raw bitfield of enabled features in htslib.
#'
#' @return An integer representing the feature bitfield.
#'
#' @examples
#' htslib_features()
#'
#' @export
htslib_features <- function() {
    .Call(RC_htslib_features)
}

#' Get htslib Feature String
#'
#' Returns a human-readable string describing the enabled features in htslib.
#'
#' @return A character string describing the enabled features.
#'
#' @examples
#' htslib_feature_string()
#'
#' @export
htslib_feature_string <- function() {
    .Call(RC_htslib_feature_string)
}

#' Check for a Specific htslib Feature
#'
#' Checks if a specific feature is enabled in the bundled htslib library.
#'
#' @param feature_id An integer feature ID. Use one of the `HTS_FEATURE_*`
#'   constants.
#'
#' @return A logical value indicating if the feature is enabled.
#'
#' @examples
#' # Check for libcurl support (feature ID 1024)
#' htslib_has_feature(1024L)
#'
#' @export
htslib_has_feature <- function(feature_id) {
    stopifnot(is.integer(feature_id), length(feature_id) == 1L)
    .Call(RC_htslib_has_feature, feature_id)
}

#' Get htslib Capabilities
#'
#' Returns a named list of all capabilities of the bundled htslib library.
#'
#' @return A named list with logical values for each capability:
#'   \describe{
#'     \item{configure}{Whether ./configure was used to build.}
#'     \item{plugins}{Whether plugins are enabled.}
#'     \item{libcurl}{Whether libcurl support is enabled.}
#'     \item{s3}{Whether S3 support is enabled.}
#'     \item{gcs}{Whether Google Cloud Storage support is enabled.}
#'     \item{libdeflate}{Whether libdeflate compression is enabled.}
#'     \item{lzma}{Whether LZMA compression is enabled.}
#'     \item{bzip2}{Whether bzip2 compression is enabled.}
#'     \item{htscodecs}{Whether htscodecs library is available.}
#'   }
#'
#' @examples
#' caps <- htslib_capabilities()
#' caps$libcurl
#' caps$s3
#'
#' @export
htslib_capabilities <- function() {
    .Call(RC_htslib_capabilities)
}

# Feature ID constants for use with htslib_has_feature()

#' @rdname htslib_has_feature
#' @export
HTS_FEATURE_CONFIGURE <- 1L

#' @rdname htslib_has_feature
#' @export
HTS_FEATURE_PLUGINS <- 2L
#' @rdname htslib_has_feature
#' @export
HTS_FEATURE_LIBCURL <- bitwShiftL(1L, 10L)

#' @rdname htslib_has_feature
#' @export
HTS_FEATURE_S3 <- bitwShiftL(1L, 11L)

#' @rdname htslib_has_feature
#' @export
HTS_FEATURE_GCS <- bitwShiftL(1L, 12L)

#' @rdname htslib_has_feature
#' @export
HTS_FEATURE_LIBDEFLATE <- bitwShiftL(1L, 20L)

#' @rdname htslib_has_feature
#' @export
HTS_FEATURE_LZMA <- bitwShiftL(1L, 21L)

#' @rdname htslib_has_feature
#' @export
HTS_FEATURE_BZIP2 <- bitwShiftL(1L, 22L)

#' @rdname htslib_has_feature
#' @export
HTS_FEATURE_HTSCODECS <- bitwShiftL(1L, 23L)
