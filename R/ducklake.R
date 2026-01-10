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

#' Parse DuckLake connection string into components
#'
#' @param connection_string DuckLake connection string (e.g., "ducklake:path/to/catalog.ducklake").
#'
#' @return Named list with components: backend, metadata_path, data_path (if specified).
#' @keywords internal
ducklake_parse_connection_string <- function(connection_string) {
  if (!grepl("^ducklake:", connection_string)) {
    stop("Connection string must start with 'ducklake:'", call. = FALSE)
  }

  # Remove ducklake: prefix
  path_part <- sub("^ducklake:", "", connection_string)

  # Check for secret reference (ducklake:secret_name)
  if (
    !grepl("[/:]", path_part) && !grepl("\\.(duckdb|db|sqlite)$", path_part)
  ) {
    return(list(
      backend = "secret",
      metadata_path = path_part,
      data_path = NULL
    ))
  }

  # Parse backend from path
  if (grepl("^sqlite://", path_part)) {
    backend <- "sqlite"
    metadata_path <- sub("^sqlite://", "", path_part)
  } else if (grepl("^postgresql://", path_part)) {
    backend <- "postgresql"
    metadata_path <- sub("^postgresql://", "", path_part)
  } else if (grepl("^mysql://", path_part)) {
    backend <- "mysql"
    metadata_path <- sub("^mysql://", "", path_part)
  } else if (grepl("\\.ducklake$", path_part)) {
    backend <- "duckdb"
    metadata_path <- path_part
  } else {
    # Default to DuckDB for plain paths
    backend <- "duckdb"
    metadata_path <- path_part
  }

  list(
    backend = backend,
    metadata_path = metadata_path,
    data_path = NULL
  )
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

#' Create a DuckLake catalog secret for database credentials
#'
#' @param con A DuckDB connection.
#' @param name Secret name (identifier). Default: "ducklake_catalog".
#' @param backend Database backend type ("duckdb", "sqlite", "postgresql", "mysql").
#' @param connection_string Database connection string (without ducklake: prefix).
#' @param data_path Default data path for this catalog. Optional.
#' @param metadata_parameters Named list of additional metadata parameters.
#' @param persistent Logical, create a persistent secret. Default: FALSE.
#'
#' @return Invisible NULL.
#' @export
ducklake_create_catalog_secret <- function(
  con,
  name = "ducklake_catalog",
  backend = c("duckdb", "sqlite", "postgresql", "mysql"),
  connection_string,
  data_path = NULL,
  metadata_parameters = list(),
  persistent = FALSE
) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (missing(connection_string) || !nzchar(connection_string)) {
    stop("connection_string is required", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }

  backend <- match.arg(backend)

  # Build metadata parameters based on backend
  meta_params <- list(TYPE = backend)

  # Add backend-specific parameters
  if (backend == "postgresql" && grepl("://", connection_string)) {
    # Parse PostgreSQL connection string to extract components for SECRET parameter
    meta_params$SECRET <- name
  } else if (backend == "mysql" && grepl("://", connection_string)) {
    # Parse MySQL connection string
    meta_params$SECRET <- name
  }

  # Merge user-provided parameters
  if (length(metadata_parameters) > 0) {
    for (nm in names(metadata_parameters)) {
      meta_params[[nm]] <- metadata_parameters[[nm]]
    }
  }

  # Build secret options
  opts <- list(
    TYPE = "ducklake",
    METADATA_PATH = connection_string
  )

  if (!is.null(data_path) && nzchar(data_path)) {
    opts$DATA_PATH <- data_path
  }

  if (length(meta_params) > 0) {
    opts$METADATA_PARAMETERS <- sprintf(
      "MAP {%s}",
      paste(
        sprintf("'%s': '%s'", names(meta_params), meta_params),
        collapse = ", "
      )
    )
  }

  # Format options for SQL
  option_sql <- vapply(
    names(opts),
    function(nm) {
      val <- opts[[nm]]
      if (nm == "METADATA_PARAMETERS") {
        sprintf("%s %s", nm, val)
      } else {
        sprintf("%s %s", nm, DBI::dbQuoteString(con, val))
      }
    },
    character(1L),
    USE.NAMES = FALSE
  )

  # Create secret
  secret_type <- if (isTRUE(persistent)) {
    "CREATE PERSISTENT SECRET"
  } else {
    "CREATE SECRET"
  }
  sql <- sprintf(
    "%s %s (%s)",
    secret_type,
    DBI::dbQuoteIdentifier(con, name),
    paste(option_sql, collapse = ", ")
  )

  DBI::dbExecute(con, sql)
  invisible(NULL)
}

#' List existing DuckLake catalog secrets
#'
#' @param con A DuckDB connection.
#'
#' @return Data frame with columns: name, type, metadata_path, data_path.
#' @export
ducklake_list_secrets <- function(con) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }

  # Query DuckDB's internal secrets table
  tryCatch(
    {
      secrets <- DBI::dbGetQuery(
        con,
        "
      SELECT 
        name,
        type,
        CASE 
          WHEN key = 'METADATA_PATH' THEN value
          ELSE NULL
        END as metadata_path,
        CASE 
          WHEN key = 'DATA_PATH' THEN value
          ELSE NULL
        END as data_path
      FROM duckdb_secrets()
      WHERE type = 'ducklake'
    "
      )

      # Pivot to get one row per secret
      if (nrow(secrets) > 0) {
        secrets <- stats::aggregate(
          cbind(metadata_path, data_path) ~ name + type,
          data = secrets,
          FUN = function(x) max(x, na.rm = TRUE)
        )
      }

      secrets
    },
    error = function(e) {
      warning("Could not list secrets: ", conditionMessage(e), call. = FALSE)
      data.frame()
    }
  )
}

#' Drop a DuckLake catalog secret
#'
#' @param con A DuckDB connection.
#' @param name Secret name to drop.
#'
#' @return Invisible NULL.
#' @export
ducklake_drop_secret <- function(con, name) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (missing(name) || !nzchar(name)) {
    stop("name must be provided", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }

  sql <- sprintf("DROP SECRET IF EXISTS %s", DBI::dbQuoteIdentifier(con, name))
  DBI::dbExecute(con, sql)
  invisible(NULL)
}

#' Update an existing DuckLake catalog secret
#'
#' @param con A DuckDB connection.
#' @param name Secret name to update.
#' @param connection_string New database connection string.
#' @param data_path New default data path. Optional.
#' @param metadata_parameters New named list of metadata parameters.
#'
#' @return Invisible NULL.
#' @export
ducklake_update_secret <- function(
  con,
  name,
  connection_string,
  data_path = NULL,
  metadata_parameters = list()
) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (missing(name) || !nzchar(name)) {
    stop("name must be provided", call. = FALSE)
  }
  if (missing(connection_string) || !nzchar(connection_string)) {
    stop("connection_string is required", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }

  # Drop existing secret
  ducklake_drop_secret(con, name)

  # Recreate with new parameters (assuming it was a catalog secret)
  ducklake_create_catalog_secret(
    con = con,
    name = name,
    backend = "duckdb", # Default, will be inferred from connection string
    connection_string = connection_string,
    data_path = data_path,
    metadata_parameters = metadata_parameters,
    persistent = TRUE
  )
}

#' Connect to a DuckLake catalog with abstracted backend support
#'
#' @param con A DuckDB connection with DuckLake loaded.
#' @param backend Database backend type ("duckdb", "sqlite", "postgresql", "mysql").
#' @param connection_string Database connection string (format depends on backend).
#' @param data_path Path/URI for table data (Parquet files). Required for new lakes.
#' @param alias Schema alias to attach as. Default: "ducklake".
#' @param secret_name Optional secret name to use instead of direct connection parameters.
#' @param read_only Logical, open lake read-only. Default: FALSE.
#' @param create_if_missing Logical, create metadata DB if missing. Default: TRUE.
#' @param extra_options Named list of additional ATTACH options.
#'
#' @return Invisible NULL.
#' @export
ducklake_connect_catalog <- function(
  con,
  backend = c("duckdb", "sqlite", "postgresql", "mysql"),
  connection_string = NULL,
  data_path = NULL,
  alias = "ducklake",
  secret_name = NULL,
  read_only = FALSE,
  create_if_missing = TRUE,
  extra_options = list()
) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }

  backend <- match.arg(backend)

  # Build metadata path based on backend
  if (!is.null(secret_name) && nzchar(secret_name)) {
    # Use secret-based connection
    metadata_path <- secret_name
  } else {
    # Use direct connection
    if (is.null(connection_string) || !nzchar(connection_string)) {
      stop(
        "connection_string is required when not using secret_name",
        call. = FALSE
      )
    }

    # Format connection string based on backend
    metadata_path <- switch(
      backend,
      "duckdb" = connection_string,
      "sqlite" = paste0("sqlite://", connection_string),
      "postgresql" = paste0("postgresql://", connection_string),
      "mysql" = paste0("mysql://", connection_string)
    )
  }

  # Validate data path requirement
  if (is.null(data_path) && is.null(secret_name)) {
    stop(
      "data_path is required when creating a new lake without a secret",
      call. = FALSE
    )
  }

  # Build base options
  opts <- list(
    READ_ONLY = if (isTRUE(read_only)) "true" else "false",
    CREATE_IF_NOT_EXISTS = if (isTRUE(create_if_missing)) "true" else "false"
  )

  # Add data path if provided
  if (!is.null(data_path) && nzchar(data_path)) {
    opts$DATA_PATH <- data_path
  }

  # Add extra options
  if (length(extra_options) > 0) {
    for (nm in names(extra_options)) {
      opts[[nm]] <- extra_options[[nm]]
    }
  }

  # Format options for SQL
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
  option_sql <- option_sql[!is.null(option_sql) & nzchar(option_sql)]

  # Build and execute ATTACH command
  attach_sql <- sprintf(
    "ATTACH %s AS %s (%s)",
    DBI::dbQuoteString(con, paste0("ducklake:", metadata_path)),
    DBI::dbQuoteIdentifier(con, alias),
    paste(option_sql, collapse = ", ")
  )

  DBI::dbExecute(con, attach_sql)
  invisible(NULL)
}

#' Attach a DuckLake catalog (legacy function)
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
#' @seealso \code{\link{ducklake_connect_catalog}} for abstracted backend support.
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

#' Register existing Parquet files in a DuckLake table
#'
#' Adds Parquet files that already exist (from prior ETL) to a DuckLake table.
#' This is a catalog-only operation; data files are not copied or moved.
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param table Target table name (optionally qualified, e.g., "lake.variants").
#' @param parquet_files Character vector of Parquet file paths/URIs.
#' @param create_table Logical, create the table if it doesn't exist. Default: TRUE.
#'   When TRUE, schema is inferred from the first Parquet file.
#'
#' @return Invisibly returns the number of files registered.
#' @export
#'
#' @details
#' This function uses DuckLake's `ducklake_add_data_files()` to register

#' external Parquet files in the catalog. The files must already exist and
#' have a schema compatible with the target table.
#'
#' @examples
#' \dontrun{
#' # Register a Parquet file created by vcf_to_parquet_duckdb()
#' ducklake_register_parquet(con, "variants", "s3://bucket/variants.parquet")
#' }
ducklake_register_parquet <- function(
  con,
  table,
  parquet_files,
  create_table = TRUE
) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (missing(table) || !nzchar(table)) {
    stop("table must be provided", call. = FALSE)
  }
  if (missing(parquet_files) || length(parquet_files) == 0) {
    stop("parquet_files must be provided", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }

  # Parse table name

  table_parts <- strsplit(table, "\\.", fixed = FALSE)[[1]]
  quoted_table <- if (length(table_parts) == 2) {
    DBI::dbQuoteIdentifier(
      con,
      DBI::Id(schema = table_parts[1], table = table_parts[2])
    )
  } else {
    DBI::dbQuoteIdentifier(con, table_parts[1])
  }

  # Check if table exists
  table_exists <- tryCatch(
    {
      if (length(table_parts) == 2) {
        DBI::dbExistsTable(
          con,
          DBI::Id(schema = table_parts[1], table = table_parts[2])
        )
      } else {
        DBI::dbExistsTable(con, DBI::Id(table = table_parts[1]))
      }
    },
    error = function(e) FALSE
  )

  # Create table from first file if needed
  if (!table_exists && isTRUE(create_table)) {
    first_file <- parquet_files[1]
    create_sql <- sprintf(
      "CREATE TABLE %s AS SELECT * FROM read_parquet(%s) WHERE false",
      quoted_table,
      DBI::dbQuoteString(con, first_file)
    )
    DBI::dbExecute(con, create_sql)
  }

  # Register files using ducklake_add_data_files
  n_registered <- 0
  for (pq_file in parquet_files) {
    add_sql <- sprintf(
      "CALL ducklake_add_data_files(%s, %s, %s)",
      DBI::dbQuoteString(con, table_parts[length(table_parts)]),
      DBI::dbQuoteString(
        con,
        if (length(table_parts) == 2) table_parts[1] else "main"
      ),
      DBI::dbQuoteString(con, pq_file)
    )
    tryCatch(
      {
        DBI::dbExecute(con, add_sql)
        n_registered <- n_registered + 1
      },
      error = function(e) {
        warning("Failed to register ", pq_file, ": ", conditionMessage(e))
      }
    )
  }

  invisible(n_registered)
}

#' Load VCF into DuckLake (ETL + Registration)
#'
#' Converts VCF/BCF to Parquet using the fast `bcf_reader` extension, then
#' registers the Parquet file in a DuckLake catalog table.
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param table Target table name (optionally qualified, e.g., "lake.variants").
#' @param vcf_path Path/URI to VCF/BCF file.
#' @param extension_path Path to bcf_reader.duckdb_extension (required).
#' @param output_path Optional Parquet output path. If NULL, uses DuckLake's DATA_PATH.
#' @param threads Number of threads for conversion.
#' @param compression Parquet compression codec.
#' @param row_group_size Parquet row group size.
#' @param region Optional region filter (e.g., "chr1:1000-2000").
#' @param columns Optional character vector of columns to include.
#' @param overwrite Logical, drop existing table first.
#'
#' @return Invisibly returns the path to the created Parquet file.
#' @export
#'
#' @details
#' This is the recommended function for loading VCF data into DuckLake.
#' It uses the `bcf_reader` DuckDB extension for fast VCF→Parquet conversion,
#' which is significantly faster than the nanoarrow streaming path.
#'
#' **Workflow:**
#' 1. VCF → Parquet via `vcf_to_parquet_duckdb()` (bcf_reader)
#' 2. Register Parquet in DuckLake catalog
#'
#' @examples
#' \dontrun{
#' # Build extension
#' ext_path <- bcf_reader_build(tempdir())
#'
#' # Setup DuckLake
#' con <- duckdb::dbConnect(duckdb::duckdb())
#' ducklake_load(con)
#' ducklake_attach(con, "catalog.ducklake", "/data/parquet/", alias = "lake")
#' DBI::dbExecute(con, "USE lake")
#'
#' # Load VCF
#' ducklake_load_vcf(con, "variants", "sample.vcf.gz", ext_path, threads = 8)
#'
#' # Query
#' DBI::dbGetQuery(con, "SELECT CHROM, COUNT(*) FROM variants GROUP BY CHROM")
#' }
ducklake_load_vcf <- function(
  con,
  table,
  vcf_path,
  extension_path,
  output_path = NULL,
  threads = parallel::detectCores(),
  compression = "zstd",
  row_group_size = 100000L,
  region = NULL,
  columns = NULL,
  overwrite = FALSE
) {
  if (missing(con) || is.null(con)) {
    stop("con must be provided", call. = FALSE)
  }
  if (missing(table) || !nzchar(table)) {
    stop("table must be provided", call. = FALSE)
  }
  if (missing(vcf_path) || !nzchar(vcf_path)) {
    stop("vcf_path must be provided", call. = FALSE)
  }
  if (missing(extension_path) || is.null(extension_path)) {
    stop(
      "extension_path must be provided. Use bcf_reader_build() first.",
      call. = FALSE
    )
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("Package 'DBI' is required", call. = FALSE)
  }

  # Validate input file
  is_remote <- grepl("^(s3|gs|http|https|ftp)://", vcf_path, ignore.case = TRUE)
  if (!is_remote && !file.exists(vcf_path)) {
    stop("VCF file not found: ", vcf_path, call. = FALSE)
  }

  # Parse table name
  table_parts <- strsplit(table, "\\.", fixed = FALSE)[[1]]
  quoted_table <- if (length(table_parts) == 2) {
    DBI::dbQuoteIdentifier(
      con,
      DBI::Id(schema = table_parts[1], table = table_parts[2])
    )
  } else {
    DBI::dbQuoteIdentifier(con, table_parts[1])
  }

  # Drop table if overwrite
  if (isTRUE(overwrite)) {
    tryCatch(
      {
        DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", quoted_table))
      },
      error = function(e) NULL
    )
  }

  # Determine output path
  if (is.null(output_path)) {
    # Generate a unique filename based on table name and timestamp
    output_file <- sprintf(
      "%s_%s.parquet",
      gsub("\\.", "_", table),
      format(Sys.time(), "%Y%m%d_%H%M%S")
    )
    output_path <- file.path(tempdir(), output_file)
    temp_output <- TRUE
  } else {
    temp_output <- FALSE
  }

  # Convert VCF to Parquet using bcf_reader (fast path)
  vcf_to_parquet_duckdb(
    input_file = vcf_path,
    output_file = output_path,
    extension_path = extension_path,
    columns = columns,
    region = region,
    compression = compression,
    row_group_size = row_group_size,
    threads = threads
  )

  # Insert into DuckLake table
  table_exists <- tryCatch(
    {
      if (length(table_parts) == 2) {
        DBI::dbExistsTable(
          con,
          DBI::Id(schema = table_parts[1], table = table_parts[2])
        )
      } else {
        DBI::dbExistsTable(con, DBI::Id(table = table_parts[1]))
      }
    },
    error = function(e) FALSE
  )

  if (table_exists) {
    insert_sql <- sprintf(
      "INSERT INTO %s SELECT * FROM read_parquet(%s)",
      quoted_table,
      DBI::dbQuoteString(con, output_path)
    )
    DBI::dbExecute(con, insert_sql)
  } else {
    create_sql <- sprintf(
      "CREATE TABLE %s AS SELECT * FROM read_parquet(%s)",
      quoted_table,
      DBI::dbQuoteString(con, output_path)
    )
    DBI::dbExecute(con, create_sql)
  }

  # Clean up temp file
  if (temp_output && file.exists(output_path)) {
    unlink(output_path)
  }

  invisible(output_path)
}
