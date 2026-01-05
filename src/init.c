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

/* Declare external functions from vcf_arrow_r.c */
extern SEXP vcf_to_arrow_stream(SEXP filename_sexp, SEXP batch_size_sexp,
                                SEXP region_sexp, SEXP samples_sexp,
                                SEXP include_info_sexp, SEXP include_format_sexp,
                                SEXP index_sexp, SEXP threads_sexp);
extern SEXP vcf_arrow_get_schema(SEXP filename_sexp);
extern SEXP vcf_arrow_read_next_batch(SEXP stream_xptr);
extern SEXP vcf_arrow_collect_batches(SEXP stream_xptr, SEXP max_batches_sexp);

/* Registration table for .Call routines */
static const R_CallMethodDef CallEntries[] = {
    {"RC_htslib_version", (DL_FUNC)&RC_htslib_version, 0},
    {"RC_bcftools_version", (DL_FUNC)&RC_bcftools_version, 0},
    {"RC_htslib_features", (DL_FUNC)&RC_htslib_features, 0},
    {"RC_htslib_feature_string", (DL_FUNC)&RC_htslib_feature_string, 0},
    {"RC_htslib_has_feature", (DL_FUNC)&RC_htslib_has_feature, 1},
    {"RC_htslib_capabilities", (DL_FUNC)&RC_htslib_capabilities, 0},
    /* VCF Arrow stream functions */
    {"vcf_to_arrow_stream", (DL_FUNC)&vcf_to_arrow_stream, 8},
    {"vcf_arrow_get_schema", (DL_FUNC)&vcf_arrow_get_schema, 1},
    {"vcf_arrow_read_next_batch", (DL_FUNC)&vcf_arrow_read_next_batch, 1},
    {"vcf_arrow_collect_batches", (DL_FUNC)&vcf_arrow_collect_batches, 2},
    {NULL, NULL, 0}};

/* Package initialization */
void R_init_RBCFTools(DllInfo *dll) {
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
