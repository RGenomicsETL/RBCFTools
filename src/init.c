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

/* Declare external functions from vcf_index_utils.c */
extern SEXP RC_vcf_has_index(SEXP filename_sexp, SEXP index_sexp);
extern SEXP RC_vcf_get_contigs(SEXP filename_sexp);
extern SEXP RC_vcf_get_contig_lengths(SEXP filename_sexp);

/* Declare external functions from vep_parser_r.c */
extern SEXP RC_vep_detect_tag(SEXP filename_sexp);
extern SEXP RC_vep_has_annotation(SEXP filename_sexp);
extern SEXP RC_vep_get_schema(SEXP filename_sexp, SEXP tag_sexp);
extern SEXP RC_vep_infer_type(SEXP field_name_sexp);
extern SEXP RC_vep_parse_record(SEXP csq_sexp, SEXP schema_sexp, SEXP filename_sexp);

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
    /* VCF index utilities */
    {"RC_vcf_has_index", (DL_FUNC)&RC_vcf_has_index, 2},
    {"RC_vcf_get_contigs", (DL_FUNC)&RC_vcf_get_contigs, 1},
    {"RC_vcf_get_contig_lengths", (DL_FUNC)&RC_vcf_get_contig_lengths, 1},
    /* VEP annotation parser */
    {"RC_vep_detect_tag", (DL_FUNC)&RC_vep_detect_tag, 1},
    {"RC_vep_has_annotation", (DL_FUNC)&RC_vep_has_annotation, 1},
    {"RC_vep_get_schema", (DL_FUNC)&RC_vep_get_schema, 2},
    {"RC_vep_infer_type", (DL_FUNC)&RC_vep_infer_type, 1},
    {"RC_vep_parse_record", (DL_FUNC)&RC_vep_parse_record, 3},
    {NULL, NULL, 0}};

/* Package initialization */
void R_init_RBCFTools(DllInfo *dll) {
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
