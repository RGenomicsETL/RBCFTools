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
#'     query = "SELECT COUNT(*) FROM bcf_read('{file}')"
#' )
#'
#' # Filter by chromosome
#' vcf_query_duckdb("variants.vcf.gz", ext_path,
#'     query = "SELECT CHROM, POS, REF, ALT FROM bcf_read('{file}') WHERE CHROM = '22'"
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
  # Validate file
  if (!file.exists(file)) {
    stop("File not found: ", file, call. = FALSE)
  }
  file <- normalizePath(file, mustWork = TRUE)

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
    # Replace {file} placeholder with actual bcf_read() call
    sql <- gsub("\\{file\\}", file, query, fixed = FALSE)
    sql <- gsub("bcf_read\\s*\\(\\s*'[^']*'\\s*\\)", bcf_read_call, sql)
    # If query doesn't contain bcf_read, assume it's a simple query and wrap it
    if (!grepl("bcf_read", sql, ignore.case = TRUE)) {
      sql <- sprintf("SELECT %s FROM %s", query, bcf_read_call)
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
  if (!file.exists(file)) {
    stop("File not found: ", file, call. = FALSE)
  }
  file <- normalizePath(file, mustWork = TRUE)

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
#'     columns = c("CHROM", "POS", "REF", "ALT", "INFO_AF")
#' )
#'
#' # Export a region
#' vcf_to_parquet_duckdb("variants.vcf.gz", "chr22.parquet", ext_path,
#'     region = "chr22"
#' )
#' }
vcf_to_parquet_duckdb <- function(
  input_file,
  output_file,
  extension_path = NULL,
  columns = NULL,
  region = NULL,
  compression = "zstd",
  con = NULL
) {
  if (!file.exists(input_file)) {
    stop("Input file not found: ", input_file, call. = FALSE)
  }
  if (is.null(con) && is.null(extension_path)) {
    stop("Either extension_path or con must be provided", call. = FALSE)
  }

  input_file <- normalizePath(input_file, mustWork = TRUE)
  output_file <- normalizePath(output_file, mustWork = FALSE)

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

  # Build COPY statement
  sql <- sprintf(
    "COPY (SELECT %s FROM %s) TO '%s' (FORMAT PARQUET, COMPRESSION '%s')",
    select_clause,
    bcf_read_call,
    output_file,
    compression
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

  file <- normalizePath(file, mustWork = TRUE)

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
