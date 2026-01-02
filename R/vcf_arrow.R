# VCF/BCF to Arrow Stream Interface
#
# This module provides functions to read VCF/BCF files as Arrow streams,
# enabling zero-copy data sharing with other Arrow-compatible tools like
# DuckDB, Polars, and conversion to Parquet format.
#
# @import nanoarrow

#' Create an Arrow stream from a VCF/BCF file
#'
#' Opens a VCF or BCF file and creates an Arrow array stream that produces
#' record batches. This enables efficient, streaming access to variant data
#' in Arrow format.
#'
#' @param filename Path to VCF or BCF file
#' @param batch_size Number of records per batch (default: 10000)
#' @param region Optional region string for filtering (e.g., "chr1:1000-2000")
#' @param samples Optional sample filter (comma-separated names or "-" prefixed to exclude)
#' @param include_info Include INFO fields in output (default: TRUE)
#' @param include_format Include FORMAT/sample data in output (default: TRUE)
#' @param threads Number of decompression threads (default: 0 = auto)
#'
#' @return A nanoarrow_array_stream object
#'
#' @examples
#' \dontrun{
#' # Basic usage
#' stream <- vcf_open_arrow("variants.vcf.gz")
#'
#' # Read batches
#' while (!is.null(batch <- stream$get_next())) {
#'     # Process batch...
#'     print(nanoarrow::as_tibble(batch))
#' }
#'
#' # With region filter
#' stream <- vcf_open_arrow("variants.vcf.gz", region = "chr1:1-1000000")
#'
#' # Convert to data frame
#' df <- vcf_to_arrow_df("variants.vcf.gz")
#'
#' # Write to parquet (requires arrow package)
#' arrow::write_parquet(vcf_to_arrow_df("variants.vcf.gz"), "variants.parquet")
#' }
#'
#' @export
vcf_open_arrow <- function(filename,
                           batch_size = 10000L,
                           region = NULL,
                           samples = NULL,
                           include_info = TRUE,
                           include_format = TRUE,
                           threads = 0L) {
    if (!requireNamespace("nanoarrow", quietly = TRUE)) {
        stop("Package 'nanoarrow' is required for Arrow stream support")
    }

    # Normalize path
    filename <- normalizePath(filename, mustWork = TRUE)

    .Call(
        vcf_to_arrow_stream,
        filename,
        as.integer(batch_size),
        region,
        samples,
        as.logical(include_info),
        as.logical(include_format),
        as.integer(threads)
    )
}

#' Get the Arrow schema for a VCF file
#'
#' Reads the header of a VCF/BCF file and returns the corresponding
#' Arrow schema.
#'
#' @param filename Path to VCF or BCF file
#'
#' @return A nanoarrow_schema object
#'
#' @export
vcf_arrow_schema <- function(filename) {
    if (!requireNamespace("nanoarrow", quietly = TRUE)) {
        stop("Package 'nanoarrow' is required for Arrow stream support")
    }

    filename <- normalizePath(filename, mustWork = TRUE)
    .Call(vcf_arrow_get_schema, filename)
}

#' Read VCF/BCF file into an Arrow Table or data frame
#'
#' Convenience function to read an entire VCF file into memory as an
#' Arrow-compatible object.
#'
#' @param filename Path to VCF or BCF file
#' @param as Character string specifying output format: "arrow_table",
#'   "tibble", "data.frame", or "batches" (list of arrow arrays)
#' @param ... Additional arguments passed to vcf_open_arrow
#'
#' @return Depends on \code{as} parameter:
#'   - "arrow_table": An Arrow Table (requires arrow package)
#'   - "tibble": A tibble
#'   - "data.frame": A data.frame
#'   - "batches": A list of nanoarrow_array objects
#'
#' @export
vcf_to_arrow <- function(filename,
                         as = c("tibble", "data.frame", "arrow_table", "batches"),
                         ...) {
    as <- match.arg(as)

    stream <- vcf_open_arrow(filename, ...)

    if (as == "batches") {
        # Collect all batches as a list
        batches <- list()
        while (!is.null(batch <- stream$get_next())) {
            batches <- c(batches, list(batch))
        }
        return(batches)
    }

    if (as == "arrow_table") {
        if (!requireNamespace("arrow", quietly = TRUE)) {
            stop("Package 'arrow' is required for arrow_table output")
        }
        # Convert stream to Arrow Table
        return(arrow::as_arrow_table(stream))
    }

    # For tibble/data.frame, collect and convert
    result <- nanoarrow::convert_array_stream(stream)

    if (as == "data.frame") {
        result <- as.data.frame(result)
    }

    result
}

#' Write VCF/BCF to Parquet format
#'
#' Converts a VCF/BCF file to Apache Parquet format for efficient storage
#' and querying with tools like DuckDB, Spark, or Python pandas/polars.
#'
#' @param input_vcf Path to input VCF or BCF file
#' @param output_parquet Path for output Parquet file
#' @param compression Compression codec: "snappy", "gzip", "zstd", "lz4", "none"
#' @param row_group_size Number of rows per row group (default: 100000)
#' @param ... Additional arguments passed to vcf_open_arrow
#'
#' @return Invisibly returns the output path
#'
#' @examples
#' \dontrun{
#' vcf_to_parquet("variants.vcf.gz", "variants.parquet")
#'
#' # With zstd compression
#' vcf_to_parquet("variants.vcf.gz", "variants.parquet", compression = "zstd")
#'
#' # Query with DuckDB
#' library(duckdb)
#' con <- dbConnect(duckdb())
#' dbGetQuery(con, "SELECT CHROM, POS, REF FROM 'variants.parquet' WHERE CHROM = 'chr1'")
#' }
#'
#' @export
vcf_to_parquet <- function(input_vcf,
                           output_parquet,
                           compression = "snappy",
                           row_group_size = 100000L,
                           ...) {
    if (!requireNamespace("arrow", quietly = TRUE)) {
        stop("Package 'arrow' is required for Parquet support")
    }

    stream <- vcf_open_arrow(input_vcf, ...)

    # Convert stream to Arrow Table and write to Parquet
    # arrow::write_parquet handles nanoarrow streams directly
    arrow_table <- arrow::as_arrow_table(stream)

    arrow::write_parquet(
        arrow_table,
        sink = output_parquet,
        compression = compression,
        chunk_size = row_group_size
    )

    message(sprintf(
        "Wrote %d rows to %s",
        arrow_table$num_rows, output_parquet
    ))

    invisible(output_parquet)
}

#' Query VCF/BCF with DuckDB via Arrow
#'
#' Enables SQL queries on VCF files using DuckDB's Arrow integration.
#' This allows powerful filtering, aggregation, and joining operations.
#'
#' @param vcf_files Character vector of VCF file paths
#' @param query SQL query string. Use "vcf" as the table name.
#' @param ... Additional arguments passed to vcf_open_arrow
#'
#' @return Query result as a data frame
#'
#' @examples
#' \dontrun{
#' # Count variants per chromosome
#' vcf_query(
#'     "variants.vcf.gz",
#'     "SELECT CHROM, COUNT(*) as n FROM vcf GROUP BY CHROM"
#' )
#'
#' # Filter high-quality variants
#' vcf_query(
#'     "variants.vcf.gz",
#'     "SELECT * FROM vcf WHERE QUAL > 30"
#' )
#'
#' # Join multiple VCF files
#' vcf_query(
#'     c("sample1.vcf.gz", "sample2.vcf.gz"),
#'     "SELECT * FROM vcf WHERE POS BETWEEN 1000 AND 2000"
#' )
#' }
#'
#' @export
vcf_query <- function(vcf_files, query, ...) {
    if (!requireNamespace("duckdb", quietly = TRUE)) {
        stop("Package 'duckdb' is required for SQL query support")
    }
    if (!requireNamespace("arrow", quietly = TRUE)) {
        stop("Package 'arrow' is required for SQL query support")
    }
    if (!requireNamespace("DBI", quietly = TRUE)) {
        stop("Package 'DBI' is required for SQL query support")
    }

    con <- duckdb::dbConnect(duckdb::duckdb())
    on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    # Create union of all VCF files
    if (length(vcf_files) == 1) {
        # Convert nanoarrow stream to Arrow Table for DuckDB compatibility
        stream <- vcf_open_arrow(vcf_files, ...)
        arrow_table <- arrow::as_arrow_table(stream)
        duckdb::duckdb_register_arrow(con, "vcf", arrow_table)
    } else {
        # For multiple files, read into memory and union
        all_data <- do.call(rbind, lapply(vcf_files, function(f) {
            vcf_to_arrow(f, as = "data.frame", ...)
        }))
        DBI::dbWriteTable(con, "vcf", all_data)
    }

    DBI::dbGetQuery(con, query)
}
