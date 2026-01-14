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
#' @export
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
  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = 3000)
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
  message("Downloading mc from ", url, " to ", dest)
  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = 3000)
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
      secrets_raw <- DBI::dbGetQuery(
        con,
        "
      SELECT name, type, secret_string
      FROM duckdb_secrets()
      WHERE type = 'ducklake'
    "
      )

      # Parse secret_string to extract metadata_path and data_path
      if (nrow(secrets_raw) > 0) {
        parse_secret_field <- function(secret_str, field_name) {
          pattern <- sprintf("%s=([^;]*)", field_name)
          match <- regexpr(pattern, secret_str, perl = TRUE)
          if (match > 0) {
            start <- attr(match, "capture.start")[1]
            length <- attr(match, "capture.length")[1]
            if (start > 0 && length > 0) {
              return(substr(secret_str, start, start + length - 1))
            }
          }
          return(NA_character_)
        }

        metadata_path <- character(nrow(secrets_raw))
        data_path <- character(nrow(secrets_raw))

        for (i in seq_len(nrow(secrets_raw))) {
          metadata_path[i] <- parse_secret_field(
            secrets_raw$secret_string[i],
            "metadata_path"
          )
          data_path[i] <- parse_secret_field(
            secrets_raw$secret_string[i],
            "data_path"
          )
        }

        secrets <- data.frame(
          name = secrets_raw$name,
          type = secrets_raw$type,
          metadata_path = metadata_path,
          data_path = data_path,
          stringsAsFactors = FALSE
        )
      } else {
        secrets <- data.frame(
          name = character(0),
          type = character(0),
          metadata_path = character(0),
          data_path = character(0),
          stringsAsFactors = FALSE
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
    metadata_path <- switch(backend,
      "duckdb" = connection_string,
      "sqlite" = paste0("sqlite:", connection_string),
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

  # Add data path if provided (only for non-secret connections)
  if (!is.null(data_path) && nzchar(data_path) && is.null(secret_name)) {
    opts$DATA_PATH <- data_path
  }

  # Add extra options (filter out unsupported options when using secrets)
  if (length(extra_options) > 0) {
    for (nm in names(extra_options)) {
      # Skip SECRET option when using secret_name as it's not supported in ATTACH
      if (!is.null(secret_name) && nm == "SECRET") {
        next
      }
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
#' @param allow_missing Logical, allow missing columns (filled with defaults). Default: FALSE.
#' @param ignore_extra_columns Logical, ignore extra columns in files. Default: FALSE.
#' @param allow_evolution Logical, evolve table schema by adding new columns from files.
#'   Default: FALSE. When TRUE, new columns found in files are added via ALTER TABLE
#'   before registration, making all columns queryable.
#'
#' @return Invisibly returns the number of files registered.
#' @export
#'
#' @details
#' This function uses DuckLake's `ducklake_add_data_files()` to register
#' external Parquet files in the catalog. The files must already exist and
#' have a schema compatible with the target table.
#'
#' **Schema Evolution (`allow_evolution = TRUE`):**
#' When enabled, the function compares each file's schema against the table schema
#' and adds any missing columns via `ALTER TABLE ADD COLUMN` before registration.
#' This allows combining VCF files with different annotations (e.g., VEP columns)
#' into a single table where all columns are queryable.
#'
#' @examples
#' \dontrun{
#' # Register a Parquet file created by vcf_to_parquet_duckdb()
#' ducklake_register_parquet(con, "variants", "s3://bucket/variants.parquet")
#'
#' # Register with schema evolution (add new columns from file)
#' ducklake_register_parquet(con, "variants", "s3://bucket/vep_variants.parquet",
#'   allow_evolution = TRUE
#' )
#' }
ducklake_register_parquet <- function(
  con,
  table,
  parquet_files,
  create_table = TRUE,
  allow_missing = FALSE,
  ignore_extra_columns = FALSE,
  allow_evolution = FALSE
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

  # Warn about conflicting options

  if (isTRUE(allow_evolution) && isTRUE(ignore_extra_columns)) {
    warning(
      "allow_evolution and ignore_extra_columns are mutually exclusive; ",
      "allow_evolution takes precedence",
      call. = FALSE
    )
    ignore_extra_columns <- FALSE
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
    # Schema evolution: add new columns from file before registration
    if (isTRUE(allow_evolution)) {
      existing_cols <- DBI::dbGetQuery(
        con,
        sprintf("SELECT column_name FROM (DESCRIBE %s)", quoted_table)
      )$column_name
      file_schema <- DBI::dbGetQuery(
        con,
        sprintf("DESCRIBE SELECT * FROM read_parquet(%s)", DBI::dbQuoteString(con, pq_file))
      )
      new_cols <- file_schema[!file_schema$column_name %in% existing_cols, ]
      if (nrow(new_cols) > 0) {
        alter_statements <- sprintf(
          'ALTER TABLE %s ADD COLUMN "%s" %s',
          quoted_table, new_cols$column_name, new_cols$column_type
        )
        invisible(lapply(alter_statements, function(sql) DBI::dbExecute(con, sql)))
      }
    }

    # Build ducklake_add_data_files call
    # Note: order is (catalog, table, file, schema => ...) for DuckLake API
    catalog_name <- if (length(table_parts) == 2) table_parts[1] else "main"
    table_name <- table_parts[length(table_parts)]

    call_params <- c(
      DBI::dbQuoteString(con, catalog_name),
      DBI::dbQuoteString(con, table_name),
      DBI::dbQuoteString(con, pq_file)
    )

    # Add schema evolution options
    # When allow_evolution is TRUE, we always need allow_missing for the original table's columns
    if (isTRUE(allow_missing) || isTRUE(allow_evolution)) {
      call_params <- c(call_params, "allow_missing => true")
    }
    if (isTRUE(ignore_extra_columns)) {
      call_params <- c(call_params, "ignore_extra_columns => true")
    }

    add_sql <- sprintf(
      "CALL ducklake_add_data_files(%s)",
      paste(call_params, collapse = ", ")
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
#' @param allow_evolution Logical, evolve table schema by adding new columns from VCF.
#'   Default: FALSE. When TRUE, new columns found in the VCF are added via ALTER TABLE
#'   before insertion, making all columns queryable. Useful for combining VCFs with
#'   different annotations (e.g., VEP columns) or different samples (FORMAT_*_SampleName).
#' @param tidy_format Logical, if TRUE exports data in tidy (long) format with one
#'   row per variant-sample combination and a SAMPLE_ID column. Default FALSE.
#'   Ideal for cohort analysis and combining multiple single-sample VCFs.
#' @param partition_by Optional character vector of columns to partition by (Hive-style).
#'   Creates directory structure like `output_dir/SAMPLE_ID=HG00098/data_0.parquet`.
#'   Note: DuckLake registration currently requires single Parquet files; when using
#'   partition_by, the output_path should point to the partition directory and
#'   files should be registered separately.
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
#' **Schema Evolution (`allow_evolution = TRUE`):**
#' When loading multiple VCFs with different schemas (e.g., different samples
#' or different annotation fields), enable `allow_evolution` to automatically
#' add new columns to the table schema. This uses DuckLake's `ALTER TABLE ADD COLUMN`
#' which preserves existing data files without rewriting.
#'
#' **Tidy Format (`tidy_format = TRUE`):**
#' When building cohort tables from multiple single-sample VCFs, use `tidy_format = TRUE`
#' to get one row per variant-sample combination with a `SAMPLE_ID` column. This format
#' is ideal for downstream analysis and MERGE/UPSERT operations on DuckLake tables.
#'
#' **Partitioning (`partition_by`):**
#' When using `partition_by`, the output is a Hive-partitioned directory structure.
#' This is useful for large cohorts where you want efficient per-sample queries.
#' DuckDB auto-generates Bloom filters for VARCHAR columns like SAMPLE_ID.
#' Note: For DuckLake, partitioned output requires manual file registration.
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
#' # Load first VCF
#' ducklake_load_vcf(con, "variants", "sample1.vcf.gz", ext_path, threads = 8)
#'
#' # Load second VCF with different annotations, evolving schema
#' ducklake_load_vcf(con, "variants", "sample2_vep.vcf.gz", ext_path,
#'   allow_evolution = TRUE
#' )
#'
#' # Load VCF in tidy format (one row per variant-sample)
#' ducklake_load_vcf(con, "variants_tidy", "cohort.vcf.gz", ext_path,
#'   tidy_format = TRUE
#' )
#'
#' # Query - all columns from both VCFs are available
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
  overwrite = FALSE,
  allow_evolution = FALSE,
  tidy_format = FALSE,
  partition_by = NULL
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
    if (!is.null(partition_by)) {
      # For partitioned output, use a directory
      output_file <- sprintf(
        "%s_%s/",
        gsub("\\.", "_", table),
        format(Sys.time(), "%Y%m%d_%H%M%S")
      )
    } else {
      output_file <- sprintf(
        "%s_%s.parquet",
        gsub("\\.", "_", table),
        format(Sys.time(), "%Y%m%d_%H%M%S")
      )
    }
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
    threads = threads,
    tidy_format = tidy_format,
    partition_by = partition_by
  )

  # Construct read path: for partitioned output, use glob pattern
  if (!is.null(partition_by)) {
    read_path <- paste0(output_path, "**/*.parquet")
    # Use hive_partitioning=true to include partition columns in the result
    read_parquet_call <- sprintf(
      "read_parquet(%s, hive_partitioning=true)",
      DBI::dbQuoteString(con, read_path)
    )
  } else {
    read_parquet_call <- sprintf(
      "read_parquet(%s)",
      DBI::dbQuoteString(con, output_path)
    )
  }

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
    # Schema evolution: add new columns before insert
    if (isTRUE(allow_evolution)) {
      existing_cols <- DBI::dbGetQuery(
        con,
        sprintf("SELECT column_name FROM (DESCRIBE %s)", quoted_table)
      )$column_name
      file_schema <- DBI::dbGetQuery(
        con,
        sprintf("DESCRIBE SELECT * FROM %s", read_parquet_call)
      )
      new_cols <- file_schema[!file_schema$column_name %in% existing_cols, ]
      if (nrow(new_cols) > 0) {
        alter_statements <- sprintf(
          'ALTER TABLE %s ADD COLUMN "%s" %s',
          quoted_table, new_cols$column_name, new_cols$column_type
        )
        invisible(lapply(alter_statements, function(sql) DBI::dbExecute(con, sql)))
      }
    }

    insert_sql <- sprintf(
      "INSERT INTO %s SELECT * FROM %s",
      quoted_table,
      read_parquet_call
    )
    DBI::dbExecute(con, insert_sql)
  } else {
    create_sql <- sprintf(
      "CREATE TABLE %s AS SELECT * FROM %s",
      quoted_table,
      read_parquet_call
    )
    DBI::dbExecute(con, create_sql)
  }

  # Clean up temp files
  if (temp_output) {
    if (!is.null(partition_by)) {
      # Remove partition directory
      unlink(output_path, recursive = TRUE)
    } else if (file.exists(output_path)) {
      unlink(output_path)
    }
  }

  invisible(output_path)
}

#' List DuckLake snapshots
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param catalog DuckLake catalog name (alias used in ATTACH).
#'
#' @return Data frame with snapshot history.
#' @export
ducklake_snapshots <- function(con, catalog = "lake") {
  DBI::dbGetQuery(con, sprintf("SELECT * FROM %s.snapshots()", catalog))
}

#' Get current snapshot ID
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param catalog DuckLake catalog name.
#'
#' @return Integer snapshot ID.
#' @export
ducklake_current_snapshot <- function(con, catalog = "lake") {
  DBI::dbGetQuery(con, sprintf("FROM %s.current_snapshot()", catalog))$id[1]
}

#' Set commit message for current transaction
#'
#' Must be called within a transaction (BEGIN/COMMIT block).
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param catalog DuckLake catalog name.
#' @param author Author name.
#' @param message Commit message.
#' @param extra_info Optional JSON string with extra metadata.
#'
#' @return Invisible NULL.
#' @export
ducklake_set_commit_message <- function(
  con,
  catalog = "lake",
  author,
  message,
  extra_info = NULL
) {
  if (is.null(extra_info)) {
    sql <- sprintf(
      "CALL %s.set_commit_message(%s, %s)",
      catalog,
      DBI::dbQuoteString(con, author),
      DBI::dbQuoteString(con, message)
    )
  } else {
    sql <- sprintf(
      "CALL %s.set_commit_message(%s, %s, extra_info => %s)",
      catalog,
      DBI::dbQuoteString(con, author),
      DBI::dbQuoteString(con, message),
      DBI::dbQuoteString(con, extra_info)
    )
  }
  DBI::dbExecute(con, sql)
  invisible(NULL)
}

#' Get DuckLake configuration options
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param catalog DuckLake catalog name.
#'
#' @return Data frame with current options.
#' @export
ducklake_options <- function(con, catalog = "lake") {
  DBI::dbGetQuery(con, sprintf("FROM %s.options()", catalog))
}

#' Set DuckLake configuration option
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param catalog DuckLake catalog name.
#' @param option Option name (e.g., "parquet_compression", "parquet_row_group_size").
#' @param value Option value.
#' @param schema Optional schema scope.
#' @param table_name Optional table scope.
#'
#' @return Invisible NULL.
#' @export
#'
#' @details
#' Common options:
#' - `parquet_compression`: snappy, zstd, gzip, lz4
#' - `parquet_row_group_size`: rows per row group (default 122880)
#' - `target_file_size`: target file size for compaction (default 512MB
#' - `data_inlining_row_limit`: max rows to inline (default 0)
ducklake_set_option <- function(
  con,
  catalog = "lake",
  option,
  value,
  schema = NULL,
  table_name = NULL
) {
  params <- c(
    DBI::dbQuoteString(con, option),
    DBI::dbQuoteString(con, as.character(value))
  )
  if (!is.null(schema)) {
    params <- c(params, sprintf("schema => %s", DBI::dbQuoteString(con, schema)))
  }
  if (!is.null(table_name)) {
    params <- c(params, sprintf("table_name => %s", DBI::dbQuoteString(con, table_name)))
  }
  sql <- sprintf("CALL %s.set_option(%s)", catalog, paste(params, collapse = ", "))
  DBI::dbExecute(con, sql)
  invisible(NULL)
}

#' Query table at a specific snapshot (time travel)
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param table Table name.
#' @param snapshot_id Snapshot version to query.
#' @param query SQL query (use 'tbl' as table alias).
#'
#' @return Query result as data frame.
#' @export
ducklake_query_snapshot <- function(con, table, snapshot_id, query = "SELECT * FROM tbl") {
  sql <- sprintf(
    "WITH tbl AS (SELECT * FROM %s AT (VERSION => %d)) %s",
    table, as.integer(snapshot_id), query
  )
  DBI::dbGetQuery(con, sql)
}

#' List files managed by DuckLake for a table
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param catalog DuckLake catalog name.
#' @param table Table name.
#' @param schema Schema name (default "main").
#'
#' @return Data frame with file information.
#' @export
ducklake_list_files <- function(con, catalog = "lake", table, schema = "main") {
  DBI::dbGetQuery(
    con,
    sprintf(
      "FROM ducklake_list_files(%s, %s, schema => %s)",
      DBI::dbQuoteString(con, catalog),
      DBI::dbQuoteString(con, table),
      DBI::dbQuoteString(con, schema)
    )
  )
}

#' Merge/upsert data into a DuckLake table
#'
#' @param con DuckDB connection with DuckLake attached.
#' @param target Target table name.
#' @param source Source table/query.
#' @param on_cols Column(s) to match on.
#' @param when_matched Action when matched: "UPDATE", "DELETE", or NULL.
#' @param when_not_matched Action when not matched: "INSERT" or NULL.
#' @param update_cols Columns to update (NULL = all columns).
#'
#' @return Number of rows affected.
#' @export
ducklake_merge <- function(
  con,
  target,
  source,
  on_cols,
  when_matched = "UPDATE",
  when_not_matched = "INSERT",
  update_cols = NULL
) {
  on_clause <- paste(
    sprintf("%s.%s = source.%s", target, on_cols, on_cols),
    collapse = " AND "
  )

  matched_clause <- if (!is.null(when_matched)) {
    if (when_matched == "UPDATE") {
      if (is.null(update_cols)) {
        "WHEN MATCHED THEN UPDATE"
      } else {
        set_clause <- paste(
          sprintf("%s = source.%s", update_cols, update_cols),
          collapse = ", "
        )
        sprintf("WHEN MATCHED THEN UPDATE SET %s", set_clause)
      }
    } else if (when_matched == "DELETE") {
      "WHEN MATCHED THEN DELETE"
    } else {
      ""
    }
  } else {
    ""
  }

  not_matched_clause <- if (!is.null(when_not_matched) && when_not_matched == "INSERT") {
    "WHEN NOT MATCHED THEN INSERT"
  } else {
    ""
  }

  sql <- sprintf(
    "MERGE INTO %s USING (%s) AS source ON (%s) %s %s",
    target, source, on_clause, matched_clause, not_matched_clause
  )

  DBI::dbExecute(con, sql)
}
