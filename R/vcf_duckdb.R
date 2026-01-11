#' DuckDB VCF/BCF Query Utilities
#'
#' Functions for querying VCF/BCF files using DuckDB with the bcf_reader extension.
#'
#' @name vcf_duckdb
#' @rdname vcf_duckdb
NULL

# -----------------------------------------------------------------------------
# Extension Build and Installation Utilities
# -----------------------------------------------------------------------------

#' Get the source directory for bcf_reader extension in the package
#'
#' @return Character string with the path to the extension source directory
#' @keywords internal
bcf_reader_source_dir <- function() {
  src_dir <- system.file(
    "duckdb_bcf_reader_extension",
    package = "RBCFTools",
    mustWork = FALSE
  )

  if (!nzchar(src_dir) || !dir.exists(src_dir)) {
    stop("bcf_reader extension source not found in package", call. = FALSE)
  }

  src_dir
}

#' Copy bcf_reader extension source to a build directory
#'
#' Copies the extension source files from the package to a specified directory
#' for building. This is necessary because the installed package directory
#' is typically read-only.
#'
#' @param dest_dir Directory where to copy the source files.
#' @return Invisible path to the destination directory
#' @export
#' @examples
#' \dontrun{
#' # Copy to temp directory
#' build_dir <- bcf_reader_copy_source(tempdir())
#'
#' # Copy to a specific location
#' build_dir <- bcf_reader_copy_source("/tmp/bcf_reader_build")
#' }
bcf_reader_copy_source <- function(dest_dir) {
  if (missing(dest_dir) || is.null(dest_dir)) {
    stop("dest_dir must be specified", call. = FALSE)
  }

  src_dir <- bcf_reader_source_dir()

  # Create destination directory
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Copy all source files
  files_to_copy <- c(
    "bcf_reader.c",
    "vcf_types.h",
    "vep_parser.c",
    "vep_parser.h",
    "duckdb_extension.h",
    "Makefile",
    "append_metadata.sh"
  )

  for (f in files_to_copy) {
    src_file <- file.path(src_dir, f)
    if (file.exists(src_file)) {
      file.copy(src_file, file.path(dest_dir, f), overwrite = TRUE)
    }
  }

  # Make append_metadata.sh executable
  metadata_script <- file.path(dest_dir, "append_metadata.sh")
  if (file.exists(metadata_script)) {
    Sys.chmod(metadata_script, mode = "0755")
  }

  # Also copy duckdb.h if it exists
  duckdb_h <- file.path(src_dir, "duckdb.h")
  if (file.exists(duckdb_h)) {
    file.copy(duckdb_h, file.path(dest_dir, "duckdb.h"), overwrite = TRUE)
  }

  invisible(dest_dir)
}

#' Build the bcf_reader DuckDB extension
#'
#' Compiles the bcf_reader extension from source using the package's htslib.
#' Source files are copied to the build directory first.
#'
#' @param build_dir Directory where to build the extension. Source files will
#'   be copied here and the extension will be built in `build_dir/build/`.
#' @param force Logical, force rebuild even if extension exists
#' @param verbose Logical, show build output
#' @return Path to the built extension file
#' @export
#' @examples
#' \dontrun{
#' # Build in temp directory
#' ext_path <- bcf_reader_build(tempdir())
#'
#' # Build in a specific location
#' ext_path <- bcf_reader_build("/tmp/bcf_reader")
#'
#' # Force rebuild
#' ext_path <- bcf_reader_build("/tmp/bcf_reader", force = TRUE)
#' }
bcf_reader_build <- function(build_dir, force = FALSE, verbose = TRUE) {
  if (missing(build_dir) || is.null(build_dir)) {
    stop("build_dir must be specified", call. = FALSE)
  }

  # Expected output path
  output_dir <- file.path(build_dir, "build")
  ext_path <- file.path(output_dir, "bcf_reader.duckdb_extension")

  # Check if already built
  if (!force && file.exists(ext_path)) {
    if (verbose) {
      message("bcf_reader extension already exists at: ", ext_path)
    }
    if (verbose) {
      message("Use force=TRUE to rebuild.")
    }
    return(ext_path)
  }

  if (verbose) {
    message("Building bcf_reader extension...")
    message("  Build directory: ", build_dir)
  }

  # Copy source files to build directory
  bcf_reader_copy_source(build_dir)

  # Get htslib paths from this package
  hts_include <- htslib_include_dir()
  hts_lib <- htslib_lib_dir()

  if (verbose) {
    message("  Using htslib from: ", hts_lib)
  }

  # Build command - pass htslib paths explicitly to make
  # USE_DEFLATE=1 is needed if htslib was built with libdeflate support
  make_cmd <- sprintf(
    "make -C '%s' clean && make -C '%s' HTSLIB_INCLUDE='%s' HTSLIB_LIB='%s' USE_DEFLATE=1",
    build_dir,
    build_dir,
    hts_include,
    hts_lib
  )

  if (verbose) {
    message("  Running: make with explicit htslib paths")
  }

  # Run make
  result <- system(make_cmd, intern = !verbose, ignore.stdout = !verbose)

  if (!is.null(attr(result, "status")) && attr(result, "status") != 0) {
    stop(
      "Failed to build bcf_reader extension. Check compiler output.",
      call. = FALSE
    )
  }

  # Verify extension was built
  if (!file.exists(ext_path)) {
    stop(
      "Build completed but extension file not found at: ",
      ext_path,
      call. = FALSE
    )
  }

  if (verbose) {
    message("Extension built: ", ext_path)
  }

  ext_path
}

#' Setup DuckDB connection with bcf_reader extension loaded
#'
#' Creates a DuckDB connection and loads the bcf_reader extension for VCF/BCF queries.
#'
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#'   Must be explicitly provided.
#' @param dbdir Database directory. Default ":memory:" for in-memory database.
#' @param read_only Logical, whether to open in read-only mode. Default FALSE.
#' @param config Named list of DuckDB configuration options.
#'
#' @return A DuckDB connection object with bcf_reader extension loaded
#' @export
#' @examples
#' \dontrun{
#' # First build the extension
#' ext_path <- bcf_reader_build(tempdir())
#'
#' # Then connect
#' con <- vcf_duckdb_connect(ext_path)
#' DBI::dbGetQuery(con, "SELECT * FROM bcf_read('variants.vcf.gz') LIMIT 10")
#' DBI::dbDisconnect(con)
#' }
vcf_duckdb_connect <- function(
  extension_path,
  dbdir = ":memory:",
  read_only = FALSE,
  config = list()
) {
  if (missing(extension_path) || is.null(extension_path)) {
    stop(
      "extension_path must be specified. Use bcf_reader_build() to build the extension first.",
      call. = FALSE
    )
  }

  if (!file.exists(extension_path)) {
    stop(
      "Extension not found at: ",
      extension_path,
      "\n",
      "Use bcf_reader_build() to build the extension first.",
      call. = FALSE
    )
  }

  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop(
      "Package 'duckdb' is required. Install with: install.packages('duckdb')",
      call. = FALSE
    )
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop(
      "Package 'DBI' is required. Install with: install.packages('DBI')",
      call. = FALSE
    )
  }

  # Setup HTS_PATH for remote file access (S3, GCS, HTTP)
  # This must be set before htslib opens any files
  setup_hts_env()

  # Enable unsigned extensions
  config$allow_unsigned_extensions <- "true"

  # Create connection
  drv <- duckdb::duckdb(dbdir = dbdir, read_only = read_only, config = config)
  con <- DBI::dbConnect(drv)

  # Load extension
  load_sql <- sprintf("LOAD '%s'", extension_path)
  tryCatch(
    DBI::dbExecute(con, load_sql),
    error = function(e) {
      DBI::dbDisconnect(con)
      stop(
        "Failed to load bcf_reader extension: ",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )

  con
}

#' Query a VCF/BCF file using DuckDB SQL
#'
#' Execute a SQL query against a VCF/BCF file using the bcf_reader extension.
#' The file is exposed as a table via the `bcf_read()` function.
#'
#' @param file Path to VCF, VCF.GZ, or BCF file
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param query SQL query string. Use `bcf_read('{file}')` to reference the file,
#'   or if NULL, returns all rows with `SELECT * FROM bcf_read('{file}')`.
#' @param region Optional genomic region for indexed files (e.g., "chr1:1000-2000")
#' @param con Optional existing DuckDB connection (with extension already loaded).
#'   If provided, extension_path is ignored.
#'
#' @return A data.frame with query results
#' @export
#' @examples
#' \dontrun{
#' # First build the extension
#' ext_path <- bcf_reader_build(tempdir())
#'
#' # Basic query - get all variants
#' vcf_query_duckdb("variants.vcf.gz", ext_path)
#'
#' # Count variants
#' vcf_query_duckdb("variants.vcf.gz", ext_path,
#'   query = "SELECT COUNT(*) FROM bcf_read('{file}')"
#' )
#'
#' # Filter by chromosome
#' vcf_query_duckdb("variants.vcf.gz", ext_path,
#'   query = "SELECT CHROM, POS, REF, ALT FROM bcf_read('{file}') WHERE CHROM = '22'"
#' )
#'
#' # Region query (requires index)
#' vcf_query_duckdb("variants.vcf.gz", ext_path, region = "chr1:1000000-2000000")
#'
#' # Reuse connection for multiple queries
#' con <- vcf_duckdb_connect(ext_path)
#' vcf_query_duckdb("file1.vcf.gz", con = con)
#' vcf_query_duckdb("file2.vcf.gz", con = con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
#' }
vcf_query_duckdb <- function(
  file,
  extension_path = NULL,
  query = NULL,
  region = NULL,
  con = NULL
) {
  # Check if file is a remote URL
  is_remote <- grepl("^(s3|gs|http|https|ftp)://", file, ignore.case = TRUE)

  if (!is_remote) {
    # Validate local file
    if (!file.exists(file)) {
      stop("File not found: ", file, call. = FALSE)
    }
    file <- normalizePath(file, mustWork = TRUE)
  }

  # Need either extension_path or con
  if (is.null(con) && is.null(extension_path)) {
    stop("Either extension_path or con must be provided", call. = FALSE)
  }

  # Build bcf_read() call
  if (!is.null(region) && nzchar(region)) {
    bcf_read_call <- sprintf("bcf_read('%s', region := '%s')", file, region)
  } else {
    bcf_read_call <- sprintf("bcf_read('%s')", file)
  }

  # Build query
  if (is.null(query)) {
    sql <- sprintf("SELECT * FROM %s", bcf_read_call)
  } else {
    # Replace {file} and {region} placeholders
    sql <- gsub("\\{file\\}", file, query, fixed = FALSE)
    if (!is.null(region) && nzchar(region)) {
      sql <- gsub("\\{region\\}", region, sql, fixed = FALSE)
    }
    # Replace bcf_read() calls (with or without region parameter) with the proper call
    sql <- gsub("bcf_read\\s*\\([^)]*\\)", bcf_read_call, sql)
    # If query doesn't contain bcf_read, handle it appropriately
    if (!grepl("bcf_read", sql, ignore.case = TRUE)) {
      # If query contains "FROM vcf", replace "vcf" with the bcf_read call
      if (grepl("\\bFROM\\s+vcf\\b", sql, ignore.case = TRUE)) {
        sql <- gsub(
          "\\bFROM\\s+vcf\\b",
          paste0("FROM ", bcf_read_call),
          sql,
          ignore.case = TRUE
        )
      } else {
        # Assume it's just column names/expressions and wrap it
        sql <- sprintf("SELECT %s FROM %s", query, bcf_read_call)
      }
    }
  }

  # Use provided connection or create temporary one
  own_con <- is.null(con)
  if (own_con) {
    con <- vcf_duckdb_connect(extension_path)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  }

  DBI::dbGetQuery(con, sql)
}

#' Count variants in a VCF/BCF file
#'
#' Fast variant count using DuckDB projection pushdown.
#'
#' @param file Path to VCF, VCF.GZ, or BCF file
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param region Optional genomic region for indexed files
#' @param con Optional existing DuckDB connection (with extension loaded).
#'
#' @return Integer count of variants
#' @export
#' @examples
#' \dontrun{
#' ext_path <- bcf_reader_build(tempdir())
#' vcf_count_duckdb("variants.vcf.gz", ext_path)
#' vcf_count_duckdb("variants.vcf.gz", ext_path, region = "chr22")
#' }
vcf_count_duckdb <- function(
  file,
  extension_path = NULL,
  region = NULL,
  con = NULL
) {
  result <- vcf_query_duckdb(
    file,
    extension_path = extension_path,
    query = "SELECT COUNT(*) as n FROM bcf_read('{file}')",
    region = region,
    con = con
  )
  as.integer(result$n)
}

#' Get VCF/BCF schema using DuckDB
#'
#' Returns the column names and types for a VCF/BCF file as seen by DuckDB.
#'
#' @param file Path to VCF, VCF.GZ, or BCF file
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param con Optional existing DuckDB connection (with extension loaded).
#'
#' @return A data.frame with column_name and column_type
#' @export
#' @examples
#' \dontrun{
#' ext_path <- bcf_reader_build(tempdir())
#' vcf_schema_duckdb("variants.vcf.gz", ext_path)
#' }
vcf_schema_duckdb <- function(file, extension_path = NULL, con = NULL) {
  # Check if file is a remote URL
  is_remote <- grepl("^(s3|gs|http|https|ftp)://", file, ignore.case = TRUE)

  if (!is_remote) {
    if (!file.exists(file)) {
      stop("File not found: ", file, call. = FALSE)
    }
    file <- normalizePath(file, mustWork = TRUE)
  }

  if (is.null(con) && is.null(extension_path)) {
    stop("Either extension_path or con must be provided", call. = FALSE)
  }

  own_con <- is.null(con)
  if (own_con) {
    con <- vcf_duckdb_connect(extension_path)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  }

  # Create a view and describe it
  sql <- sprintf("SELECT * FROM bcf_read('%s') LIMIT 0", file)
  result <- DBI::dbGetQuery(con, sql)

  data.frame(
    column_name = names(result),
    column_type = vapply(result, function(x) class(x)[1], character(1)),
    stringsAsFactors = FALSE
  )
}

#' Export VCF/BCF to Parquet using DuckDB
#'
#' Convert a VCF/BCF file to Parquet format for fast subsequent queries.
#'
#' @param input_file Path to input VCF, VCF.GZ, or BCF file
#' @param output_file Path to output Parquet file
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param columns Optional character vector of columns to include. NULL for all.
#' @param region Optional genomic region to export (requires index)
#' @param compression Parquet compression: "snappy", "zstd", "gzip", or "none"
#' @param row_group_size Number of rows per row group (default: 100000)
#' @param threads Number of parallel threads for processing (default: 1).
#'   When threads > 1 and file is indexed, uses parallel processing by splitting
#'   work across chromosomes/contigs. See \code{\link{vcf_to_parquet_duckdb_parallel}}.
#' @param con Optional existing DuckDB connection (with extension loaded).
#'
#' @return Invisible path to output file
#' @export
#' @examples
#' \dontrun{
#' ext_path <- bcf_reader_build(tempdir())
#'
#' # Export entire file
#' vcf_to_parquet_duckdb("variants.vcf.gz", "variants.parquet", ext_path)
#'
#' # Export specific columns
#' vcf_to_parquet_duckdb("variants.vcf.gz", "variants_slim.parquet", ext_path,
#'   columns = c("CHROM", "POS", "REF", "ALT", "INFO_AF")
#' )
#'
#' # Export a region
#' vcf_to_parquet_duckdb("variants.vcf.gz", "chr22.parquet", ext_path,
#'   region = "chr22"
#' )
#'
#' # Parallel mode for whole-genome VCF (requires index)
#' vcf_to_parquet_duckdb("wgs.vcf.gz", "wgs.parquet", ext_path, threads = 8)
#' }
vcf_to_parquet_duckdb <- function(
  input_file,
  output_file,
  extension_path = NULL,
  columns = NULL,
  region = NULL,
  compression = "zstd",
  row_group_size = 100000L,
  threads = 1L,
  con = NULL
) {
  # Check if file is a remote URL
  is_remote <- grepl(
    "^(s3|gs|http|https|ftp)://",
    input_file,
    ignore.case = TRUE
  )

  if (!is_remote) {
    if (!file.exists(input_file)) {
      stop("Input file not found: ", input_file, call. = FALSE)
    }
    input_file <- normalizePath(input_file, mustWork = TRUE)
  }

  if (is.null(con) && is.null(extension_path)) {
    stop("Either extension_path or con must be provided", call. = FALSE)
  }

  output_file <- normalizePath(output_file, mustWork = FALSE)

  # Use parallel processing if threads > 1
  if (threads > 1) {
    return(vcf_to_parquet_duckdb_parallel(
      input_file = input_file,
      output_file = output_file,
      extension_path = extension_path,
      threads = threads,
      compression = compression,
      row_group_size = row_group_size,
      columns = columns,
      con = con
    ))
  }

  # Build select clause
  select_clause <- if (is.null(columns)) {
    "*"
  } else {
    paste(columns, collapse = ", ")
  }

  # Build bcf_read call
  if (!is.null(region) && nzchar(region)) {
    bcf_read_call <- sprintf(
      "bcf_read('%s', region := '%s')",
      input_file,
      region
    )
  } else {
    bcf_read_call <- sprintf("bcf_read('%s')", input_file)
  }

  # Map compression name to DuckDB format
  duckdb_compression <- toupper(compression)

  # Build COPY statement with row_group_size
  sql <- sprintf(
    "COPY (SELECT %s FROM %s) TO '%s' (FORMAT PARQUET, COMPRESSION '%s', ROW_GROUP_SIZE %d)",
    select_clause,
    bcf_read_call,
    output_file,
    duckdb_compression,
    as.integer(row_group_size)
  )

  own_con <- is.null(con)
  if (own_con) {
    con <- vcf_duckdb_connect(extension_path)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  }

  DBI::dbExecute(con, sql)
  message("Wrote: ", output_file)
  invisible(output_file)
}

#' List samples in a VCF/BCF file using DuckDB
#'
#' Extract sample names from FORMAT column names.
#'
#' @param file Path to VCF, VCF.GZ, or BCF file
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param con Optional existing DuckDB connection (with extension loaded).
#'
#' @return Character vector of sample names
#' @export
#' @examples
#' \dontrun{
#' ext_path <- bcf_reader_build(tempdir())
#' vcf_samples_duckdb("variants.vcf.gz", ext_path)
#' }
vcf_samples_duckdb <- function(file, extension_path = NULL, con = NULL) {
  schema <- vcf_schema_duckdb(file, extension_path = extension_path, con = con)

  # Extract sample names from FORMAT_GT_<sample> columns
  gt_cols <- grep("^FORMAT_GT_", schema$column_name, value = TRUE)

  if (length(gt_cols) == 0) {
    return(character(0))
  }

  # Remove FORMAT_GT_ prefix
  sub("^FORMAT_GT_", "", gt_cols)
}

#' Summary statistics for a VCF/BCF file using DuckDB
#'
#' Get summary statistics including variant counts per chromosome.
#'
#' @param file Path to VCF, VCF.GZ, or BCF file
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param con Optional existing DuckDB connection (with extension loaded).
#'
#' @return A list with total_variants, n_samples, and variants_per_chrom
#' @export
#' @examples
#' \dontrun{
#' ext_path <- bcf_reader_build(tempdir())
#' vcf_summary_duckdb("variants.vcf.gz", ext_path)
#' }
vcf_summary_duckdb <- function(file, extension_path = NULL, con = NULL) {
  if (is.null(con) && is.null(extension_path)) {
    stop("Either extension_path or con must be provided", call. = FALSE)
  }

  own_con <- is.null(con)
  if (own_con) {
    con <- vcf_duckdb_connect(extension_path)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  }

  # Check if file is a remote URL
  is_remote <- grepl("^(s3|gs|http|https|ftp)://", file, ignore.case = TRUE)
  if (!is_remote) {
    file <- normalizePath(file, mustWork = TRUE)
  }

  # Get counts per chromosome
  per_chrom <- vcf_query_duckdb(
    file,
    query = "SELECT CHROM, COUNT(*) as n FROM bcf_read('{file}') GROUP BY CHROM ORDER BY n DESC",
    con = con
  )

  # Get samples
  samples <- vcf_samples_duckdb(file, con = con)

  list(
    total_variants = sum(per_chrom$n),
    n_samples = length(samples),
    samples = samples,
    variants_per_chrom = per_chrom
  )
}

#' Parallel VCF to Parquet conversion using DuckDB
#'
#' Processes VCF/BCF file in parallel by splitting work across chromosomes/contigs
#' using the DuckDB bcf_reader extension. Requires an indexed file. Each thread
#' processes a different chromosome, then results are merged into a single Parquet file.
#'
#' @param input_file Path to input VCF/BCF file (must be indexed)
#' @param output_file Path for output Parquet file
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param threads Number of parallel threads (default: auto-detect)
#' @param compression Parquet compression codec
#' @param row_group_size Row group size
#' @param columns Optional character vector of columns to include
#' @param con Optional existing DuckDB connection (with extension loaded).
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
#' ext_path <- bcf_reader_build(tempdir())
#'
#' # Use 8 threads
#' vcf_to_parquet_duckdb_parallel("wgs.vcf.gz", "wgs.parquet", ext_path, threads = 8)
#'
#' # With specific columns
#' vcf_to_parquet_duckdb_parallel(
#'   "wgs.vcf.gz", "wgs.parquet", ext_path,
#'   threads = 16,
#'   columns = c("CHROM", "POS", "REF", "ALT")
#' )
#' }
#'
#' @seealso \code{\link{vcf_to_parquet_duckdb}} for single-threaded conversion
#'
#' @export
vcf_to_parquet_duckdb_parallel <- function(
  input_file,
  output_file,
  extension_path = NULL,
  threads = parallel::detectCores(),
  compression = "zstd",
  row_group_size = 100000L,
  columns = NULL,
  con = NULL
) {
  if (!requireNamespace("parallel", quietly = TRUE)) {
    stop("Package 'parallel' required for parallel processing")
  }

  # Check that we have extension_path for workers (con won't work across processes)
  if (is.null(extension_path)) {
    if (!is.null(con)) {
      stop(
        "Parallel processing requires extension_path parameter. ",
        "Shared connections cannot be used across processes.",
        call. = FALSE
      )
    }
    stop(
      "extension_path must be provided for parallel processing",
      call. = FALSE
    )
  }

  # Check if file is a remote URL
  is_remote <- grepl(
    "^(s3|gs|http|https|ftp)://",
    input_file,
    ignore.case = TRUE
  )
  if (!is_remote) {
    input_file <- normalizePath(input_file, mustWork = TRUE)
  }
  output_file <- normalizePath(output_file, mustWork = FALSE)

  # Check for index
  has_idx <- vcf_has_index(input_file)
  if (!has_idx) {
    warning("No index found. Falling back to single-threaded mode.")
    return(vcf_to_parquet_duckdb(
      input_file = input_file,
      output_file = output_file,
      extension_path = extension_path,
      columns = columns,
      compression = compression,
      row_group_size = row_group_size,
      threads = 1
    ))
  }

  # Get contigs from header
  all_contigs <- vcf_get_contigs(input_file)
  if (length(all_contigs) == 0) {
    stop("No contigs found in VCF header")
  }

  # Filter to only contigs with variants (use vcf_count_per_contig)
  contig_counts <- vcf_count_per_contig(input_file)
  contigs_with_data <- names(contig_counts)[contig_counts > 0]

  if (length(contigs_with_data) == 0) {
    stop("No contigs have variants")
  }

  contigs <- contigs_with_data

  # Limit threads to number of contigs
  threads <- min(threads, length(contigs))

  message(sprintf(
    "Processing %d contigs (out of %d in header) using %d threads (DuckDB mode)",
    length(contigs),
    length(all_contigs),
    threads
  ))

  # If only 1 contig or 1 thread, use single-threaded mode
  if (length(contigs) == 1 || threads == 1) {
    return(vcf_to_parquet_duckdb(
      input_file = input_file,
      output_file = output_file,
      extension_path = extension_path,
      columns = columns,
      compression = compression,
      row_group_size = row_group_size,
      threads = 1
    ))
  }

  # Create temp directory for per-contig files
  temp_dir <- tempfile("vcf_duckdb_parallel_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  # Map compression name
  duckdb_compression <- toupper(compression)

  # Process each contig
  process_contig <- function(
    i,
    vcf_file,
    out_dir,
    contigs_list,
    ext_path,
    compression_codec,
    rg_size,
    cols
  ) {
    contig <- contigs_list[i]
    temp_file <- file.path(out_dir, sprintf("contig_%04d.parquet", i))

    tryCatch(
      {
        # Process this contig using vcf_to_parquet_duckdb
        vcf_to_parquet_duckdb(
          input_file = vcf_file,
          output_file = temp_file,
          extension_path = ext_path,
          columns = cols,
          region = contig,
          compression = compression_codec,
          row_group_size = rg_size,
          threads = 1
        )

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
      vcf_file = input_file,
      out_dir = temp_dir,
      contigs_list = contigs,
      ext_path = extension_path,
      compression_codec = compression,
      rg_size = row_group_size,
      cols = columns
    )
  } else {
    temp_files <- parallel::mclapply(
      seq_along(contigs),
      process_contig,
      vcf_file = input_file,
      out_dir = temp_dir,
      contigs_list = contigs,
      ext_path = extension_path,
      compression_codec = compression,
      rg_size = row_group_size,
      cols = columns,
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

  # Merge all temp files using DuckDB
  message("Merging temporary Parquet files... to ", output_file)
  merge_parquet_files(
    temp_files,
    output_file,
    duckdb_compression,
    row_group_size
  )

  invisible(output_file)
}
