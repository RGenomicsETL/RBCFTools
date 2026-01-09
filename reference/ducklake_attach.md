# Attach a DuckLake catalog

Attach a DuckLake catalog

## Usage

``` r
ducklake_attach(
  con,
  metadata_path,
  data_path,
  alias = "ducklake",
  read_only = FALSE,
  create_if_missing = TRUE,
  extra_options = list()
)
```

## Arguments

- con:

  A DuckDB connection with DuckLake loaded.

- metadata_path:

  Path/URI to the DuckLake metadata DB (without the `ducklake:` prefix).

- data_path:

  Path/URI for table data (Parquet files).

- alias:

  Schema alias to attach as. Default: "ducklake".

- read_only:

  Logical, open lake read-only. Default: FALSE.

- create_if_missing:

  Logical, create metadata DB if missing. Default: TRUE.

- extra_options:

  Named list of additional ATTACH options (e.g., list(METADATA_CATALOG =
  "meta")).

## Value

Invisible NULL.
