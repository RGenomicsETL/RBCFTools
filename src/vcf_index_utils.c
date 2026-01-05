// VCF/BCF Index Utilities
// Provides C-level functions for index checking and contig extraction
// Uses htslib facilities for robust handling of local and remote files

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include "htslib/vcf.h"
#include "htslib/tbx.h"
#include "htslib/hts.h"

/**
 * Check if a VCF/BCF file has an index
 * Uses htslib's index loading mechanism which handles:
 * - Local and remote files (S3, GCS, HTTP)
 * - ##idx## syntax for custom index paths
 * - Auto-detection of .tbi, .csi indexes
 * 
 * @param filename_sexp Path to VCF/BCF file
 * @param index_sexp Optional explicit index path (or R_NilValue)
 * @return Logical: TRUE if index exists and can be loaded, FALSE otherwise
 */
SEXP RC_vcf_has_index(SEXP filename_sexp, SEXP index_sexp) {
    if (TYPEOF(filename_sexp) != STRSXP || Rf_length(filename_sexp) != 1) {
        Rf_error("filename must be a single character string");
    }
    
    const char* filename = CHAR(STRING_ELT(filename_sexp, 0));
    const char* index_path = NULL;
    
    if (!Rf_isNull(index_sexp) && TYPEOF(index_sexp) == STRSXP) {
        index_path = CHAR(STRING_ELT(index_sexp, 0));
    }
    
    // Try to open the file
    htsFile* fp = hts_open(filename, "r");
    if (!fp) {
        return Rf_ScalarLogical(0);  // File can't be opened
    }
    
    bcf_hdr_t* hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        return Rf_ScalarLogical(0);
    }
    
    // Try to load the index
    hts_idx_t* idx = NULL;
    if (index_path) {
        // Use explicit index path
        idx = bcf_index_load2(filename, index_path);
    } else {
        // Auto-detect index
        idx = bcf_index_load(filename);
    }
    
    int has_idx = (idx != NULL);
    
    // Clean up
    if (idx) hts_idx_destroy(idx);
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    return Rf_ScalarLogical(has_idx);
}

/**
 * Get list of contig names from VCF/BCF header
 * 
 * @param filename_sexp Path to VCF/BCF file
 * @return Character vector of contig names
 */
SEXP RC_vcf_get_contigs(SEXP filename_sexp) {
    if (TYPEOF(filename_sexp) != STRSXP || Rf_length(filename_sexp) != 1) {
        Rf_error("filename must be a single character string");
    }
    
    const char* filename = CHAR(STRING_ELT(filename_sexp, 0));
    
    htsFile* fp = hts_open(filename, "r");
    if (!fp) {
        Rf_error("Failed to open VCF/BCF file: %s", filename);
    }
    
    bcf_hdr_t* hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        Rf_error("Failed to read VCF/BCF header");
    }
    
    // Get number of sequences
    int nseq = 0;
    const char** seqnames = bcf_hdr_seqnames(hdr, &nseq);
    
    if (nseq == 0 || !seqnames) {
        bcf_hdr_destroy(hdr);
        hts_close(fp);
        return Rf_allocVector(STRSXP, 0);  // Empty vector
    }
    
    // Create R character vector
    SEXP result = PROTECT(Rf_allocVector(STRSXP, nseq));
    for (int i = 0; i < nseq; i++) {
        SET_STRING_ELT(result, i, Rf_mkChar(seqnames[i]));
    }
    
    // Clean up
    free(seqnames);
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    UNPROTECT(1);
    return result;
}

/**
 * Get contig lengths from VCF/BCF header
 * 
 * @param filename_sexp Path to VCF/BCF file
 * @return Named integer vector: names are contigs, values are lengths
 */
SEXP RC_vcf_get_contig_lengths(SEXP filename_sexp) {
    if (TYPEOF(filename_sexp) != STRSXP || Rf_length(filename_sexp) != 1) {
        Rf_error("filename must be a single character string");
    }
    
    const char* filename = CHAR(STRING_ELT(filename_sexp, 0));
    
    htsFile* fp = hts_open(filename, "r");
    if (!fp) {
        Rf_error("Failed to open VCF/BCF file: %s", filename);
    }
    
    bcf_hdr_t* hdr = bcf_hdr_read(fp);
    if (!hdr) {
        hts_close(fp);
        Rf_error("Failed to read VCF/BCF header");
    }
    
    int nseq = 0;
    const char** seqnames = bcf_hdr_seqnames(hdr, &nseq);
    
    if (nseq == 0 || !seqnames) {
        bcf_hdr_destroy(hdr);
        hts_close(fp);
        return Rf_allocVector(INTSXP, 0);
    }
    
    // Create R integer vector with names
    SEXP result = PROTECT(Rf_allocVector(INTSXP, nseq));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, nseq));
    
    for (int i = 0; i < nseq; i++) {
        SET_STRING_ELT(names, i, Rf_mkChar(seqnames[i]));
        
        // Get sequence length from header
        int len = bcf_hdr_id2length(hdr, BCF_DT_CTG, i);
        INTEGER(result)[i] = len;
    }
    
    Rf_setAttrib(result, R_NamesSymbol, names);
    
    // Clean up
    free(seqnames);
    bcf_hdr_destroy(hdr);
    hts_close(fp);
    
    UNPROTECT(2);
    return result;
}
