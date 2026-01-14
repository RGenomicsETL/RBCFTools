# List files managed by DuckLake for a table

List files managed by DuckLake for a table

## Usage

``` r
ducklake_list_files(con, catalog = "lake", table, schema = "main")
```

## Arguments

- con:

  DuckDB connection with DuckLake attached.

- catalog:

  DuckLake catalog name.

- table:

  Table name.

- schema:

  Schema name (default "main").

## Value

Data frame with file information.
