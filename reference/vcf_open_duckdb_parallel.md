# Internal: Parallel loading helper for vcf_open_duckdb

Loads VCF data by chromosome in parallel and unions into a single table.

## Usage

``` r
vcf_open_duckdb_parallel(
  con,
  file,
  table_name,
  columns,
  tidy_format,
  threads,
  partition_by
)
```

## Arguments

- con:

  DuckDB connection

- file:

  VCF file path

- table_name:

  Target table name

- columns:

  Columns to select

- tidy_format:

  Whether to use tidy format

- threads:

  Number of threads

- partition_by:

  Partition columns (unused currently)

## Value

Row count
