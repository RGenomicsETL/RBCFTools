/*
 * init.c - R native routine registration for RBCFTools
 */

#define R_NO_REMAP
#include <R.h>
#include <R_ext/Rdynload.h>
#include <Rinternals.h>

/* Declare external functions from RC_BCFTools.c */
extern SEXP RC_htslib_version(void);
extern SEXP RC_bcftools_version(void);
extern SEXP RC_htslib_features(void);
extern SEXP RC_htslib_feature_string(void);
extern SEXP RC_htslib_has_feature(SEXP feature_id);
extern SEXP RC_htslib_capabilities(void);

/* Registration table for .Call routines */
static const R_CallMethodDef CallEntries[] = {
    {"RC_htslib_version", (DL_FUNC)&RC_htslib_version, 0},
    {"RC_bcftools_version", (DL_FUNC)&RC_bcftools_version, 0},
    {"RC_htslib_features", (DL_FUNC)&RC_htslib_features, 0},
    {"RC_htslib_feature_string", (DL_FUNC)&RC_htslib_feature_string, 0},
    {"RC_htslib_has_feature", (DL_FUNC)&RC_htslib_has_feature, 1},
    {"RC_htslib_capabilities", (DL_FUNC)&RC_htslib_capabilities, 0},
    {NULL, NULL, 0}};

/* Package initialization */
void R_init_RBCFTools(DllInfo *dll) {
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
