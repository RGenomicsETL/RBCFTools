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

# =============================================================================
# LinkingTo Support Functions
# =============================================================================
# These functions provide compiler and linker flags for packages that want to
# link against htslib and bcftools via LinkingTo: RBCFTools

#' Get htslib Include Directory
#'
#' Returns the path to the htslib header files for use in compilation.
#'
#' @return A character string containing the path to the htslib include
#'   directory.
#'
#' @details
#' This directory contains the htslib headers (e.g., `htslib/hts.h`,
#' `htslib/vcf.h`, etc.). Use this path with `-I` compiler flag when
#' compiling code that uses htslib.
#'
#' @examples
#' htslib_include_dir()
#'
#' @export
htslib_include_dir <- function() {
  system.file("htslib", "include", package = "RBCFTools")
}

#' Get htslib Library Directory
#'
#' Returns the path to the htslib library files for use in linking.
#'
#' @return A character string containing the path to the htslib lib directory.
#'
#' @details
#' This directory contains `libhts.a` (static) and `libhts.so` (shared)
#' libraries. Use this path with `-L` linker flag when linking against htslib.
#'
#' @examples
#' htslib_lib_dir()
#'
#' @export
htslib_lib_dir <- function() {
  system.file("htslib", "lib", package = "RBCFTools")
}

#' Get bcftools Library Directory
#'
#' Returns the path to the bcftools library files for use in linking.
#'
#' @return A character string containing the path to the bcftools lib directory.
#'
#' @details
#' This directory contains `libbcftools.a` (static) and `libbcftools.so`
#' (shared) libraries.
#'
#' @examples
#' bcftools_lib_dir()
#'
#' @export
bcftools_lib_dir <- function() {
  system.file("bcftools", "lib", package = "RBCFTools")
}

#' Get Compiler Flags for htslib
#'
#' Returns the compiler flags (CFLAGS/CPPFLAGS) needed to compile code
#' that uses htslib.
#'
#' @return A character string containing compiler flags including the `-I`
#'   include path.
#'
#' @examples
#' htslib_cflags()
#' # Use in Makevars: PKG_CPPFLAGS = $(shell Rscript -e "cat(RBCFTools::htslib_cflags())")
#'
#' @export
htslib_cflags <- function() {
  include_dir <- htslib_include_dir()
  if (nchar(include_dir) == 0) {
    return("")
  }
  paste0("-I", include_dir)
}

#' Get Linker Flags for htslib
#'
#' Returns the linker flags needed to link against htslib.
#'
#' @param static Logical. If `TRUE`, returns flags for static linking.
#'   If `FALSE` (default), returns flags for dynamic linking.
#'
#' @return A character string containing linker flags including `-L` library
#'   path and `-l` library names.
#'
#' @details
#' For dynamic linking, returns `-L<libdir> -lhts`.
#' For static linking, also includes the dependent libraries:
#' `-lpthread -lz -lm -lbz2 -llzma -ldeflate`.
#'
#' @examples
#' htslib_libs()
#' htslib_libs(static = TRUE)
#' # Use in Makevars: PKG_LIBS = $(shell Rscript -e "cat(RBCFTools::htslib_libs())")
#'
#' @export
htslib_libs <- function(static = FALSE) {
  lib_dir <- htslib_lib_dir()
  if (nchar(lib_dir) == 0) {
    return("")
  }

  base_libs <- paste0("-L", lib_dir, " -lhts")

  if (static) {
    # Additional libraries needed for static linking
    static_deps <- "-lpthread -lz -lm -lbz2 -llzma -ldeflate -ldl"
    paste(base_libs, static_deps)
  } else {
    base_libs
  }
}

#' Get Linker Flags for bcftools Library
#'
#' Returns the linker flags needed to link against the bcftools library.
#'
#' @return A character string containing linker flags including `-L` library
#'   path and `-l` library name.
#'
#' @details
#' Note that bcftools library also depends on htslib, so you typically need
#' to include both `bcftools_libs()` and `htslib_libs()` in your linker flags.
#'
#' @examples
#' bcftools_libs()
#' # Full linking: paste(RBCFTools::bcftools_libs(), RBCFTools::htslib_libs())
#'
#' @export
bcftools_libs <- function() {
  lib_dir <- bcftools_lib_dir()
  if (nchar(lib_dir) == 0) {
    return("")
  }
  paste0("-L", lib_dir, " -lbcftools")
}

#' Get All Linking Information for RBCFTools
#'
#' Returns a list with all paths and flags needed for linking against
#' htslib and bcftools from this package.
#'
#' @return A named list with the following elements:
#' \describe{
#'   \item{htslib_include}{Path to htslib include directory}
#'   \item{htslib_lib}{Path to htslib library directory}
#'   \item{bcftools_lib}{Path to bcftools library directory}
#'   \item{cflags}{Compiler flags for htslib}
#'   \item{htslib_libs}{Linker flags for htslib (dynamic)}
#'   \item{htslib_libs_static}{Linker flags for htslib (static)}
#'   \item{bcftools_libs}{Linker flags for bcftools}
#'   \item{all_libs}{Combined linker flags for both bcftools and htslib}
#' }
#'
#' @examples
#' info <- linking_info()
#' info$cflags
#' info$all_libs
#'
#' @export
linking_info <- function() {
  list(
    htslib_include = htslib_include_dir(),
    htslib_lib = htslib_lib_dir(),
    bcftools_lib = bcftools_lib_dir(),
    cflags = htslib_cflags(),
    htslib_libs = htslib_libs(static = FALSE),
    htslib_libs_static = htslib_libs(static = TRUE),
    bcftools_libs = bcftools_libs(),
    all_libs = paste(bcftools_libs(), htslib_libs(static = FALSE))
  )
}

#' Print Makevars Configuration for LinkingTo
#'
#' Prints example Makevars configuration that can be used by packages
#' that want to link against htslib and/or bcftools via LinkingTo.
#'
#' @param use_bcftools Logical. If `TRUE`, includes bcftools library flags.
#'   Default is `FALSE` (htslib only).
#' @param static Logical. If `TRUE`, uses static linking flags.
#'   Default is `FALSE`.
#'
#' @return Invisibly returns the Makevars text as a character string.
#'
#' @examples
#' # Print Makevars for htslib only
#' print_makevars_config()
#'
#' # Print Makevars for both bcftools and htslib
#' print_makevars_config(use_bcftools = TRUE)
#'
#' @export
print_makevars_config <- function(use_bcftools = FALSE, static = FALSE) {
  cflags <- htslib_cflags()

  if (use_bcftools) {
    libs <- paste(bcftools_libs(), htslib_libs(static = static))
  } else {
    libs <- htslib_libs(static = static)
  }

  makevars <- paste0(
    "# Add to your package's src/Makevars or src/Makevars.in\n",
    "# Generated by RBCFTools::print_makevars_config()\n\n",
    "PKG_CPPFLAGS = ",
    cflags,
    "\n",
    "PKG_LIBS = ",
    libs,
    "\n"
  )

  cat(makevars)
  invisible(makevars)
}
