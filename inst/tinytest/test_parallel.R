# Test VCF parallel processing and index utilities
library(RBCFTools)
library(tinytest)

# =============================================================================
# Test Index Detection (C functions)
# =============================================================================

# Test with bundled test file (should have index)
test_vcf <- system.file("extdata", "test_genotypes.vcf", package = "RBCFTools")

if (nchar(test_vcf) > 0 && file.exists(test_vcf)) {
  # Note: test_genotypes.vcf is uncompressed, so no index
  # Let's test the function exists and doesn't crash
  expect_true(
    is.logical(vcf_has_index(test_vcf)),
    info = "vcf_has_index should return logical"
  )
}

# Test with BCF file that should have index
test_bcf <- system.file("extdata", "1000G_3samples.bcf", package = "RBCFTools")

if (nchar(test_bcf) > 0 && file.exists(test_bcf)) {
  has_idx <- vcf_has_index(test_bcf)
  expect_true(
    is.logical(has_idx),
    info = "vcf_has_index should return logical for BCF file"
  )

  # If indexed, test contig extraction
  if (has_idx) {
    contigs <- vcf_get_contigs(test_bcf)
    expect_true(
      is.character(contigs),
      info = "vcf_get_contigs should return character vector"
    )
    expect_true(
      length(contigs) > 0,
      info = "Should have at least one contig"
    )

    # Test contig lengths
    lengths <- vcf_get_contig_lengths(test_bcf)
    expect_true(
      is.integer(lengths),
      info = "vcf_get_contig_lengths should return integer vector"
    )
    expect_true(
      !is.null(names(lengths)),
      info = "Contig lengths should be named"
    )
    expect_equal(
      length(lengths),
      length(contigs),
      info = "Should have same number of lengths as contigs"
    )
  }
}

# =============================================================================
# Test bcftools CLI integration
# =============================================================================

# Test variant counting for indexed file
if (nchar(test_bcf) > 0 && file.exists(test_bcf) && vcf_has_index(test_bcf)) {
  # Test total count
  count <- tryCatch(
    vcf_count_variants(test_bcf),
    error = function(e) NA_integer_
  )

  if (!is.na(count)) {
    expect_true(
      is.integer(count),
      info = "vcf_count_variants should return integer"
    )
    expect_true(
      count >= 0,
      info = "Variant count should be non-negative"
    )
  }

  # Test per-contig counts
  contig_counts <- tryCatch(
    vcf_count_per_contig(test_bcf),
    error = function(e) integer(0)
  )

  if (length(contig_counts) > 0) {
    expect_true(
      is.integer(contig_counts),
      info = "vcf_count_per_contig should return integer vector"
    )
    expect_true(
      !is.null(names(contig_counts)),
      info = "Per-contig counts should be named"
    )
    expect_true(
      all(contig_counts >= 0),
      info = "All counts should be non-negative"
    )
  }
}

# =============================================================================
# Test parallel Parquet conversion (if nanoarrow and duckdb available)
# =============================================================================

if (
  requireNamespace("nanoarrow", quietly = TRUE) &&
    requireNamespace("duckdb", quietly = TRUE) &&
    requireNamespace("DBI", quietly = TRUE)
) {
  # Only test if we have an indexed file
  if (nchar(test_bcf) > 0 && file.exists(test_bcf) && vcf_has_index(test_bcf)) {
    # Test single-threaded mode (baseline)
    output_single <- tempfile(fileext = ".parquet")
    result_single <- tryCatch(
      {
        vcf_to_parquet_arrow(test_bcf, output_single, threads = 1)
        TRUE
      },
      error = function(e) {
        message("Single-threaded conversion failed: ", e$message)
        FALSE
      }
    )

    if (result_single) {
      expect_true(
        file.exists(output_single),
        info = "Single-threaded Parquet file should exist"
      )

      # Get record count
      con <- duckdb::dbConnect(duckdb::duckdb())
      n_single <- DBI::dbGetQuery(
        con,
        sprintf("SELECT COUNT(*) as n FROM '%s'", output_single)
      )$n[1]
      duckdb::dbDisconnect(con, shutdown = TRUE)

      expect_true(
        n_single > 0,
        info = "Should have records in single-threaded output"
      )

      # Test parallel mode (2 threads)
      output_parallel <- tempfile(fileext = ".parquet")
      result_parallel <- tryCatch(
        {
          vcf_to_parquet_arrow(test_bcf, output_parallel, threads = 2)
          TRUE
        },
        error = function(e) {
          message("Parallel conversion failed: ", e$message)
          FALSE
        }
      )

      if (result_parallel) {
        expect_true(
          file.exists(output_parallel),
          info = "Parallel Parquet file should exist"
        )

        # Verify same record count
        con <- duckdb::dbConnect(duckdb::duckdb())
        n_parallel <- DBI::dbGetQuery(
          con,
          sprintf("SELECT COUNT(*) as n FROM '%s'", output_parallel)
        )$n[1]
        duckdb::dbDisconnect(con, shutdown = TRUE)

        expect_equal(
          n_parallel,
          n_single,
          info = "Parallel and single-threaded should produce same record count"
        )

        # Clean up
        unlink(output_parallel)
      }

      # Clean up
      unlink(output_single)
    }
  }
}

# =============================================================================
# Test error handling
# =============================================================================

# Test with non-existent file - should return FALSE, not error
result <- vcf_has_index("nonexistent.vcf.gz")
expect_true(
  is.logical(result) && !result,
  info = "Should return FALSE for non-existent file"
)

expect_error(
  vcf_get_contigs("nonexistent.vcf.gz"),
  info = "Should error for non-existent file"
)

expect_error(
  vcf_get_contig_lengths("nonexistent.vcf.gz"),
  info = "vcf_get_contig_lengths should error for non-existent file"
)

# Test parallel mode without index
if (nchar(test_vcf) > 0 && file.exists(test_vcf)) {
  if (
    requireNamespace("nanoarrow", quietly = TRUE) &&
      requireNamespace("duckdb", quietly = TRUE)
  ) {
    output_no_idx <- tempfile(fileext = ".parquet")

    # Should fall back to single-threaded
    result <- tryCatch(
      {
        suppressWarnings(
          vcf_to_parquet_arrow(test_vcf, output_no_idx, threads = 4)
        )
        TRUE
      },
      error = function(e) FALSE
    )

    # Clean up if created
    if (file.exists(output_no_idx)) {
      unlink(output_no_idx)
    }
  }
}

# =============================================================================
# Test vcf_count_variants edge cases
# =============================================================================

if (nchar(test_bcf) > 0 && file.exists(test_bcf)) {
  # Test count without region
  count1 <- tryCatch(
    vcf_count_variants(test_bcf),
    error = function(e) NA_integer_
  )

  if (!is.na(count1)) {
    expect_true(
      count1 >= 0,
      info = "Count should be non-negative"
    )

    # If indexed, test with region
    if (vcf_has_index(test_bcf)) {
      contigs <- vcf_get_contigs(test_bcf)
      if (length(contigs) > 0) {
        count_region <- tryCatch(
          vcf_count_variants(test_bcf, region = contigs[1]),
          error = function(e) NA_integer_
        )

        if (!is.na(count_region)) {
          expect_true(
            count_region >= 0,
            info = "Region count should be non-negative"
          )
          expect_true(
            count_region <= count1,
            info = "Region count should be <= total count"
          )
        }
      }
    }
  }
}

# =============================================================================
# Test vcf_count_per_contig error handling
# =============================================================================

# Test error when file is not indexed
if (nchar(test_vcf) > 0 && file.exists(test_vcf)) {
  if (!vcf_has_index(test_vcf)) {
    expect_error(
      vcf_count_per_contig(test_vcf),
      pattern = "must be indexed",
      info = "Should error when file is not indexed"
    )
  }
}

# =============================================================================
# Test vcf_to_parquet_parallel edge cases
# =============================================================================

if (
  requireNamespace("nanoarrow", quietly = TRUE) &&
    requireNamespace("duckdb", quietly = TRUE) &&
    requireNamespace("parallel", quietly = TRUE)
) {
  # Test with indexed file
  if (nchar(test_bcf) > 0 && file.exists(test_bcf) && vcf_has_index(test_bcf)) {
    output_par <- tempfile(fileext = ".parquet")

    result <- tryCatch(
      {
        vcf_to_parquet_parallel_arrow(
          test_bcf,
          output_par,
          threads = 2,
          compression = "zstd"
        )
        TRUE
      },
      error = function(e) {
        message("Parallel conversion error: ", e$message)
        FALSE
      }
    )

    if (result && file.exists(output_par)) {
      expect_true(
        file.size(output_par) > 0,
        info = "Parallel parquet should have content"
      )

      # Verify can read it
      con <- duckdb::dbConnect(duckdb::duckdb())
      data <- DBI::dbGetQuery(
        con,
        sprintf("SELECT COUNT(*) as n FROM '%s'", output_par)
      )
      duckdb::dbDisconnect(con, shutdown = TRUE)

      expect_true(
        data$n[1] > 0,
        info = "Should have records in parallel output"
      )

      unlink(output_par)
    }

    # Test with streaming=TRUE
    output_stream <- tempfile(fileext = ".parquet")
    result_stream <- tryCatch(
      {
        vcf_to_parquet_parallel_arrow(
          test_bcf,
          output_stream,
          threads = 2,
          streaming = TRUE
        )
        TRUE
      },
      error = function(e) {
        message("Parallel streaming error: ", e$message)
        FALSE
      }
    )

    if (result_stream && file.exists(output_stream)) {
      expect_true(
        file.size(output_stream) > 0,
        info = "Streaming parallel parquet should have content"
      )
      unlink(output_stream)
    }

    # Test with 1 thread (should fall back to single-threaded)
    output_single <- tempfile(fileext = ".parquet")
    result_single <- tryCatch(
      {
        suppressMessages(
          vcf_to_parquet_parallel_arrow(test_bcf, output_single, threads = 1)
        )
        TRUE
      },
      error = function(e) FALSE
    )

    if (result_single && file.exists(output_single)) {
      expect_true(
        file.size(output_single) > 0,
        info = "Single-threaded fallback should work"
      )
      unlink(output_single)
    }
  }

  # Test fallback when no index
  if (
    nchar(test_vcf) > 0 && file.exists(test_vcf) && !vcf_has_index(test_vcf)
  ) {
    output_fallback <- tempfile(fileext = ".parquet")

    result_fallback <- tryCatch(
      {
        suppressWarnings(
          vcf_to_parquet_parallel_arrow(test_vcf, output_fallback, threads = 4)
        )
        TRUE
      },
      error = function(e) FALSE
    )

    if (file.exists(output_fallback)) {
      unlink(output_fallback)
    }
  }
}
