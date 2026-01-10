# List existing DuckLake catalog secrets

List existing DuckLake catalog secrets

## Usage

``` r
ducklake_list_secrets(con)
```

## Arguments

- con:

  A DuckDB connection.

## Value

Data frame with columns: name, type, metadata_path, data_path.
