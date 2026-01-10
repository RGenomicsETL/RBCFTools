# Create a DuckLake catalog secret for database credentials

Create a DuckLake catalog secret for database credentials

## Usage

``` r
ducklake_create_catalog_secret(
  con,
  name = "ducklake_catalog",
  backend = c("duckdb", "sqlite", "postgresql", "mysql"),
  connection_string,
  data_path = NULL,
  metadata_parameters = list(),
  persistent = FALSE
)
```

## Arguments

- con:

  A DuckDB connection.

- name:

  Secret name (identifier). Default: "ducklake_catalog".

- backend:

  Database backend type ("duckdb", "sqlite", "postgresql", "mysql").

- connection_string:

  Database connection string (without ducklake: prefix).

- data_path:

  Default data path for this catalog. Optional.

- metadata_parameters:

  Named list of additional metadata parameters.

- persistent:

  Logical, create a persistent secret. Default: FALSE.

## Value

Invisible NULL.
