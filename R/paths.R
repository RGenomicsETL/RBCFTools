# Path Functions
#
# Functions to locate bundled bcftools and htslib executables and directories.

#' Setup Environment for Remote File Access
#'
#' Sets the `HTS_PATH` environment variable to point to the bundled htslib
#' plugins directory. This is required for S3, GCS, and other remote file
#' access via libcurl.
#'
#' @return Invisibly returns the previous value of `HTS_PATH` (or `NA` if unset).
#'
#' @details
#' Call this function before using bcftools/htslib tools with remote URLs
#' (s3://, gs://, http://, etc.). The function sets `HTS_PATH` to the package's
#' plugin directory so htslib can find `hfile_libcurl.so` and `hfile_gcs.so`.
#'
#' @examples
#' setup_hts_env()
#' # Now bcftools can access S3 URLs
#'
#' @export
setup_hts_env <- function() {
  old_value <- Sys.getenv("HTS_PATH", unset = NA)
  Sys.setenv(HTS_PATH = htslib_plugins_dir())
  invisible(old_value)
}

#' Get Path to bcftools Executable
#'
#' Returns the path to the bundled bcftools executable.
#'
#' @return A character string containing the path to the bcftools executable.
#'
#' @examples
#' bcftools_path()
#'
#' @export
bcftools_path <- function() {
  system.file("bcftools", "bin", "bcftools", package = "RBCFTools")
}

#' Get Path to bcftools Binary Directory
#'
#' Returns the path to the directory containing bcftools and related scripts.
#'
#' @return A character string containing the path to the bcftools bin directory.
#'
#' @details
#' The directory contains the following tools:
#' - `bcftools` - Main bcftools executable
#' - `color-chrs.pl` - Chromosome coloring script
#' - `gff2gff` - GFF conversion tool
#' - `gff2gff.py` - GFF conversion Python script
#' - `guess-ploidy.py` - Ploidy guessing script
#' - `plot-roh.py` - ROH plotting script
#' - `plot-vcfstats` - VCF statistics plotting script
#' - `roh-viz` - ROH visualization tool
#' - `run-roh.pl` - ROH analysis script
#' - `vcfutils.pl` - VCF utilities script
#' - `vrfs-variances` - Variant frequency variances tool
#'
#' @examples
#' bcftools_bin_dir()
#'
#' @export
bcftools_bin_dir <- function() {
  system.file("bcftools", "bin", package = "RBCFTools")
}

#' Get Path to bcftools Plugins Directory
#'
#' Returns the path to the directory containing bcftools plugins.
#'
#' @return A character string containing the path to the bcftools plugins
#'   directory.
#'
#' @examples
#' bcftools_plugins_dir()
#'
#' @export
bcftools_plugins_dir <- function() {
  system.file("bcftools", "libexec", "bcftools", package = "RBCFTools")
}

#' Get Path to htslib Plugins Directory
#'
#' Returns the path to the directory containing htslib plugins (e.g., for
#' remote file access via libcurl, S3, GCS).
#'
#' @return A character string containing the path to the htslib plugins
#'   directory.
#'
#' @examples
#' htslib_plugins_dir()
#'
#' @export
htslib_plugins_dir <- function() {
  system.file("htslib", "libexec", "htslib", package = "RBCFTools")
}

#' Get Path to htslib Binary Directory
#'
#' Returns the path to the directory containing htslib executables.
#'
#' @return A character string containing the path to the htslib bin directory.
#'
#' @details
#' The directory contains the following tools:
#' - `annot-tsv` - Annotate TSV files
#' - `bgzip` - Block gzip compression
#' - `htsfile` - Identify file format
#' - `ref-cache` - Reference sequence cache management
#' - `tabix` - Index and query TAB-delimited files
#'
#' @examples
#' htslib_bin_dir()
#'
#' @export
htslib_bin_dir <- function() {
  system.file("htslib", "bin", package = "RBCFTools")
}

#' Get Path to bgzip Executable
#'
#' Returns the path to the bundled bgzip executable.
#'
#' @return A character string containing the path to the bgzip executable.
#'
#' @examples
#' bgzip_path()
#'
#' @export
bgzip_path <- function() {
  system.file("htslib", "bin", "bgzip", package = "RBCFTools")
}

#' Get Path to tabix Executable
#'
#' Returns the path to the bundled tabix executable.
#'
#' @return A character string containing the path to the tabix executable.
#'
#' @examples
#' tabix_path()
#'
#' @export
tabix_path <- function() {
  system.file("htslib", "bin", "tabix", package = "RBCFTools")
}

#' Get Path to htsfile Executable
#'
#' Returns the path to the bundled htsfile executable for identifying file
#' formats.
#'
#' @return A character string containing the path to the htsfile executable.
#'
#' @examples
#' htsfile_path()
#'
#' @export
htsfile_path <- function() {
  system.file("htslib", "bin", "htsfile", package = "RBCFTools")
}

#' Get Path to annot-tsv Executable
#'
#' Returns the path to the bundled annot-tsv executable.
#'
#' @return A character string containing the path to the annot-tsv executable.
#'
#' @examples
#' annot_tsv_path()
#'
#' @export
annot_tsv_path <- function() {
  system.file("htslib", "bin", "annot-tsv", package = "RBCFTools")
}

#' Get Path to ref-cache Executable
#'
#' Returns the path to the bundled ref-cache executable for reference sequence
#' cache management.
#'
#' @return A character string containing the path to the ref-cache executable.
#'
#' @examples
#' ref_cache_path()
#'
#' @export
ref_cache_path <- function() {
  system.file("htslib", "bin", "ref-cache", package = "RBCFTools")
}

#' List Available bcftools Scripts
#'
#' Lists all available scripts and tools in the bcftools bin directory.
#'
#' @return A character vector of available tool names.
#'
#' @examples
#' bcftools_tools()
#'
#' @export
bcftools_tools <- function() {
  bin_dir <- bcftools_bin_dir()
  if (nchar(bin_dir) == 0) {
    return(character(0))
  }

  list.files(bin_dir)
}

#' List Available htslib Tools
#'
#' Lists all available tools in the htslib bin directory.
#'
#' @return A character vector of available tool names.
#'
#' @examples
#' htslib_tools()
#'
#' @export
htslib_tools <- function() {
  bin_dir <- htslib_bin_dir()
  if (nchar(bin_dir) == 0) {
    return(character(0))
  }
  list.files(bin_dir)
}
