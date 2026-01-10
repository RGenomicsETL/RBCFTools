# Parse DuckLake connection string into components

Parse DuckLake connection string into components

## Usage

``` r
ducklake_parse_connection_string(connection_string)
```

## Arguments

- connection_string:

  DuckLake connection string (e.g.,
  "ducklake:path/to/catalog.ducklake").

## Value

Named list with components: backend, metadata_path, data_path (if
specified).
