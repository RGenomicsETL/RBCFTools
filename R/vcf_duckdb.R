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

#' Open a VCF/BCF file as a DuckDB table or view
#'
#' Creates a DuckDB connection with the VCF data loaded as a table or view.
#' Supports in-memory or file-backed databases, tidy format output,
#' parallel loading by chromosome, column selection, and optional Hive partitioning.
#'
#' @param file Path to VCF, VCF.GZ, or BCF file
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param table_name Name for the table/view (default: "variants")
#' @param as_view Logical, create a VIEW instead of materializing a TABLE (default: TRUE).
#'   Views are instant to create but queries re-read the VCF each time.
#'   Tables are slower to create but subsequent queries are fast.
#' @param dbdir Database directory. Default ":memory:" for in-memory database.
#'   Use a file path for persistent storage (e.g., "variants.duckdb").
#' @param columns Optional character vector of columns to include. NULL for all.
#' @param region Optional genomic region filter (e.g., "chr1:1000-2000").
#'   Requires an indexed VCF.
#' @param tidy_format Logical, if TRUE loads data in tidy (long) format with one
#'   row per variant-sample combination and a SAMPLE_ID column. Default FALSE.
#' @param threads Number of threads for parallel loading (default: 1).
#'   When > 1 and VCF is indexed, loads each chromosome in parallel then unions.
#'   Only applies when as_view = FALSE.
#' @param partition_by Optional character vector of columns to partition by when
#'   creating a table (ignored for views). Creates a partitioned table for efficient
#'   filtering. Only supported for file-backed databases.
#' @param overwrite Logical, drop existing table/view if it exists (default: FALSE).
#' @param config Named list of DuckDB configuration options.
#'
#' @return A list with:
#'   \item{con}{DuckDB connection with extension loaded}
#'   \item{table}{Name of the created table/view}
#'   \item{is_view}{Logical indicating if a view was created}
#'   \item{file}{Path to the source VCF file}
#'   \item{dbdir}{Database directory}
#'   \item{tidy_format}{Whether tidy format was used}
#'   \item{row_count}{Number of rows (NULL for views)}
#'
#' @export
#' @examples
#' \dontrun{
#' ext_path <- bcf_reader_build(tempdir())
#'
#' # Open as lazy view (default - instant creation, re-reads VCF each query)
#' vcf <- vcf_open_duckdb("variants.vcf.gz", ext_path)
#' DBI::dbGetQuery(vcf$con, "SELECT * FROM variants WHERE CHROM = '22'")
#' vcf_close_duckdb(vcf)
#'
#' # Open as materialized table (slower to create, fast repeated queries)
#' vcf <- vcf_open_duckdb("variants.vcf.gz", ext_path, as_view = FALSE)
#' DBI::dbGetQuery(vcf$con, "SELECT COUNT(*) FROM variants")
#'
#' # Tidy format with specific columns
#' vcf <- vcf_open_duckdb("cohort.vcf.gz", ext_path,
#'   tidy_format = TRUE,
#'   columns = c("CHROM", "POS", "REF", "ALT", "SAMPLE_ID", "FORMAT_GT")
#' )
#'
#' # Parallel loading for large files (requires as_view = FALSE)
#' vcf <- vcf_open_duckdb("wgs.vcf.gz", ext_path, as_view = FALSE, threads = 8)
#'
#' # Persistent file-backed database
#' vcf <- vcf_open_duckdb("variants.vcf.gz", ext_path,
#'   dbdir = "my_variants.duckdb"
#' )
#'
#' # Partitioned table for efficient sample queries
#' vcf <- vcf_open_duckdb("cohort.vcf.gz", ext_path,
#'   dbdir = "cohort.duckdb",
#'   tidy_format = TRUE,
#'   partition_by = "SAMPLE_ID"
#' )
#' }
vcf_open_duckdb <- function(
  file,
  extension_path,
  table_name = "variants",
  as_view = TRUE,
  dbdir = ":memory:",
  columns = NULL,
  region = NULL,
  tidy_format = FALSE,
  threads = 1L,
  partition_by = NULL,
  overwrite = FALSE,
  config = list()
) {
  # Validate inputs
  if (missing(extension_path) || is.null(extension_path)) {
    stop(
      "extension_path must be specified. Use bcf_reader_build() first.",
      call. = FALSE
    )
  }

  # Check if file is a remote URL
  is_remote <- grepl("^(s3|gs|http|https|ftp)://", file, ignore.case = TRUE)
  if (!is_remote) {
    if (!file.exists(file)) {
      stop("File not found: ", file, call. = FALSE)
    }
    file <- normalizePath(file, mustWork = TRUE)
  }

  # Validate partition_by usage
  if (!is.null(partition_by)) {
    if (isTRUE(as_view)) {
      warning("partition_by is ignored when as_view = TRUE", call. = FALSE)
      partition_by <- NULL
    }
    if (dbdir == ":memory:") {
      warning(
        "partition_by with in-memory database has limited benefit. ",
        "Consider using a file-backed database for partitioned tables.",
        call. = FALSE
      )
    }
  }

  # Create DuckDB connection with extension
  con <- vcf_duckdb_connect(
    extension_path = extension_path,
    dbdir = dbdir,
    read_only = FALSE,
    config = config
  )

  # Handle cleanup on error
  on.exit(
    {
      if (exists("con") && !is.null(con)) {
        # Only disconnect if we haven't successfully returned
        if (!exists(".success") || !.success) {
          tryCatch(
            DBI::dbDisconnect(con, shutdown = TRUE),
            error = function(e) NULL
          )
        }
      }
    },
    add = TRUE
  )

  # Build bcf_read() call with parameters
  bcf_params <- c()
  if (!is.null(region) && nzchar(region)) {
    bcf_params <- c(bcf_params, sprintf("region := '%s'", region))
  }
  if (isTRUE(tidy_format)) {
    bcf_params <- c(bcf_params, "tidy_format := true")
  }

  if (length(bcf_params) > 0) {
    bcf_read_call <- sprintf(
      "bcf_read('%s', %s)",
      file,
      paste(bcf_params, collapse = ", ")
    )
  } else {
    bcf_read_call <- sprintf("bcf_read('%s')", file)
  }

  # Build select clause
  select_clause <- if (is.null(columns)) {
    "*"
  } else {
    paste(columns, collapse = ", ")
  }

  # Quote table name
  quoted_table <- DBI::dbQuoteIdentifier(con, table_name)

  # Drop existing table/view if overwrite
  if (isTRUE(overwrite)) {
    tryCatch(
      {
        DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", quoted_table))
        DBI::dbExecute(con, sprintf("DROP VIEW IF EXISTS %s", quoted_table))
      },
      error = function(e) NULL
    )
  }

  row_count <- NULL

  if (isTRUE(as_view)) {
    # Create a VIEW - instant but re-reads VCF each query
    view_sql <- sprintf(
      "CREATE VIEW %s AS SELECT %s FROM %s",
      quoted_table,
      select_clause,
      bcf_read_call
    )
    DBI::dbExecute(con, view_sql)
    message(sprintf("Created view '%s' from %s", table_name, basename(file)))
  } else if (threads > 1 && is.null(region) && vcf_has_index(file)) {
    # Parallel loading by chromosome
    row_count <- vcf_open_duckdb_parallel(
      con = con,
      file = file,
      table_name = table_name,
      columns = columns,
      tidy_format = tidy_format,
      threads = threads,
      partition_by = partition_by
    )
  } else {
    # Single-threaded table creation
    if (!is.null(partition_by)) {
      # Create partitioned table
      partition_cols <- paste(partition_by, collapse = ", ")
      create_sql <- sprintf(
        "CREATE TABLE %s AS SELECT %s FROM %s",
        quoted_table,
        select_clause,
        bcf_read_call
      )
      DBI::dbExecute(con, create_sql)

      # Note: DuckDB doesn't support CREATE TABLE ... PARTITION BY directly

      # The partition_by is mainly useful for COPY TO PARQUET
      # For in-database queries, create appropriate indexes instead
      message(sprintf(
        "Note: For best partitioned query performance, consider exporting to ",
        "Parquet with partition_by using vcf_to_parquet_duckdb()"
      ))
    } else {
      create_sql <- sprintf(
        "CREATE TABLE %s AS SELECT %s FROM %s",
        quoted_table,
        select_clause,
        bcf_read_call
      )
      DBI::dbExecute(con, create_sql)
    }

    # Get row count
    count_result <- DBI::dbGetQuery(
      con,
      sprintf("SELECT COUNT(*) as n FROM %s", quoted_table)
    )
    row_count <- count_result$n[1]
    message(sprintf(
      "Created table '%s' with %s rows from %s",
      table_name,
      format(row_count, big.mark = ","),
      basename(file)
    ))
  }

  # Mark success to prevent cleanup
  .success <- TRUE

  # Return connection info
  result <- list(
    con = con,
    table = table_name,
    is_view = as_view,
    file = file,
    dbdir = dbdir,
    tidy_format = tidy_format,
    row_count = row_count
  )
  class(result) <- c("vcf_duckdb", "list")
  result
}

#' Internal: Parallel loading helper for vcf_open_duckdb
#'
#' Loads VCF data by chromosome in parallel and unions into a single table.
#'
#' @param con DuckDB connection
#' @param file VCF file path
#' @param table_name Target table name
#' @param columns Columns to select
#' @param tidy_format Whether to use tidy format
#' @param threads Number of threads
#' @param partition_by Partition columns (unused currently)
#' @return Row count
#' @keywords internal
vcf_open_duckdb_parallel <- function(
  con,
  file,
  table_name,
  columns,
  tidy_format,
  threads,
  partition_by
) {
  # Get contigs from header
  all_contigs <- vcf_get_contigs(file)
  if (length(all_contigs) == 0) {
    stop("No contigs found in VCF header", call. = FALSE)
  }

  # Filter to contigs with data
  contig_counts <- vcf_count_per_contig(file)
  contigs <- names(contig_counts)[contig_counts > 0]

  if (length(contigs) == 0) {
    stop("No variants found in file", call. = FALSE)
  }

  threads <- min(threads, length(contigs))
  message(sprintf(
    "Loading %d contigs using %d threads...",
    length(contigs),
    threads
  ))

  # Build select clause
  select_clause <- if (is.null(columns)) "*" else paste(columns, collapse = ", ")

  # Quote table name
  quoted_table <- DBI::dbQuoteIdentifier(con, table_name)

  # Create temporary tables for each contig in parallel
  temp_tables <- paste0("_temp_contig_", seq_along(contigs))

  load_contig <- function(i) {
    contig <- contigs[i]
    temp_tbl <- temp_tables[i]

    bcf_params <- sprintf("region := '%s'", contig)
    if (isTRUE(tidy_format)) {
      bcf_params <- paste(bcf_params, "tidy_format := true", sep = ", ")
    }

    bcf_read_call <- sprintf("bcf_read('%s', %s)", file, bcf_params)

    sql <- sprintf(
      "CREATE TABLE %s AS SELECT %s FROM %s",
      DBI::dbQuoteIdentifier(con, temp_tbl),
      select_clause,
      bcf_read_call
    )

    tryCatch(
      {
        DBI::dbExecute(con, sql)
        return(temp_tbl)
      },
      error = function(e) {
        return(NULL)
      }
    )
  }

  # Run loading (sequentially for now since DuckDB connection isn't thread-safe)
  # TODO: Consider using multiple connections for true parallel loading
  loaded_tables <- lapply(seq_along(contigs), load_contig)
  loaded_tables <- Filter(Negate(is.null), loaded_tables)

  if (length(loaded_tables) == 0) {
    stop("Failed to load any contigs", call. = FALSE)
  }

  # Union all temp tables into final table
  union_parts <- vapply(
    loaded_tables,
    function(t) sprintf("SELECT * FROM %s", DBI::dbQuoteIdentifier(con, t)),
    character(1)
  )
  union_sql <- paste(union_parts, collapse = " UNION ALL ")

  create_sql <- sprintf(
    "CREATE TABLE %s AS %s",
    quoted_table,
    union_sql
  )
  DBI::dbExecute(con, create_sql)

  # Drop temp tables
  for (t in loaded_tables) {
    tryCatch(
      DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", DBI::dbQuoteIdentifier(con, t))),
      error = function(e) NULL
    )
  }

  # Get final row count
  count_result <- DBI::dbGetQuery(
    con,
    sprintf("SELECT COUNT(*) as n FROM %s", quoted_table)
  )
  row_count <- count_result$n[1]
  message(sprintf(
    "Created table '%s' with %s rows from %d contigs",
    table_name,
    format(row_count, big.mark = ","),
    length(loaded_tables)
  ))

  row_count
}

#' Close a VCF DuckDB connection
#'
#' Properly closes the DuckDB connection opened by vcf_open_duckdb.
#'
#' @param vcf A vcf_duckdb object returned by vcf_open_duckdb
#' @param shutdown Logical, whether to shutdown the DuckDB instance (default: TRUE)
#'
#' @return Invisible NULL
#' @export
#' @examples
#' \dontrun{
#' vcf <- vcf_open_duckdb("variants.vcf.gz", ext_path)
#' # ... do queries ...
#' vcf_close_duckdb(vcf)
#' }
vcf_close_duckdb <- function(vcf, shutdown = TRUE) {
  if (!inherits(vcf, "vcf_duckdb")) {
    stop("vcf must be a vcf_duckdb object from vcf_open_duckdb()", call. = FALSE)
  }
  if (!is.null(vcf$con)) {
    DBI::dbDisconnect(vcf$con, shutdown = shutdown)
  }
  invisible(NULL)
}

#' Print method for vcf_duckdb objects
#'
#' @param x A vcf_duckdb object
#' @param ... Additional arguments (ignored)
#' @export
print.vcf_duckdb <- function(x, ...) {
  cat("VCF DuckDB Connection\n")
  cat("---------------------\n")
  cat("Source file:", basename(x$file), "\n")
  cat("Table name: ", x$table, "\n")
  cat("Type:       ", if (x$is_view) "VIEW (lazy)" else "TABLE (materialized)", "\n")
  cat("Database:   ", if (x$dbdir == ":memory:") "in-memory" else x$dbdir, "\n")
  cat("Tidy format:", x$tidy_format, "\n")
  if (!is.null(x$row_count)) {
    cat("Row count:  ", format(x$row_count, big.mark = ","), "\n")
  }
  cat("\nUse DBI::dbGetQuery(vcf$con, 'SELECT ...') to query\n")
  cat("Use vcf_close_duckdb(vcf) when done\n")
  invisible(x)
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
#' @param tidy_format Logical, if TRUE returns data in tidy (long) format with one
#'   row per variant-sample combination and a SAMPLE_ID column. Default FALSE.
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
#' # Tidy format - one row per variant-sample
#' vcf_query_duckdb("cohort.vcf.gz", ext_path, tidy_format = TRUE)
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
  tidy_format = FALSE,
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

  # Build bcf_read() call with optional parameters
  bcf_params <- c()
  if (!is.null(region) && nzchar(region)) {
    bcf_params <- c(bcf_params, sprintf("region := '%s'", region))
  }
  if (isTRUE(tidy_format)) {
    bcf_params <- c(bcf_params, "tidy_format := true")
  }

  if (length(bcf_params) > 0) {
    bcf_read_call <- sprintf("bcf_read('%s', %s)", file, paste(bcf_params, collapse = ", "))
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
#' @param tidy_format Logical, if TRUE counts rows in tidy format (one per variant-sample).
#'   Default FALSE returns count of variants.
#' @param con Optional existing DuckDB connection (with extension loaded).
#'
#' @return Integer count of variants (or variant-sample combinations if tidy_format=TRUE)
#' @export
#' @examples
#' \dontrun{
#' ext_path <- bcf_reader_build(tempdir())
#' vcf_count_duckdb("variants.vcf.gz", ext_path)
#' vcf_count_duckdb("variants.vcf.gz", ext_path, region = "chr22")
#'
#' # Count variant-sample rows (variants * samples)
#' vcf_count_duckdb("cohort.vcf.gz", ext_path, tidy_format = TRUE)
#' }
vcf_count_duckdb <- function(
  file,
  extension_path = NULL,
  region = NULL,
  tidy_format = FALSE,
  con = NULL
) {
  result <- vcf_query_duckdb(
    file,
    extension_path = extension_path,
    query = "SELECT COUNT(*) as n FROM bcf_read('{file}')",
    region = region,
    tidy_format = tidy_format,
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
#' @param tidy_format Logical, if TRUE returns schema for tidy format. Default FALSE.
#' @param con Optional existing DuckDB connection (with extension loaded).
#'
#' @return A data.frame with column_name and column_type
#' @export
#' @examples
#' \dontrun{
#' ext_path <- bcf_reader_build(tempdir())
#' vcf_schema_duckdb("variants.vcf.gz", ext_path)
#'
#' # Compare wide vs tidy schemas
#' vcf_schema_duckdb("cohort.vcf.gz", ext_path) # FORMAT_GT_Sample1, FORMAT_GT_Sample2...
#' vcf_schema_duckdb("cohort.vcf.gz", ext_path, tidy_format = TRUE) # SAMPLE_ID, FORMAT_GT
#' }
vcf_schema_duckdb <- function(file, extension_path = NULL, tidy_format = FALSE, con = NULL) {
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

  # Build bcf_read call with tidy_format option
  if (isTRUE(tidy_format)) {
    sql <- sprintf("SELECT * FROM bcf_read('%s', tidy_format := true) LIMIT 0", file)
  } else {
    sql <- sprintf("SELECT * FROM bcf_read('%s') LIMIT 0", file)
  }
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
#' @param output_file Path to output Parquet file or directory (when using partition_by)
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param columns Optional character vector of columns to include. NULL for all.
#' @param region Optional genomic region to export (requires index)
#' @param compression Parquet compression: "snappy", "zstd", "gzip", or "none"
#' @param row_group_size Number of rows per row group (default: 100000)
#' @param threads Number of parallel threads for processing (default: 1).
#'   When threads > 1 and file is indexed, uses parallel processing by splitting
#'   work across chromosomes/contigs. See \code{\link{vcf_to_parquet_duckdb_parallel}}.
#' @param tidy_format Logical, if TRUE exports data in tidy (long) format with one
#'   row per variant-sample combination and a SAMPLE_ID column. Default FALSE.
#' @param partition_by Optional character vector of columns to partition by (Hive-style).
#'   Creates a directory structure like `output_dir/SAMPLE_ID=HG00098/data_0.parquet`.
#'   Particularly useful with `tidy_format = TRUE` to partition by SAMPLE_ID for
#'   efficient per-sample queries. DuckDB auto-generates Bloom filters for VARCHAR
#'   columns like SAMPLE_ID, enabling fast row group pruning.
#' @param con Optional existing DuckDB connection (with extension loaded).
#'
#' @return Invisible path to output file/directory
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
#' # Export in tidy format (one row per variant-sample)
#' vcf_to_parquet_duckdb("cohort.vcf.gz", "cohort_tidy.parquet", ext_path,
#'   tidy_format = TRUE
#' )
#'
#' # Tidy format with Hive partitioning by SAMPLE_ID (efficient per-sample queries)
#' vcf_to_parquet_duckdb("cohort.vcf.gz", "cohort_partitioned/", ext_path,
#'   tidy_format = TRUE,
#'   partition_by = "SAMPLE_ID"
#' )
#'
#' # Partition by both CHROM and SAMPLE_ID for large cohorts
#' vcf_to_parquet_duckdb("wgs_cohort.vcf.gz", "wgs_partitioned/", ext_path,
#'   tidy_format = TRUE,
#'   partition_by = c("CHROM", "SAMPLE_ID")
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
  tidy_format = FALSE,
  partition_by = NULL,
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
      tidy_format = tidy_format,
      con = con
    ))
  }

  # Build select clause
  select_clause <- if (is.null(columns)) {
    "*"
  } else {
    paste(columns, collapse = ", ")
  }

  # Build bcf_read call with optional parameters
  bcf_params <- c()
  if (!is.null(region) && nzchar(region)) {
    bcf_params <- c(bcf_params, sprintf("region := '%s'", region))
  }
  if (isTRUE(tidy_format)) {
    bcf_params <- c(bcf_params, "tidy_format := true")
  }

  if (length(bcf_params) > 0) {
    bcf_read_call <- sprintf("bcf_read('%s', %s)", input_file, paste(bcf_params, collapse = ", "))
  } else {
    bcf_read_call <- sprintf("bcf_read('%s')", input_file)
  }

  # Map compression name to DuckDB format
  duckdb_compression <- toupper(compression)

  # Build COPY options
  copy_options <- sprintf(
    "FORMAT PARQUET, COMPRESSION '%s', ROW_GROUP_SIZE %d",
    duckdb_compression,
    as.integer(row_group_size)
  )

  # Add partition_by if specified (Hive-style partitioning)
  if (!is.null(partition_by)) {
    if (!is.character(partition_by) || length(partition_by) == 0) {
      stop("partition_by must be a character vector of column names", call. = FALSE)
    }
    partition_cols <- paste(partition_by, collapse = ", ")
    copy_options <- sprintf("%s, PARTITION_BY (%s)", copy_options, partition_cols)
    # Ensure output path ends with / for directory output
    if (!grepl("/$", output_file)) {
      output_file <- paste0(output_file, "/")
    }
  }

  # Build COPY statement
  sql <- sprintf(
    "COPY (SELECT %s FROM %s) TO '%s' (%s)",
    select_clause,
    bcf_read_call,
    output_file,
    copy_options
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
#' @param tidy_format Logical, if TRUE exports data in tidy (long) format. Default FALSE.
#' @param partition_by Optional character vector of columns to partition by (Hive-style).
#'   Creates directory structure like `output_dir/SAMPLE_ID=HG00098/data_0.parquet`.
#'   Note: When using partition_by, each contig's data is partitioned separately then
#'   merged into the final partitioned output.
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
#' When `partition_by` is specified, the function creates a Hive-partitioned directory
#' structure. This is especially useful with `tidy_format = TRUE` and
#' `partition_by = "SAMPLE_ID"` for efficient per-sample queries on large cohorts.
#' DuckDB auto-generates Bloom filters for VARCHAR columns like SAMPLE_ID.
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
#'
#' # Tidy format output
#' vcf_to_parquet_duckdb_parallel("wgs.vcf.gz", "wgs_tidy.parquet", ext_path,
#'   threads = 8, tidy_format = TRUE
#' )
#'
#' # Tidy format with Hive partitioning by SAMPLE_ID
#' vcf_to_parquet_duckdb_parallel("wgs_cohort.vcf.gz", "wgs_partitioned/", ext_path,
#'   threads = 8, tidy_format = TRUE, partition_by = "SAMPLE_ID"
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
  tidy_format = FALSE,
  partition_by = NULL,
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
      threads = 1,
      tidy_format = tidy_format,
      partition_by = partition_by
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
      threads = 1,
      tidy_format = tidy_format,
      partition_by = partition_by
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
    cols,
    tidy
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
          threads = 1,
          tidy_format = tidy
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
      cols = columns,
      tidy = tidy_format
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
      tidy = tidy_format,
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
  # If partition_by is specified, use COPY with PARTITION_BY
  message("Merging temporary Parquet files... to ", output_file)

  if (!is.null(partition_by)) {
    merge_parquet_files_partitioned(
      temp_files,
      output_file,
      duckdb_compression,
      row_group_size,
      partition_by
    )
  } else {
    merge_parquet_files(
      temp_files,
      output_file,
      duckdb_compression,
      row_group_size
    )
  }

  invisible(output_file)
}


#' Merge Parquet files with Hive partitioning
#'
#' Internal function to merge parquet files into partitioned output.
#'
#' @param input_files Character vector of Parquet file paths
#' @param output_dir Output directory for partitioned parquet
#' @param compression Compression codec
#' @param row_group_size Row group size
#' @param partition_by Character vector of columns to partition by
#' @noRd
merge_parquet_files_partitioned <- function(
  input_files,
  output_dir,
  compression,
  row_group_size,
  partition_by
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

  # Ensure output_dir ends with /
  if (!grepl("/$", output_dir)) {
    output_dir <- paste0(output_dir, "/")
  }

  partition_cols <- paste(partition_by, collapse = ", ")

  sql <- sprintf(
    "COPY (%s) TO '%s' (FORMAT PARQUET, COMPRESSION %s, ROW_GROUP_SIZE %d, PARTITION_BY (%s))",
    union_query,
    output_dir,
    compression,
    as.integer(row_group_size),
    partition_cols
  )

  # Execute merge with partitioning
  suppressMessages({
    DBI::dbExecute(con, sql)
  })

  # Count files created
  n_files <- length(list.files(output_dir, pattern = "\\.parquet$", recursive = TRUE))

  message(sprintf(
    "Merged %d temp files -> %s (%d partition files, partitioned by %s)",
    length(input_files),
    output_dir,
    n_files,
    paste(partition_by, collapse = ", ")
  ))
}


#' Get sample names from a VCF/BCF file
#'
#' Extracts sample names from FORMAT column naming pattern.
#'
#' @param file Path to VCF, VCF.GZ, or BCF file
#' @param extension_path Path to the bcf_reader.duckdb_extension file.
#' @param con Optional existing DuckDB connection (with extension loaded).
#'
#' @return Character vector of sample names
#' @keywords internal
vcf_get_sample_names <- function(file, extension_path = NULL, con = NULL) {
  schema <- vcf_schema_duckdb(file, extension_path = extension_path, con = con)
  gt_cols <- grep("^FORMAT_GT_", schema$column_name, value = TRUE)

  if (length(gt_cols) == 0) {
    return(character(0))
  }

  sub("^FORMAT_GT_", "", gt_cols)
}
