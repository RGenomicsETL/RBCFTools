# Parallel VCF Processing Utilities
#
# Functions for parallel processing of VCF/BCF files using chromosome-level
# or region-level chunking with bcftools CLI and htslib C functions

#' Check if VCF/BCF file has an index
#'
#' Uses htslib to robustly check for index presence. Works with local files,
#' remote URLs (S3, GCS, HTTP), and custom index paths.
#'
#' @param filename Path to VCF/BCF file
#' @param index Optional explicit index path
#' @return Logical indicating if index exists
#'
#' @examples
#' \dontrun{
#' vcf_has_index("variants.vcf.gz")
#' vcf_has_index("s3://bucket/file.vcf.gz")
#' vcf_has_index("file.vcf.gz", index = "custom.tbi")
#' }
#'
#' @export
vcf_has_index <- function(filename, index = NULL) {
    .Call(RC_vcf_has_index, filename, index, PACKAGE = "RBCFTools")
}

#' Get contig names from VCF/BCF file
#'
#' Extracts contig names from the VCF/BCF header using htslib.
#'
#' @param filename Path to VCF/BCF file
#' @return Character vector of contig names
#'
#' @examples
#' \dontrun{
#' contigs <- vcf_get_contigs("variants.vcf.gz")
#' }
#'
#' @export
vcf_get_contigs <- function(filename) {
    .Call(RC_vcf_get_contigs, filename, PACKAGE = "RBCFTools")
}

#' Get contig lengths from VCF/BCF file
#'
#' Extracts contig names and lengths from the VCF/BCF header.
#'
#' @param filename Path to VCF/BCF file
#' @return Named integer vector (names = contigs, values = lengths)
#'
#' @examples
#' \dontrun{
#' lengths <- vcf_get_contig_lengths("variants.vcf.gz")
#' }
#'
#' @export
vcf_get_contig_lengths <- function(filename) {
    .Call(RC_vcf_get_contig_lengths, filename, PACKAGE = "RBCFTools")
}

#' Get number of variants using bcftools
#'
#' Uses bundled bcftools to count variants efficiently. For indexed files,
#' this is very fast. Can also count per-chromosome.
#'
#' @param filename Path to VCF/BCF file
#' @param region Optional region string (e.g., "chr1" or "chr1:1-1000")
#' @return Integer count of variants
#'
#' @examples
#' \dontrun{
#' # Total variants
#' n <- vcf_count_variants("variants.vcf.gz")
#'
#' # Variants on chr1
#' n_chr1 <- vcf_count_variants("variants.vcf.gz", region = "chr1")
#' }
#'
#' @export
vcf_count_variants <- function(filename, region = NULL) {
    # Use bcftools index --nrecords for indexed files (fast)
    # Falls back to bcftools view -c for unindexed files
    bcftools <- bcftools_path()

    if (vcf_has_index(filename)) {
        # Fast path: use index statistics
        cmd <- sprintf(
            "%s index --nrecords %s",
            shQuote(bcftools),
            shQuote(filename)
        )

        if (!is.null(region)) {
            # For regions, need to actually query
            cmd <- sprintf(
                "%s view -H %s %s | wc -l",
                shQuote(bcftools),
                shQuote(region),
                shQuote(filename)
            )
        }
    } else {
        # Slow path: count records
        cmd <- sprintf(
            "%s view -H %s | wc -l",
            shQuote(bcftools),
            shQuote(filename)
        )
    }

    result <- system(cmd, intern = TRUE, ignore.stderr = TRUE)
    count <- as.integer(result[1])

    if (is.na(count)) {
        warning("Failed to count variants")
        return(0L)
    }

    count
}

#' Get variant counts per contig using bcftools
#'
#' Uses bcftools index --stats to get per-contig variant counts.
#' Requires an indexed file.
#'
#' @param filename Path to VCF/BCF file (must be indexed)
#' @return Named integer vector (names = contigs, values = variant counts)
#'
#' @examples
#' \dontrun{
#' counts <- vcf_count_per_contig("variants.vcf.gz")
#' # chr1: 12345, chr2: 23456, ...
#' }
#'
#' @export
vcf_count_per_contig <- function(filename) {
    if (!vcf_has_index(filename)) {
        stop("File must be indexed to get per-contig counts")
    }

    bcftools <- bcftools_path()
    cmd <- sprintf("%s index --stats %s", shQuote(bcftools), shQuote(filename))

    output <- system(cmd, intern = TRUE, ignore.stderr = FALSE)

    if (length(output) == 0) {
        warning("No statistics available from index")
        return(integer(0))
    }

    # Parse output: format is "chr1\t12345\t67890\t..."
    # We want the contig name (col 1) and record count (col 2)
    lines <- strsplit(output, "\t")
    contigs <- sapply(lines, `[`, 1)
    counts <- as.integer(sapply(lines, `[`, 2))

    names(counts) <- contigs
    counts
}

#' Helper to merge multiple Parquet files efficiently
#'
#' @param input_files Character vector of Parquet file paths
#' @param output_file Output Parquet file path
#' @param compression Compression codec
#' @param row_group_size Row group size
#' @noRd
merge_parquet_files <- function(
    input_files,
    output_file,
    compression,
    row_group_size
) {
    if (!requireNamespace("duckdb", quietly = TRUE)) {
        stop("Package 'duckdb' required")
    }
    if (!requireNamespace("DBI", quietly = TRUE)) {
        stop("Package 'DBI' required")
    }

    con <- duckdb::dbConnect(duckdb::duckdb())
    on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    # Build UNION ALL query for all input files
    select_clauses <- sprintf("SELECT * FROM '%s'", input_files)
    union_query <- paste(select_clauses, collapse = " UNION ALL ")

    sql <- sprintf(
        "COPY (%s) TO '%s' (FORMAT PARQUET, COMPRESSION %s, ROW_GROUP_SIZE %d)",
        union_query,
        output_file,
        compression,
        as.integer(row_group_size)
    )

    message(sprintf(
        "Merging %d parquet files into %s...",
        length(input_files),
        basename(output_file)
    ))
    DBI::dbExecute(con, sql)

    # Get total row count
    count_sql <- sprintf("SELECT COUNT(*) as n FROM '%s'", output_file)
    n_rows <- DBI::dbGetQuery(con, count_sql)$n[1]

    message(sprintf("Wrote %d total rows", n_rows))
}

#' Parallel VCF to Parquet conversion
#'
#' Processes VCF/BCF file in parallel by splitting work across chromosomes/contigs.
#' Requires an indexed file. Each thread processes a different chromosome,
#' then results are merged into a single Parquet file.
#'
#' @param input_vcf Path to input VCF/BCF file (must be indexed)
#' @param output_parquet Path for output Parquet file
#' @param threads Number of parallel threads (default: auto-detect)
#' @param compression Compression codec
#' @param row_group_size Row group size
#' @param streaming Use streaming mode
#' @param min_variants_per_contig Minimum variants to process a contig (default: 100)
#'   Contigs with fewer variants are grouped together to avoid overhead
#' @param index Optional explicit index path
#' @param ... Additional arguments passed to vcf_open_arrow
#'
#' @return Invisibly returns the output path
#'
#' @details
#' This function:
#' 1. Checks for index (required for parallel processing)
#' 2. Extracts contig names from header
#' 3. Processes each contig in parallel using multiple R processes
#' 4. Writes each contig to a temporary Parquet file
#' 5. Merges all temporary files into final output using DuckDB
#'
#' Performance scales nearly linearly with number of chromosomes (up to thread count).
#' Best for whole-genome VCFs with many chromosomes.
#'
#' @examples
#' \dontrun{
#' # Use 8 threads
#' vcf_to_parquet_parallel("wgs.vcf.gz", "wgs.parquet", threads = 8)
#'
#' # With streaming mode for large files
#' vcf_to_parquet_parallel(
#'     "huge.vcf.gz", "huge.parquet",
#'     threads = 16, streaming = TRUE
#' )
#' }
#'
#' @export
vcf_to_parquet_parallel <- function(
    input_vcf,
    output_parquet,
    threads = parallel::detectCores(),
    compression = "snappy",
    row_group_size = 100000L,
    streaming = FALSE,
    min_variants_per_contig = 100L,
    index = NULL,
    ...
) {
    if (!requireNamespace("parallel", quietly = TRUE)) {
        stop("Package 'parallel' required for parallel processing")
    }

    # Check for index using htslib (robust to remote files)
    has_idx <- vcf_has_index(input_vcf, index)

    if (!has_idx) {
        warning("No index found. Falling back to single-threaded mode.")
        return(vcf_to_parquet(
            input_vcf,
            output_parquet,
            compression = compression,
            row_group_size = row_group_size,
            streaming = streaming,
            ...
        ))
    }

    # Get list of contigs from header
    contigs <- vcf_get_contigs(input_vcf)

    if (length(contigs) == 0) {
        stop("No contigs found in VCF header")
    }

    # Get per-contig variant counts to optimize work distribution
    contig_counts <- tryCatch(
        vcf_count_per_contig(input_vcf),
        error = function(e) {
            # Fallback: assume equal distribution
            rep(1000L, length(contigs))
        }
    )

    # Filter out tiny contigs and group them
    large_contigs <- contigs[contig_counts >= min_variants_per_contig]
    small_contigs <- contigs[contig_counts < min_variants_per_contig]

    # Prepare work units
    work_units <- as.list(large_contigs)

    # Group small contigs together
    if (length(small_contigs) > 0) {
        work_units <- c(work_units, list(small_contigs))
    }

    if (length(work_units) == 0) {
        stop("No contigs to process")
    }

    # Limit threads to number of work units
    threads <- min(threads, length(work_units))

    message(sprintf(
        "Processing %d contigs (%d large, %d small grouped) using %d threads",
        length(contigs),
        length(large_contigs),
        length(small_contigs),
        threads
    ))

    # Create temporary directory for per-contig parquet files
    temp_dir <- tempfile("vcf_parallel_")
    dir.create(temp_dir, recursive = TRUE)
    on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

    # Map compression name
    duckdb_compression <- toupper(compression)
    if (duckdb_compression == "LZ4") {
        duckdb_compression <- "LZ4_RAW"
    }

    # Process work units in parallel
    process_unit <- function(i) {
        unit <- work_units[[i]]
        temp_file <- file.path(temp_dir, sprintf("chunk_%04d.parquet", i))

        tryCatch(
            {
                if (length(unit) == 1) {
                    # Single contig
                    region <- unit
                    message(sprintf(
                        "[Thread %d] Processing contig: %s",
                        i,
                        region
                    ))
                } else {
                    # Multiple small contigs - process separately and combine
                    region <- NULL
                    message(sprintf(
                        "[Thread %d] Processing %d small contigs",
                        i,
                        length(unit)
                    ))
                }

                # Process this region
                if (streaming) {
                    vcf_to_parquet_streaming(
                        input_vcf,
                        temp_file,
                        duckdb_compression,
                        row_group_size,
                        region = if (length(unit) == 1) unit else NULL,
                        index = index,
                        ...
                    )
                } else {
                    vcf_to_parquet_inmemory(
                        input_vcf,
                        temp_file,
                        duckdb_compression,
                        row_group_size,
                        region = if (length(unit) == 1) unit else NULL,
                        index = index,
                        ...
                    )
                }

                # For multiple small contigs, process each and merge
                if (length(unit) > 1) {
                    small_files <- lapply(seq_along(unit), function(j) {
                        small_file <- file.path(
                            temp_dir,
                            sprintf("small_%04d_%04d.parquet", i, j)
                        )
                        if (streaming) {
                            vcf_to_parquet_streaming(
                                input_vcf,
                                small_file,
                                duckdb_compression,
                                row_group_size,
                                region = unit[j],
                                index = index,
                                ...
                            )
                        } else {
                            vcf_to_parquet_inmemory(
                                input_vcf,
                                small_file,
                                duckdb_compression,
                                row_group_size,
                                region = unit[j],
                                index = index,
                                ...
                            )
                        }
                        small_file
                    })
                    # Merge small files into temp_file
                    merge_parquet_files(
                        unlist(small_files),
                        temp_file,
                        duckdb_compression,
                        row_group_size
                    )
                }

                temp_file
            },
            error = function(e) {
                warning(sprintf(
                    "[Thread %d] Failed to process work unit: %s",
                    i,
                    e$message
                ))
                NULL
            }
        )
    }

    # Run in parallel
    if (.Platform$OS.type == "windows") {
        # Use parLapply for Windows
        cl <- parallel::makeCluster(threads)
        on.exit(parallel::stopCluster(cl), add = TRUE)
        parallel::clusterEvalQ(cl, library(RBCFTools))
        temp_files <- parallel::parLapply(
            cl,
            seq_along(work_units),
            process_unit
        )
    } else {
        # Use mclapply for Unix/Mac
        temp_files <- parallel::mclapply(
            seq_along(work_units),
            process_unit,
            mc.cores = threads
        )
    }

    # Filter out failed chunks
    temp_files <- Filter(Negate(is.null), temp_files)
    temp_files <- unlist(temp_files)
    temp_files <- temp_files[file.exists(temp_files)]

    if (length(temp_files) == 0) {
        stop("Failed to process any contigs")
    }

    # Merge all temporary parquet files
    merge_parquet_files(
        temp_files,
        output_parquet,
        duckdb_compression,
        row_group_size
    )

    invisible(output_parquet)
}
