# List DuckLake snapshots

List DuckLake snapshots

## Usage

``` r
ducklake_snapshots(con, catalog = "lake")
```

## Arguments

- con:

  DuckDB connection with DuckLake attached.

- catalog:

  DuckLake catalog name (alias used in ATTACH).

## Value

Data frame with snapshot history.
