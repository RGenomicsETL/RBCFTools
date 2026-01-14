# Set DuckLake configuration option

Set DuckLake configuration option

## Usage

``` r
ducklake_set_option(
  con,
  catalog = "lake",
  option,
  value,
  schema = NULL,
  table_name = NULL
)
```

## Arguments

- con:

  DuckDB connection with DuckLake attached.

- catalog:

  DuckLake catalog name.

- option:

  Option name (e.g., "parquet_compression", "parquet_row_group_size").

- value:

  Option value.

- schema:

  Optional schema scope.

- table_name:

  Optional table scope.

## Value

Invisible NULL.

## Details

Common options:

- `parquet_compression`: snappy, zstd, gzip, lz4

- `parquet_row_group_size`: rows per row group (default 122880)

- `target_file_size`: target file size for compaction (default 512MB

- `data_inlining_row_limit`: max rows to inline (default 0)
