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

  # Parse output: format is "CHROM\tLENGTH\tN_RECORDS"
  # We want the contig name (col 1) and record count (col 3)
  # Note: LENGTH can be "." if not in header
  # Use suppressWarnings to avoid NA coercion warnings from malformed lines
  lines <- strsplit(output, "\t")
  contigs <- sapply(lines, function(x) {
    if (length(x) >= 1) x[1] else NA_character_
  })
  counts <- suppressWarnings(as.integer(sapply(lines, function(x) {
    if (length(x) >= 3) x[3] else NA_character_
  })))

  # Keep only valid entries
  valid <- !is.na(contigs) & !is.na(counts)
  if (!any(valid)) {
    warning("Could not parse variant counts from bcftools index")
    return(integer(0))
  }

  contigs <- contigs[valid]
  counts <- counts[valid]

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

  # Suppress messages during merge to avoid worker process I/O conflicts
  suppressMessages({
    DBI::dbExecute(con, sql)
  })

  # Get total row count
  count_sql <- sprintf("SELECT COUNT(*) as n FROM '%s'", output_file)
  n_rows <- DBI::dbGetQuery(con, count_sql)$n[1]

  message(sprintf(
    "Merged %d parquet files -> %s (%d rows)",
    length(input_files),
    basename(output_file),
    n_rows
  ))
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
#' Contigs that return no variants are skipped automatically.
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
  compression = "zstd",
  row_group_size = 100000L,
  streaming = FALSE,
  index = NULL,
  ...
) {
  if (!requireNamespace("parallel", quietly = TRUE)) {
    stop("Package 'parallel' required for parallel processing")
  }

  # Check for index
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

  # Get contigs from header
  contigs <- vcf_get_contigs(input_vcf)
  if (length(contigs) == 0) {
    stop("No contigs found in VCF header")
  }

  # Limit threads to number of contigs
  threads <- min(threads, length(contigs))

  message(sprintf(
    "Processing %d contigs using %d threads",
    length(contigs),
    threads
  ))

  # If only 1 contig or 1 thread, use single-threaded mode
  if (length(contigs) == 1 || threads == 1) {
    return(vcf_to_parquet(
      input_vcf,
      output_parquet,
      compression = compression,
      row_group_size = row_group_size,
      streaming = streaming,
      threads = 1,
      index = index,
      ...
    ))
  }

  # Create temp directory for per-contig files
  temp_dir <- tempfile("vcf_parallel_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  # Map compression name
  duckdb_compression <- toupper(compression)
  if (duckdb_compression == "LZ4") {
    duckdb_compression <- "LZ4_RAW"
  }

  # Capture additional arguments
  extra_args <- list(...)

  # Process each contig
  process_contig <- function(
    i,
    vcf_file,
    out_dir,
    contigs_list,
    use_streaming,
    compression_codec,
    rg_size,
    idx,
    args_list
  ) {
    contig <- contigs_list[i]
    temp_file <- file.path(out_dir, sprintf("contig_%04d.parquet", i))

    tryCatch(
      {
        # Filter args - only keep those supported by vcf_open_arrow
        supported_args <- c("samples", "include_info", "include_format")
        filtered_args <- args_list[names(args_list) %in% supported_args]

        # Build arguments list
        call_args <- c(
          list(
            input_vcf = vcf_file,
            output_parquet = temp_file,
            duckdb_compression = compression_codec,
            row_group_size = rg_size,
            region = contig,
            index = idx
          ),
          filtered_args
        )

        # Process this contig
        if (use_streaming) {
          do.call(vcf_to_parquet_streaming, call_args)
        } else {
          do.call(vcf_to_parquet_inmemory, call_args)
        }

        # Return temp file path only if it exists and has content
        if (file.exists(temp_file) && file.size(temp_file) > 0) {
          return(temp_file)
        }
        return(NULL)
      },
      error = function(e) {
        # Silently skip failed contigs
        return(NULL)
      }
    )
  }

  # Run in parallel
  if (.Platform$OS.type == "windows") {
    cl <- parallel::makeCluster(threads)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterEvalQ(cl, library(RBCFTools))
    temp_files <- parallel::parLapply(
      cl,
      seq_along(contigs),
      process_contig,
      vcf_file = input_vcf,
      out_dir = temp_dir,
      contigs_list = contigs,
      use_streaming = streaming,
      compression_codec = duckdb_compression,
      rg_size = row_group_size,
      idx = index,
      args_list = extra_args
    )
  } else {
    temp_files <- parallel::mclapply(
      seq_along(contigs),
      process_contig,
      vcf_file = input_vcf,
      out_dir = temp_dir,
      contigs_list = contigs,
      use_streaming = streaming,
      compression_codec = duckdb_compression,
      rg_size = row_group_size,
      idx = index,
      args_list = extra_args,
      mc.cores = threads
    )
  }

  # Filter out NULLs and keep only successful file paths
  temp_files <- Filter(Negate(is.null), temp_files)
  temp_files <- unlist(temp_files, use.names = FALSE)
  temp_files <- as.character(temp_files)

  # Keep files that exist and have content
  if (length(temp_files) > 0) {
    temp_files <- temp_files[
      nzchar(temp_files) &
        file.exists(temp_files) &
        file.size(temp_files) > 0
    ]
  }

  if (length(temp_files) == 0) {
    stop("No variants found in any contig")
  }

  # Merge all temp files
  message("Merging temporary Parquet files... to ", output_parquet)
  merge_parquet_files(
    temp_files,
    output_parquet,
    duckdb_compression,
    row_group_size
  )

  invisible(output_parquet)
}
