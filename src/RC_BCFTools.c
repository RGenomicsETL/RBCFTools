/*
 * RC_BCFTools.c - R bindings for bcftools and htslib
 *
 */

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include "htslib/hts.h"

/* bcftools version from version.h */
#include "bcftools-1.23/version.h"

/*
 * RC_htslib_version
 *
 * Get the htslib version string.
 *
 * @return Character vector of length 1 containing the htslib version.
 */
SEXP RC_htslib_version(void) {
  SEXP result = PROTECT(Rf_allocVector(STRSXP, 1));
  SET_STRING_ELT(result, 0, Rf_mkChar(hts_version()));
  UNPROTECT(1);
  return result;
}

/*
 * RC_bcftools_version
 *
 * Get the bcftools version string.
 *
 * @return Character vector of length 1 containing the bcftools version.
 */
SEXP RC_bcftools_version(void) {
  SEXP result = PROTECT(Rf_allocVector(STRSXP, 1));
  SET_STRING_ELT(result, 0, Rf_mkChar(BCFTOOLS_VERSION));
  UNPROTECT(1);
  return result;
}

/*
 * RC_htslib_features
 *
 * Get the htslib features as a bitfield.
 *
 * @return Integer vector of length 1 containing the feature bitfield.
 */
SEXP RC_htslib_features(void) {
  SEXP result = PROTECT(Rf_allocVector(INTSXP, 1));
  INTEGER(result)[0] = (int)hts_features();
  UNPROTECT(1);
  return result;
}

/*
 * RC_htslib_feature_string
 *
 * Get the htslib features as a human-readable string.
 *
 * @return Character vector of length 1 containing the feature string.
 */
SEXP RC_htslib_feature_string(void) {
  SEXP result = PROTECT(Rf_allocVector(STRSXP, 1));
  const char *features = hts_feature_string();
  SET_STRING_ELT(result, 0, Rf_mkChar(features ? features : ""));
  UNPROTECT(1);
  return result;
}

/*
 * RC_htslib_has_feature
 *
 * Check if a specific htslib feature is enabled.
 *
 * @param feature_id Integer feature ID (HTS_FEATURE_* constant).
 * @return Logical vector of length 1 indicating if feature is enabled.
 */
SEXP RC_htslib_has_feature(SEXP feature_id) {
  if (TYPEOF(feature_id) != INTSXP || Rf_length(feature_id) != 1) {
    Rf_error("feature_id must be a single integer");
  }

  unsigned int id = (unsigned int)INTEGER(feature_id)[0];
  unsigned int features = hts_features();

  SEXP result = PROTECT(Rf_allocVector(LGLSXP, 1));
  LOGICAL(result)[0] = (features & id) != 0;
  UNPROTECT(1);
  return result;
}

/*
 * RC_htslib_capabilities
 *
 * Get a named list of all htslib capabilities.
 *
 * @return Named list with logical values for each capability.
 */
SEXP RC_htslib_capabilities(void) {
  unsigned int features = hts_features();

  /* Define capability names and corresponding feature flags */
  const char *names[] = {"configure", "plugins",   "libcurl", "s3",
                         "gcs",       "libdeflate", "lzma",   "bzip2",
                         "htscodecs"};
  unsigned int flags[] = {
      1,         /* HTS_FEATURE_CONFIGURE */
      2,         /* HTS_FEATURE_PLUGINS */
      (1u << 10), /* HTS_FEATURE_LIBCURL */
      (1u << 11), /* HTS_FEATURE_S3 */
      (1u << 12), /* HTS_FEATURE_GCS */
      (1u << 20), /* HTS_FEATURE_LIBDEFLATE */
      (1u << 21), /* HTS_FEATURE_LZMA */
      (1u << 22), /* HTS_FEATURE_BZIP2 */
      (1u << 23)  /* HTS_FEATURE_HTSCODECS */
  };

  int n = sizeof(names) / sizeof(names[0]);

  SEXP result = PROTECT(Rf_allocVector(VECSXP, n));
  SEXP result_names = PROTECT(Rf_allocVector(STRSXP, n));

  for (int i = 0; i < n; i++) {
    SEXP val = PROTECT(Rf_allocVector(LGLSXP, 1));
    LOGICAL(val)[0] = (features & flags[i]) != 0;
    SET_VECTOR_ELT(result, i, val);
    SET_STRING_ELT(result_names, i, Rf_mkChar(names[i]));
    UNPROTECT(1);
  }

  Rf_setAttrib(result, R_NamesSymbol, result_names);
  UNPROTECT(2);
  return result;
}
