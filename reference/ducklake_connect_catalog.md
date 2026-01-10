# Connect to a DuckLake catalog with abstracted backend support

Connect to a DuckLake catalog with abstracted backend support

## Usage

``` r
ducklake_connect_catalog(
  con,
  backend = c("duckdb", "sqlite", "postgresql", "mysql"),
  connection_string = NULL,
  data_path = NULL,
  alias = "ducklake",
  secret_name = NULL,
  read_only = FALSE,
  create_if_missing = TRUE,
  extra_options = list()
)
```

## Arguments

- con:

  A DuckDB connection with DuckLake loaded.

- backend:

  Database backend type ("duckdb", "sqlite", "postgresql", "mysql").

- connection_string:

  Database connection string (format depends on backend).

- data_path:

  Path/URI for table data (Parquet files). Required for new lakes.

- alias:

  Schema alias to attach as. Default: "ducklake".

- secret_name:

  Optional secret name to use instead of direct connection parameters.

- read_only:

  Logical, open lake read-only. Default: FALSE.

- create_if_missing:

  Logical, create metadata DB if missing. Default: TRUE.

- extra_options:

  Named list of additional ATTACH options.

## Value

Invisible NULL.
