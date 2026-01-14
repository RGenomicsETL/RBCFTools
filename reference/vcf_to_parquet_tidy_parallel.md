# Parallel tidy VCF to Parquet conversion

Processes VCF/BCF file in parallel by splitting work across
chromosomes/contigs, converting to tidy (long) format. Requires an
indexed file.

## Usage

``` r
vcf_to_parquet_tidy_parallel(
  input_file,
  output_file,
  extension_path = NULL,
  threads = parallel::detectCores(),
  compression = "zstd",
  row_group_size = 100000L,
  columns = NULL,
  con = NULL
)
```

## Arguments

- input_file:

  Path to input VCF, VCF.GZ, or BCF file

- output_file:

  Path to output Parquet file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- threads:

  Number of parallel threads (default: auto-detect)

- compression:

  Parquet compression: "snappy", "zstd", "gzip", or "none"

- row_group_size:

  Number of rows per row group (default: 100000)

- columns:

  Optional character vector of non-FORMAT columns to include. FORMAT
  columns are always included and transformed to tidy format. NULL
  includes all columns.

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

Invisibly returns the output path
