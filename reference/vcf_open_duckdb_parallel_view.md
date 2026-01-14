# Internal: Create parallel VIEW using UNION ALL of per-contig bcf_read calls

Creates a VIEW that unions bcf_read() calls for each contig. DuckDB can
parallelize execution at query time.

## Usage

``` r
vcf_open_duckdb_parallel_view(
  con,
  file,
  table_name,
  columns,
  tidy_format,
  threads
)
```

## Arguments

- con:

  DuckDB connection

- file:

  VCF file path

- table_name:

  Target view name

- columns:

  Columns to select

- tidy_format:

  Whether to use tidy format

- threads:

  Number of threads (used to limit contigs)

## Value

NULL (views don't have row counts)
