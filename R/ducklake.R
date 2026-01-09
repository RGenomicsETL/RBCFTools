#' DuckLake helpers for VCF/BCF ETL
#'
#' Utilities to load the DuckLake extension, attach a lake (local or S3-backed),
#' configure S3 secrets, and write variants using either direct DuckDB insert or
#' parallel Parquet conversion.
#'
#' @name ducklake
#' @rdname ducklake
NULL

#' Load the DuckLake extension
#'
#' @param con A DuckDB connection.
#' @param install Logical, attempt `INSTALL ducklake` before loading. Defaults to TRUE.
#'
#' @return The connection (invisibly).
#' @export
ducklake_load <- function(con, install = TRUE) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }

  if (isTRUE(install)) {
    try(DBI::dbExecute(con, "INSTALL ducklake"), silent = TRUE)
  }

  DBI::dbExecute(con, "LOAD ducklake")
  invisible(con)
}

#' @keywords internal
ducklake_machine_arch <- function() {
  m <- tolower(Sys.info()[["machine"]])
  if (grepl("aarch64|arm64", m)) {
    "arm64"
  } else if (grepl("ppc64", m)) {
    "ppc64le"
  } else if (grepl("s390x", m)) {
    "s390x"
  } else {
    "amd64"
  }
}

#' Create or replace an S3 secret for DuckLake
#'
#' @param con A DuckDB connection.
#' @param name Secret name (identifier). Default: "ducklake_s3".
#' @param key_id S3 key ID.
#' @param secret S3 secret key.
#' @param endpoint Optional S3-compatible endpoint (e.g., "s3.us-east-1.amazonaws.com" or "minio:9000").
#' @param region Optional region.
#' @param use_ssl Logical, whether to use SSL. Default: TRUE.
#' @param url_style URL style ("path" or "virtual_host"). Default: "path".
#' @param session_token Optional session token.
#'
#' @return Invisible NULL.
#' @export
ducklake_create_s3_secret <- function(
  con,
  name = "ducklake_s3",
  key_id,
  secret,
  endpoint = NULL,
  region = NULL,
  use_ssl = TRUE,
  url_style = "path",
  session_token = NULL
) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }
  if (missing(key_id) || missing(secret)) {
    stop("key_id and secret are required for S3 secrets", call. = FALSE)
  }

  opts <- list(
    TYPE = "S3",
    KEY_ID = key_id,
    SECRET = secret,
    ENDPOINT = endpoint,
    REGION = region,
    USE_SSL = if (isTRUE(use_ssl)) "true" else "false",
    URL_STYLE = url_style,
    SESSION_TOKEN = session_token
  )

  # Drop NULL or empty values before formatting
  opts <- opts[
    !vapply(
      opts,
      function(x) {
        is.null(x) || (is.character(x) && length(x) == 1 && !nzchar(x))
      },
      logical(1),
      USE.NAMES = FALSE
    )
  ]
  opts <- opts[vapply(
    opts,
    function(x) length(x) > 0,
    logical(1),
    USE.NAMES = FALSE
  )]

  option_sql <- vapply(
    names(opts),
    function(nm) {
      val <- opts[[nm]]
      if (nm %in% c("USE_SSL")) {
        sprintf("%s %s", nm, val)
      } else {
        sprintf("%s %s", nm, DBI::dbQuoteString(con, val))
      }
    },
    character(1L),
    USE.NAMES = FALSE
  )
  option_sql <- option_sql[nzchar(option_sql)]

  sql <- sprintf(
    "CREATE OR REPLACE SECRET %s (%s)",
    DBI::dbQuoteIdentifier(con, name),
    paste(option_sql, collapse = ", ")
  )

  DBI::dbExecute(con, sql)
  invisible(NULL)
}

#' Download a static MinIO server binary
#'
#' @param dest_dir Destination directory (created if missing).
#' @param url Optional download URL. Defaults to MinIO Linux build for host arch.
#' @param filename Output filename. Defaults to "minio".
#'
#' @return Path to downloaded binary.
#' @export
ducklake_download_minio <- function(
  dest_dir = tempdir(),
  url = NULL,
  filename = "minio"
) {
  if (missing(dest_dir) || is.null(dest_dir)) {
    stop("dest_dir must be provided", call. = FALSE)
  }
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  }
  if (is.null(url) || !nzchar(url)) {
    os <- tolower(Sys.info()[["sysname"]])
    if (os != "linux") {
      stop(
        "MinIO server binary download is only supported on Linux hosts",
        call. = FALSE
      )
    }
    arch <- ducklake_machine_arch()
    url <- sprintf(
      "https://dl.min.io/server/minio/release/linux-%s/minio",
      arch
    )
  }
  dest <- file.path(dest_dir, filename)
  utils::download.file(url, dest, mode = "wb", quiet = TRUE)
  Sys.chmod(dest, mode = "0755")
  dest
}

#' Download a static MinIO client (mc) binary
#'
#' @param dest_dir Destination directory (created if missing).
#' @param url Optional download URL. Defaults to mc Linux build for host arch.
#' @param filename Output filename. Defaults to "mc".
#'
#' @return Path to downloaded binary.
#' @export
ducklake_download_mc <- function(
  dest_dir = tempdir(),
  url = NULL,
  filename = "mc"
) {
  if (missing(dest_dir) || is.null(dest_dir)) {
    stop("dest_dir must be provided", call. = FALSE)
  }
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  }
  if (is.null(url) || !nzchar(url)) {
    os <- tolower(Sys.info()[["sysname"]])
    arch <- ducklake_machine_arch()
    if (os == "linux") {
      url <- sprintf("https://dl.min.io/client/mc/release/linux-%s/mc", arch)
    } else if (os == "darwin") {
      url <- sprintf("https://dl.min.io/client/mc/release/darwin-%s/mc", arch)
    } else {
      stop(
        "Unsupported platform for mc download; expected Linux or macOS",
        call. = FALSE
      )
    }
  }
  dest <- file.path(dest_dir, filename)
  utils::download.file(url, dest, mode = "wb", quiet = TRUE)
  Sys.chmod(dest, mode = "0755")
  dest
}

#' Attach a DuckLake catalog
#'
#' @param con A DuckDB connection with DuckLake loaded.
#' @param metadata_path Path/URI to the DuckLake metadata DB (without the `ducklake:` prefix).
#' @param data_path Path/URI for table data (Parquet files).
#' @param alias Schema alias to attach as. Default: "ducklake".
#' @param read_only Logical, open lake read-only. Default: FALSE.
#' @param create_if_missing Logical, create metadata DB if missing. Default: TRUE.
#' @param extra_options Named list of additional ATTACH options (e.g., list(METADATA_CATALOG = "meta")).
#'
#' @return Invisible NULL.
#' @export
ducklake_attach <- function(
  con,
  metadata_path,
  data_path,
  alias = "ducklake",
  read_only = FALSE,
  create_if_missing = TRUE,
  extra_options = list()
) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (missing(metadata_path) || !nzchar(metadata_path)) {
    stop("metadata_path must be provided", call. = FALSE)
  }
  if (missing(data_path) || !nzchar(data_path)) {
    stop("data_path must be provided", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }

  opts <- list(
    DATA_PATH = data_path,
    READ_ONLY = if (isTRUE(read_only)) "true" else "false",
    CREATE_IF_NOT_EXISTS = if (isTRUE(create_if_missing)) "true" else "false"
  )

  if (length(extra_options)) {
    for (nm in names(extra_options)) {
      opts[[nm]] <- extra_options[[nm]]
    }
  }

  option_sql <- vapply(
    names(opts),
    function(nm) {
      val <- opts[[nm]]
      if (is.null(val) || (is.character(val) && !nzchar(val))) {
        return(NULL)
      }
      if (is.logical(val)) {
        sprintf("%s %s", nm, if (val) "true" else "false")
      } else if (is.numeric(val)) {
        sprintf("%s %s", nm, as.character(val))
      } else if (tolower(val) %in% c("true", "false")) {
        sprintf("%s %s", nm, val)
      } else {
        sprintf("%s %s", nm, DBI::dbQuoteString(con, val))
      }
    },
    character(1L),
    USE.NAMES = FALSE
  )
  option_sql <- option_sql[nzchar(option_sql)]

  attach_sql <- sprintf(
    "ATTACH %s AS %s (%s)",
    DBI::dbQuoteString(con, paste0("ducklake:", metadata_path)),
    DBI::dbQuoteIdentifier(con, alias),
    paste(option_sql, collapse = ", ")
  )

  DBI::dbExecute(con, attach_sql)
  invisible(NULL)
}

#' Write variants into a DuckLake table
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param table Target table name (optionally qualified, e.g., "ducklake.variants").
#' @param vcf_path Path/URI to VCF/BCF.
#' @param method "parquet" (default) to convert to Parquet then ingest, or "direct" to insert via `bcf_read`.
#' @param threads Threads for conversion (passed to `vcf_to_parquet`).
#' @param compression Parquet compression codec (default "zstd").
#' @param row_group_size Parquet row group size (default 100000).
#' @param partition_by Optional character vector of columns to partition by when creating a new table.
#' @param overwrite Logical, drop and recreate the table.
#' @param bcf_reader_extension Optional path to bcf_reader.duckdb_extension (needed for `method = "direct"` if not installed).
#' @param region Optional region string for `bcf_read` when using `method = "direct"`.
#' @param ... Additional arguments passed to `vcf_to_parquet`.
#'
#' @return Invisible NULL.
#' @export
ducklake_write_variants <- function(
  con,
  table,
  vcf_path,
  method = c("parquet", "direct"),
  threads = parallel::detectCores(),
  compression = "zstd",
  row_group_size = 100000L,
  partition_by = NULL,
  overwrite = FALSE,
  bcf_reader_extension = NULL,
  region = NULL,
  ...
) {
  method <- match.arg(method)

  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (missing(table) || !nzchar(table)) {
    stop("table must be provided", call. = FALSE)
  }
  if (missing(vcf_path) || !nzchar(vcf_path)) {
    stop("vcf_path must be provided", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("Package 'duckdb' is required", call. = FALSE)
  }

  is_remote <- grepl("^(s3|gs|http|https|ftp)://", vcf_path, ignore.case = TRUE)
  if (!is_remote && !file.exists(vcf_path)) {
    stop("File not found: ", vcf_path, call. = FALSE)
  }

  partition_clause <- ""
  if (!is.null(partition_by) && length(partition_by) > 0) {
    ids <- vapply(
      partition_by,
      function(x) DBI::dbQuoteIdentifier(con, x),
      character(1L)
    )
    partition_clause <- sprintf(
      " PARTITION BY (%s)",
      paste(ids, collapse = ", ")
    )
  }

  table_exists <- FALSE
  table_parts <- strsplit(table, "\\.", fixed = TRUE)[[1]]
  if (length(table_parts) == 2) {
    table_exists <- tryCatch(
      DBI::dbExistsTable(
        con,
        DBI::Id(schema = table_parts[1], table = table_parts[2])
      ),
      error = function(e) FALSE
    )
  } else {
    table_exists <- tryCatch(
      DBI::dbExistsTable(con, DBI::Id(table = table_parts[1])),
      error = function(e) FALSE
    )
  }

  quoted_table <- if (length(table_parts) == 2) {
    DBI::dbQuoteIdentifier(
      con,
      DBI::Id(schema = table_parts[1], table = table_parts[2])
    )
  } else {
    DBI::dbQuoteIdentifier(con, table_parts[1])
  }

  if (isTRUE(overwrite) && table_exists) {
    DBI::dbExecute(con, sprintf("DROP TABLE %s", quoted_table))
    table_exists <- FALSE
  }

  if (method == "parquet") {
    parquet_path <- tempfile("ducklake_parquet_", fileext = ".parquet")
    on.exit(unlink(parquet_path, recursive = TRUE), add = TRUE)

    vcf_to_parquet(
      input_vcf = vcf_path,
      output_parquet = parquet_path,
      compression = compression,
      row_group_size = row_group_size,
      streaming = FALSE,
      threads = threads,
      ...
    )

    if (!file.exists(parquet_path)) {
      stop("Parquet conversion did not produce an output file", call. = FALSE)
    }

    if (table_exists) {
      insert_sql <- sprintf(
        "INSERT INTO %s SELECT * FROM read_parquet(%s)",
        quoted_table,
        DBI::dbQuoteString(con, parquet_path)
      )
      DBI::dbExecute(con, insert_sql)
    } else {
      create_sql <- sprintf(
        "CREATE TABLE %s%s AS SELECT * FROM read_parquet(%s)",
        quoted_table,
        partition_clause,
        DBI::dbQuoteString(con, parquet_path)
      )
      DBI::dbExecute(con, create_sql)
    }
  } else {
    # direct mode via bcf_read
    load_stmt <- if (
      !is.null(bcf_reader_extension) && nzchar(bcf_reader_extension)
    ) {
      sprintf("LOAD %s", DBI::dbQuoteString(con, bcf_reader_extension))
    } else {
      "LOAD bcf_reader"
    }
    load_res <- try(DBI::dbExecute(con, load_stmt), silent = TRUE)
    if (inherits(load_res, "try-error")) {
      stop(
        "Failed to load bcf_reader extension; provide bcf_reader_extension path if needed",
        call. = FALSE
      )
    }

    bcf_call <- if (!is.null(region) && nzchar(region)) {
      sprintf(
        "bcf_read(%s, region := %s)",
        DBI::dbQuoteString(con, vcf_path),
        DBI::dbQuoteString(con, region)
      )
    } else {
      sprintf("bcf_read(%s)", DBI::dbQuoteString(con, vcf_path))
    }

    if (table_exists) {
      insert_sql <- sprintf(
        "INSERT INTO %s SELECT * FROM %s",
        quoted_table,
        bcf_call
      )
      DBI::dbExecute(con, insert_sql)
    } else {
      create_sql <- sprintf(
        "CREATE TABLE %s%s AS SELECT * FROM %s",
        quoted_table,
        partition_clause,
        bcf_call
      )
      DBI::dbExecute(con, create_sql)
    }
  }

  invisible(NULL)
}
