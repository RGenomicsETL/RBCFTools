# Write variants into a DuckLake table

Write variants into a DuckLake table

## Usage

``` r
ducklake_write_variants(
  con,
  table,
  vcf_path,
  method = c("parquet", "direct"),
  threads = parallel::detectCores(),
  compression = "zstd",
  row_group_size = 100000L,
  partition_by = NULL,
  overwrite = FALSE,
  bcf_reader_extension = NULL,
  region = NULL,
  ...
)
```

## Arguments

- con:

  DuckDB connection with DuckLake attached.

- table:

  Target table name (optionally qualified, e.g., "ducklake.variants").

- vcf_path:

  Path/URI to VCF/BCF.

- method:

  "parquet" (default) to convert to Parquet then ingest, or "direct" to
  insert via `bcf_read`.

- threads:

  Threads for conversion (passed to `vcf_to_parquet`).

- compression:

  Parquet compression codec (default "zstd").

- row_group_size:

  Parquet row group size (default 100000).

- partition_by:

  Optional character vector of columns to partition by when creating a
  new table.

- overwrite:

  Logical, drop and recreate the table.

- bcf_reader_extension:

  Optional path to bcf_reader.duckdb_extension (needed for
  `method = "direct"` if not installed).

- region:

  Optional region string for `bcf_read` when using `method = "direct"`.

- ...:

  Additional arguments passed to `vcf_to_parquet`.

## Value

Invisible NULL.
