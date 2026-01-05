# VCF/BCF to Arrow Stream Interface
#
# This module provides functions to read VCF/BCF files as Arrow streams,
# enabling zero-copy data sharing with other Arrow-compatible tools like
# DuckDB, Polars, and conversion to Parquet/Arrow IPC formats.
#
# Uses nanoarrow for Arrow format support and DuckDB for Parquet/IPC writing.
# No dependency on the heavy arrow R package.
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
#' @param index Optional index file path. If NULL (default), uses auto-detection:
#'   VCF files try .tbi first, then .csi; BCF files use .csi only.
#'   Useful for non-standard index locations or presigned URLs with different paths.
#'   Alternatively, use htslib ##idx## syntax in filename (e.g., "file.vcf.gz##idx##custom.tbi").
#'   Note: Index is only required for region queries; whole-file streaming needs no index.
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
#'     print(nanoarrow::convert_array(batch))
#' }
#'
#' # With region filter
#' stream <- vcf_open_arrow("variants.vcf.gz", region = "chr1:1-1000000")
#'
#' # With custom index file (useful for presigned URLs or non-standard locations)
#' stream <- vcf_open_arrow("variants.vcf.gz", index = "custom_path.tbi", region = "chr1")
#'
#' # Convert to data frame
#' df <- vcf_to_arrow("variants.vcf.gz", as = "data.frame")
#'
#' # Write to parquet (uses DuckDB, no arrow package needed)
#' vcf_to_parquet("variants.vcf.gz", "variants.parquet")
#' }
#'
#' @export
vcf_open_arrow <- function(
  filename,
  batch_size = 10000L,
  region = NULL,
  samples = NULL,
  include_info = TRUE,
  include_format = TRUE,
  index = NULL,
  threads = 0L
) {
    # Normalize local paths, but allow:
    # - Remote URLs (s3://, gs://, http://, https://, ftp://)
    # - htslib ##idx## syntax for custom index paths
    if (
        !grepl("^(s3|gs|http|https|ftp)://", filename) &&
            !grepl("##idx##", filename)
    ) {
        filename <- normalizePath(filename, mustWork = TRUE)
    }

    .Call(
        vcf_to_arrow_stream,
        filename,
        as.integer(batch_size),
        region,
        samples,
        as.logical(include_info),
        as.logical(include_format),
        index,
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
    filename <- normalizePath(filename, mustWork = TRUE)
    .Call(vcf_arrow_get_schema, filename)
}

#' Read VCF/BCF file into a data frame or list of batches
#'
#' Convenience function to read an entire VCF file into memory as an
#' R data structure.
#'
#' @param filename Path to VCF or BCF file
#' @param as Character string specifying output format:
#'   "tibble", "data.frame", or "batches" (list of nanoarrow arrays)
#' @param ... Additional arguments passed to vcf_open_arrow
#'
#' @return Depends on \code{as} parameter:
#'   - "tibble": A tibble
#'   - "data.frame": A data.frame
#'   - "batches": A list of nanoarrow_array objects
#'
#' @export
vcf_to_arrow <- function(
  filename,
  as = c("tibble", "data.frame", "batches"),
  ...
) {
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
#' @param compression Compression codec: "snappy", "gzip", "zstd", "lz4", "uncompressed"
#' @param row_group_size Number of rows per row group (default: 100000)
#' @param streaming Use streaming mode for large files. When TRUE, writes to
#'   a temporary Arrow IPC file first (via nanoarrow), then converts to Parquet
#'   via DuckDB. This avoids loading the entire VCF into R memory. Requires
#'   the DuckDB nanoarrow community extension. Default is FALSE.
#' @param threads Number of parallel threads for processing (default: 1).
#'   When threads > 1 and file is indexed, uses parallel processing by splitting
#'   work across chromosomes/contigs. Each thread processes different regions
#'   simultaneously. Requires indexed file. See \code{\link{vcf_to_parquet_parallel}}
#'   for details.
#' @param index Optional explicit index file path
#' @param ... Additional arguments passed to vcf_open_arrow
#'
#' @return Invisibly returns the output path
#'
#' @details
#' **Processing Modes:**
#'
#' 1. **Standard mode** (`streaming = FALSE, threads = 1`): Loads entire VCF
#'    into memory as data.frame before writing. Fast for small-medium files.
#'
#' 2. **Streaming mode** (`streaming = TRUE, threads = 1`): Two-stage streaming
#'    via temporary Arrow IPC file. Minimal memory usage for large files.
#'
#' 3. **Parallel mode** (`threads > 1`): Requires indexed file. Splits work by
#'    chromosomes, processing multiple regions simultaneously. Near-linear
#'    speedup with thread count. Best for whole-genome VCFs.
#'
#' @examples
#' \dontrun{
#' # Standard mode (fast, loads into memory)
#' vcf_to_parquet("variants.vcf.gz", "variants.parquet")
#'
#' # Streaming mode for large files (low memory)
#' vcf_to_parquet("huge.vcf.gz", "huge.parquet", streaming = TRUE)
#'
#' # Parallel mode for whole-genome VCF (requires index)
#' vcf_to_parquet("wgs.vcf.gz", "wgs.parquet", threads = 8)
#'
#' # Parallel + streaming for massive files
#' vcf_to_parquet("wgs.vcf.gz", "wgs.parquet", threads = 16, streaming = TRUE)
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
vcf_to_parquet <- function(
  input_vcf,
  output_parquet,
  compression = "zstd",
  row_group_size = 100000L,
  streaming = FALSE,
  threads = 1L,
  index = NULL,
  ...
) {
    if (!requireNamespace("duckdb", quietly = TRUE)) {
        stop("Package 'duckdb' is required for Parquet support")
    }
    if (!requireNamespace("DBI", quietly = TRUE)) {
        stop("Package 'DBI' is required for Parquet support")
    }

    # Map compression names to DuckDB format
    compression <- match.arg(
        compression,
        c("snappy", "gzip", "zstd", "lz4", "uncompressed")
    )
    duckdb_compression <- toupper(compression)
    if (duckdb_compression == "LZ4") {
        duckdb_compression <- "LZ4_RAW"
    }

    # Use parallel processing if threads > 1
    if (threads > 1) {
        return(vcf_to_parquet_parallel(
            input_vcf,
            output_parquet,
            threads = threads,
            compression = compression,
            row_group_size = row_group_size,
            streaming = streaming,
            index = index,
            ...
        ))
    }

    # Single-threaded mode
    if (streaming) {
        # Streaming mode: VCF -> IPC (nanoarrow) -> Parquet (DuckDB)
        vcf_to_parquet_streaming(
            input_vcf,
            output_parquet,
            duckdb_compression,
            row_group_size,
            ...
        )
    } else {
        # Standard mode: load into memory
        vcf_to_parquet_inmemory(
            input_vcf,
            output_parquet,
            duckdb_compression,
            row_group_size,
            ...
        )
    }

    invisible(output_parquet)
}

#' @noRd
vcf_to_parquet_inmemory <- function(
  input_vcf,
  output_parquet,
  duckdb_compression,
  row_group_size,
  ...
) {
    # Open VCF stream and convert to data.frame
    stream <- vcf_open_arrow(input_vcf, ...)
    df <- as.data.frame(nanoarrow::convert_array_stream(stream))

    if (nrow(df) == 0L) {
        # Silently skip empty results
        return(invisible(NULL))
    }

    # Use DuckDB to write Parquet
    con <- duckdb::dbConnect(duckdb::duckdb())
    on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    duckdb::duckdb_register(con, "vcf_data", df)

    sql <- sprintf(
        "COPY vcf_data TO '%s' (FORMAT PARQUET, COMPRESSION %s, ROW_GROUP_SIZE %d)",
        output_parquet,
        duckdb_compression,
        as.integer(row_group_size)
    )
    DBI::dbExecute(con, sql)

    message(sprintf("Wrote %d rows to %s", nrow(df), output_parquet))
}

#' @noRd
vcf_to_parquet_streaming <- function(
  input_vcf,
  output_parquet,
  duckdb_compression,
  row_group_size,
  ...
) {
    # Stage 1: Stream VCF to temporary IPC file via nanoarrow
    ipc_temp <- tempfile(fileext = ".arrow")
    on.exit(unlink(ipc_temp), add = TRUE)

    stream <- vcf_open_arrow(input_vcf, ...)
    nanoarrow::write_nanoarrow(stream, ipc_temp)

    # Check if file was written
    if (!file.exists(ipc_temp) || file.size(ipc_temp) == 0) {
        # Silently skip empty results
        return(invisible(NULL))
    }

    # Stage 2: Convert IPC to Parquet via DuckDB with nanoarrow extension
    con <- duckdb::dbConnect(duckdb::duckdb())
    on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    # Load nanoarrow extension for reading Arrow IPC
    tryCatch(
        {
            DBI::dbExecute(con, "LOAD nanoarrow")
        },
        error = function(e) {
            tryCatch(
                {
                    DBI::dbExecute(con, "INSTALL nanoarrow FROM community")
                    DBI::dbExecute(con, "LOAD nanoarrow")
                },
                error = function(e2) {
                    stop(
                        "Streaming mode requires the DuckDB nanoarrow extension. ",
                        "Install with: DBI::dbExecute(con, 'INSTALL nanoarrow FROM community')",
                        "\nOr use streaming = FALSE for in-memory conversion."
                    )
                }
            )
        }
    )

    # Get row count for message
    count_result <- DBI::dbGetQuery(
        con,
        sprintf("SELECT COUNT(*) as n FROM '%s'", ipc_temp)
    )
    n_rows <- count_result$n[1]

    # Convert IPC to Parquet
    sql <- sprintf(
        "COPY (SELECT * FROM '%s') TO '%s' (FORMAT PARQUET, COMPRESSION %s, ROW_GROUP_SIZE %d)",
        ipc_temp,
        output_parquet,
        duckdb_compression,
        as.integer(row_group_size)
    )
    DBI::dbExecute(con, sql)

    message(sprintf(
        "Wrote %d rows to %s (streaming mode)",
        n_rows,
        output_parquet
    ))
}

#' Query VCF/BCF with DuckDB
#'
#' Enables SQL queries on VCF files using DuckDB.
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
    if (!requireNamespace("DBI", quietly = TRUE)) {
        stop("Package 'DBI' is required for SQL query support")
    }

    con <- duckdb::dbConnect(duckdb::duckdb())
    on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    # Read VCF(s) and register with DuckDB
    if (length(vcf_files) == 1) {
        stream <- vcf_open_arrow(vcf_files, ...)
        df <- as.data.frame(nanoarrow::convert_array_stream(stream))
        duckdb::duckdb_register(con, "vcf", df)
    } else {
        # For multiple files, read into memory and union
        all_data <- do.call(
            rbind,
            lapply(vcf_files, function(f) {
                vcf_to_arrow(f, as = "data.frame", ...)
            })
        )
        duckdb::duckdb_register(con, "vcf", all_data)
    }

    DBI::dbGetQuery(con, query)
}

#' Write VCF/BCF to Arrow IPC format
#'
#' Converts a VCF/BCF file to Arrow IPC stream format for efficient
#' storage and interoperability with Arrow-compatible tools.
#' Uses nanoarrow's native IPC writer for streaming output.
#'
#' @param input_vcf Path to input VCF or BCF file
#' @param output_ipc Path for output Arrow IPC file (typically .arrows extension)
#' @param ... Additional arguments passed to vcf_open_arrow
#'
#' @return Invisibly returns the output path
#'
#' @examples
#' \dontrun{
#' vcf_to_arrow_ipc("variants.vcf.gz", "variants.arrows")
#'
#' # Read back with nanoarrow
#' stream <- nanoarrow::read_nanoarrow("variants.arrows")
#' df <- as.data.frame(stream)
#'
#' # Or query with DuckDB
#' library(duckdb)
#' con <- dbConnect(duckdb())
#' dbGetQuery(con, "SELECT * FROM 'variants.arrows' LIMIT 10")
#' }
#'
#' @export
vcf_to_arrow_ipc <- function(input_vcf, output_ipc, ...) {
    # Open VCF as Arrow stream
    stream <- vcf_open_arrow(input_vcf, ...)

    # Write directly to IPC file using nanoarrow
    nanoarrow::write_nanoarrow(stream, output_ipc)

    invisible(output_ipc)
}
