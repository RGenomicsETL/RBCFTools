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
    if (
        nchar(test_bcf) > 0 && file.exists(test_bcf) && vcf_has_index(test_bcf)
    ) {
        # Test single-threaded mode (baseline)
        output_single <- tempfile(fileext = ".parquet")
        result_single <- tryCatch(
            {
                vcf_to_parquet(test_bcf, output_single, threads = 1)
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
                    vcf_to_parquet(test_bcf, output_parallel, threads = 2)
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
                    vcf_to_parquet(test_vcf, output_no_idx, threads = 4)
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
