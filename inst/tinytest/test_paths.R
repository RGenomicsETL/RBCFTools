# Test path functions
library(RBCFTools)
library(tinytest)
# Test bcftools_path returns a string
expect_true(
  is.character(bcftools_path()),
  info = "bcftools_path() should return a character"
)

# Test bcftools_bin_dir returns a string
expect_true(
  is.character(bcftools_bin_dir()),
  info = "bcftools_bin_dir() should return a character"
)

# Test bcftools_plugins_dir returns a string
expect_true(
  is.character(bcftools_plugins_dir()),
  info = "bcftools_plugins_dir() should return a character"
)

# Test htslib_bin_dir returns a string
expect_true(
  is.character(htslib_bin_dir()),
  info = "htslib_bin_dir() should return a character"
)

# Test individual htslib tool paths
expect_true(
  is.character(bgzip_path()),
  info = "bgzip_path() should return a character"
)

expect_true(
  is.character(tabix_path()),
  info = "tabix_path() should return a character"
)

expect_true(
  is.character(htsfile_path()),
  info = "htsfile_path() should return a character"
)

expect_true(
  is.character(annot_tsv_path()),
  info = "annot_tsv_path() should return a character"
)

expect_true(
  is.character(ref_cache_path()),
  info = "ref_cache_path() should return a character"
)

# Test tool listing functions return character vectors
expect_true(
  is.character(bcftools_tools()),
  info = "bcftools_tools() should return a character vector"
)

expect_true(
  is.character(htslib_tools()),
  info = "htslib_tools() should return a character vector"
)

# If package is properly installed, paths should exist
if (nchar(bcftools_path()) > 0) {
  expect_true(
    file.exists(bcftools_path()),
    info = "bcftools executable should exist when path is non-empty"
  )
}

if (nchar(bgzip_path()) > 0) {
  expect_true(
    file.exists(bgzip_path()),
    info = "bgzip executable should exist when path is non-empty"
  )
}

if (nchar(tabix_path()) > 0) {
  expect_true(
    file.exists(tabix_path()),
    info = "tabix executable should exist when path is non-empty"
  )
}

# Test that bcftools_tools contains expected tools when available
tools <- bcftools_tools()
if (length(tools) > 0) {
  expect_true(
    "bcftools" %in% tools,
    info = "bcftools should be in bcftools_tools()"
  )
}

# Test that htslib_tools contains expected tools when available
hts_tools <- htslib_tools()
if (length(hts_tools) > 0) {
  expected_hts_tools <- c("bgzip", "tabix", "htsfile")
  expect_true(
    all(expected_hts_tools %in% hts_tools),
    info = "Expected htslib tools should be in htslib_tools()"
  )
}

# =============================================================================
# LinkingTo Support Function Tests
# =============================================================================

# Test htslib_include_dir returns a valid directory
expect_true(
  is.character(htslib_include_dir()),
  info = "htslib_include_dir() should return a character"
)

if (nchar(htslib_include_dir()) > 0) {
  expect_true(
    dir.exists(htslib_include_dir()),
    info = "htslib include directory should exist"
  )
  # Check for key header files
  expect_true(
    file.exists(file.path(htslib_include_dir(), "htslib", "hts.h")),
    info = "htslib/hts.h header should exist"
  )
  expect_true(
    file.exists(file.path(htslib_include_dir(), "htslib", "vcf.h")),
    info = "htslib/vcf.h header should exist"
  )
}

# Test htslib_lib_dir returns a valid directory
expect_true(
  is.character(htslib_lib_dir()),
  info = "htslib_lib_dir() should return a character"
)

if (nchar(htslib_lib_dir()) > 0) {
  expect_true(
    dir.exists(htslib_lib_dir()),
    info = "htslib library directory should exist"
  )
  # Check for library files
  expect_true(
    file.exists(file.path(htslib_lib_dir(), "libhts.a")),
    info = "libhts.a static library should exist"
  )
}

# Test bcftools_lib_dir returns a valid directory
expect_true(
  is.character(bcftools_lib_dir()),
  info = "bcftools_lib_dir() should return a character"
)

if (nchar(bcftools_lib_dir()) > 0) {
  expect_true(
    dir.exists(bcftools_lib_dir()),
    info = "bcftools library directory should exist"
  )
}

# Test htslib_cflags returns proper format
expect_true(
  is.character(htslib_cflags()),
  info = "htslib_cflags() should return a character"
)

if (nchar(htslib_include_dir()) > 0) {
  expect_true(
    grepl("^-I", htslib_cflags()),
    info = "htslib_cflags() should start with -I"
  )
}

# Test htslib_libs returns proper format
expect_true(
  is.character(htslib_libs()),
  info = "htslib_libs() should return a character"
)

if (nchar(htslib_lib_dir()) > 0) {
  expect_true(
    grepl("-L.*-lhts", htslib_libs()),
    info = "htslib_libs() should contain -L and -lhts"
  )
}

# Test htslib_libs with static = TRUE
expect_true(
  is.character(htslib_libs(static = TRUE)),
  info = "htslib_libs(static = TRUE) should return a character"
)

if (nchar(htslib_lib_dir()) > 0) {
  static_libs <- htslib_libs(static = TRUE)
  expect_true(
    grepl("-lpthread", static_libs) && grepl("-lz", static_libs),
    info = "htslib_libs(static = TRUE) should include dependency libraries"
  )
}

# Test bcftools_libs returns proper format
expect_true(
  is.character(bcftools_libs()),
  info = "bcftools_libs() should return a character"
)

if (nchar(bcftools_lib_dir()) > 0) {
  expect_true(
    grepl("-L.*-lbcftools", bcftools_libs()),
    info = "bcftools_libs() should contain -L and -lbcftools"
  )
}

# Test linking_info returns a proper list
info <- linking_info()
expect_true(
  is.list(info),
  info = "linking_info() should return a list"
)

expected_names <- c(
  "htslib_include",
  "htslib_lib",
  "bcftools_lib",
  "cflags",
  "htslib_libs",
  "htslib_libs_static",
  "bcftools_libs",
  "all_libs"
)
expect_true(
  all(expected_names %in% names(info)),
  info = "linking_info() should contain all expected elements"
)

# Test print_makevars_config runs without error
expect_silent(
  capture.output(print_makevars_config())
)

expect_silent(
  capture.output(print_makevars_config(use_bcftools = TRUE))
)

expect_silent(
  capture.output(print_makevars_config(static = TRUE))
)

# =============================================================================
# Compilation Test Against htslib
# =============================================================================
# This test actually compiles a simple C program against htslib to verify
# the linking information is correct and usable.

test_compile_against_htslib <- function() {
  # Skip if we don't have the necessary directories
  if (nchar(htslib_include_dir()) == 0 || nchar(htslib_lib_dir()) == 0) {
    return(TRUE) # Skip silently
  }

  # Get R's compiler configuration (like configure script does)
  cc <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "config", "CC"),
    stdout = TRUE,
    stderr = FALSE
  )
  cflags <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "config", "CFLAGS"),
    stdout = TRUE,
    stderr = FALSE
  )

  # Create a temporary directory for the test

  tmp_dir <- tempdir()
  test_c_file <- file.path(tmp_dir, "test_htslib.c")
  test_exe <- file.path(tmp_dir, "test_htslib")

  # Write a simple test program that includes htslib headers
  test_code <- '
#include <stdio.h>
#include <htslib/hts.h>
#include <htslib/vcf.h>

int main(void) {
    // Test that we can call htslib functions
    const char *version = hts_version();
    if (version != NULL) {
        printf("htslib version: %s\\n", version);
        return 0;
    }
    return 1;
}
'
  writeLines(test_code, test_c_file)

  # Build the compile command using static library directly
  lib_path <- file.path(htslib_lib_dir(), "libhts.a")
  compile_cmd <- sprintf(
    "%s %s %s -o %s %s %s -lpthread -lz -lm -lbz2 -llzma -ldeflate -ldl",
    cc,
    cflags,
    htslib_cflags(),
    test_exe,
    test_c_file,
    lib_path
  )

  # Try to compile
  compile_result <- system(
    compile_cmd,
    ignore.stdout = TRUE,
    ignore.stderr = TRUE
  )

  # Clean up
  if (file.exists(test_c_file)) {
    file.remove(test_c_file)
  }
  if (file.exists(test_exe)) {
    file.remove(test_exe)
  }

  return(compile_result == 0)
}

# Run the compilation test
expect_true(
  test_compile_against_htslib(),
  info = "Should be able to compile a simple program against htslib"
)

# =============================================================================
# Compilation Test: hts_version() execution
# =============================================================================
# This test compiles AND runs a program to verify runtime linking works

test_run_htslib_program <- function() {
  # Skip if we don't have the necessary directories
  if (nchar(htslib_include_dir()) == 0 || nchar(htslib_lib_dir()) == 0) {
    return(TRUE) # Skip silently
  }

  # Get R's compiler configuration
  cc <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "config", "CC"),
    stdout = TRUE,
    stderr = FALSE
  )
  cflags <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "config", "CFLAGS"),
    stdout = TRUE,
    stderr = FALSE
  )

  # Create a temporary directory for the test
  tmp_dir <- tempdir()
  test_c_file <- file.path(tmp_dir, "test_htslib_run.c")
  test_exe <- file.path(tmp_dir, "test_htslib_run")

  # Write a simple test program
  test_code <- '
#include <stdio.h>
#include <htslib/hts.h>

int main(void) {
    const char *version = hts_version();
    if (version != NULL) {
        printf("%s", version);
        return 0;
    }
    return 1;
}
'
  writeLines(test_code, test_c_file)

  # Build the compile command using static library directly
  lib_path <- file.path(htslib_lib_dir(), "libhts.a")
  compile_cmd <- sprintf(
    "%s %s %s -o %s %s %s -lpthread -lz -lm -lbz2 -llzma -ldeflate -ldl",
    cc,
    cflags,
    htslib_cflags(),
    test_exe,
    test_c_file,
    lib_path
  )

  # Try to compile
  compile_result <- system(
    compile_cmd,
    ignore.stdout = TRUE,
    ignore.stderr = TRUE
  )

  if (compile_result != 0) {
    if (file.exists(test_c_file)) {
      file.remove(test_c_file)
    }
    return(FALSE)
  }

  # Try to run the program
  run_output <- tryCatch(
    {
      system2(test_exe, stdout = TRUE, stderr = FALSE)
    },
    error = function(e) NULL
  )

  # Clean up
  if (file.exists(test_c_file)) {
    file.remove(test_c_file)
  }
  if (file.exists(test_exe)) {
    file.remove(test_exe)
  }

  # Check that we got a version string
  if (is.null(run_output) || length(run_output) == 0) {
    return(FALSE)
  }

  # Version should be something like "1.23"
  return(grepl("^[0-9]+\\.[0-9]+", run_output[1]))
}

expect_true(
  test_run_htslib_program(),
  info = "Should be able to compile and run a program that calls hts_version()"
)

# =============================================================================
# Compilation Test: VCF header functions
# =============================================================================
# More comprehensive test using VCF functions

test_vcf_compile <- function() {
  # Skip if we don't have the necessary directories
  if (nchar(htslib_include_dir()) == 0 || nchar(htslib_lib_dir()) == 0) {
    return(TRUE)
  }

  cc <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "config", "CC"),
    stdout = TRUE,
    stderr = FALSE
  )
  cflags <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "config", "CFLAGS"),
    stdout = TRUE,
    stderr = FALSE
  )

  tmp_dir <- tempdir()
  test_c_file <- file.path(tmp_dir, "test_vcf.c")
  test_exe <- file.path(tmp_dir, "test_vcf")

  # Test program that uses VCF API
  test_code <- '
#include <stdio.h>
#include <stdlib.h>
#include <htslib/vcf.h>
#include <htslib/hts.h>

int main(void) {
    // Create a VCF header
    bcf_hdr_t *hdr = bcf_hdr_init("w");
    if (hdr == NULL) {
        return 1;
    }

    // Add a contig
    bcf_hdr_append(hdr, "##contig=<ID=chr1,length=1000000>");

    // Sync the header
    bcf_hdr_sync(hdr);

    // Get number of sequences using bcf_hdr_seqnames
    int nseq = 0;
    const char **seqnames = bcf_hdr_seqnames(hdr, &nseq);
    printf("Number of sequences: %d\\n", nseq);

    // Free the seqnames array (but not the strings themselves)
    free(seqnames);

    // Clean up
    bcf_hdr_destroy(hdr);

    return (nseq == 1) ? 0 : 1;
}
'
  writeLines(test_code, test_c_file)

  # Use static library directly
  lib_path <- file.path(htslib_lib_dir(), "libhts.a")
  compile_cmd <- sprintf(
    "%s %s %s -o %s %s %s -lpthread -lz -lm -lbz2 -llzma -ldeflate -ldl",
    cc,
    cflags,
    htslib_cflags(),
    test_exe,
    test_c_file,
    lib_path
  )

  compile_result <- system(
    compile_cmd,
    ignore.stdout = TRUE,
    ignore.stderr = TRUE
  )

  success <- FALSE
  if (compile_result == 0 && file.exists(test_exe)) {
    run_result <- system(test_exe, ignore.stdout = TRUE, ignore.stderr = TRUE)
    success <- (run_result == 0)
  }

  # Clean up
  if (file.exists(test_c_file)) {
    file.remove(test_c_file)
  }
  if (file.exists(test_exe)) {
    file.remove(test_exe)
  }

  return(success)
}

expect_true(
  test_vcf_compile(),
  info = "Should be able to compile and run a program using VCF API (bcf_hdr_init, etc.)"
)
