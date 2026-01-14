# Parallel VCF to Parquet conversion using DuckDB

Processes VCF/BCF file in parallel by splitting work across
chromosomes/contigs using the DuckDB bcf_reader extension. Requires an
indexed file. Each thread processes a different chromosome, then results
are merged into a single Parquet file.

## Usage

``` r
vcf_to_parquet_duckdb_parallel(
  input_file,
  output_file,
  extension_path = NULL,
  threads = parallel::detectCores(),
  compression = "zstd",
  row_group_size = 100000L,
  columns = NULL,
  tidy_format = FALSE,
  partition_by = NULL,
  con = NULL
)
```

## Arguments

- input_file:

  Path to input VCF/BCF file (must be indexed)

- output_file:

  Path for output Parquet file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- threads:

  Number of parallel threads (default: auto-detect)

- compression:

  Parquet compression codec

- row_group_size:

  Row group size

- columns:

  Optional character vector of columns to include

- tidy_format:

  Logical, if TRUE exports data in tidy (long) format. Default FALSE.

- partition_by:

  Optional character vector of columns to partition by (Hive-style).
  Creates directory structure like
  `output_dir/SAMPLE_ID=HG00098/data_0.parquet`. Note: When using
  partition_by, each contig's data is partitioned separately then merged
  into the final partitioned output.

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

Invisibly returns the output path

## Details

This function:

1.  Checks for index (required for parallel processing)

2.  Extracts contig names from header

3.  Processes each contig in parallel using multiple R processes

4.  Writes each contig to a temporary Parquet file

5.  Merges all temporary files into final output using DuckDB

Contigs that return no variants are skipped automatically.

When `partition_by` is specified, the function creates a
Hive-partitioned directory structure. This is especially useful with
`tidy_format = TRUE` and `partition_by = "SAMPLE_ID"` for efficient
per-sample queries on large cohorts. DuckDB auto-generates Bloom filters
for VARCHAR columns like SAMPLE_ID.

## See also

[`vcf_to_parquet_duckdb`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_parquet_duckdb.md)
for single-threaded conversion

## Examples

``` r
if (FALSE) { # \dontrun{
ext_path <- bcf_reader_build(tempdir())

# Use 8 threads
vcf_to_parquet_duckdb_parallel("wgs.vcf.gz", "wgs.parquet", ext_path, threads = 8)

# With specific columns
vcf_to_parquet_duckdb_parallel(
  "wgs.vcf.gz", "wgs.parquet", ext_path,
  threads = 16,
  columns = c("CHROM", "POS", "REF", "ALT")
)

# Tidy format output
vcf_to_parquet_duckdb_parallel("wgs.vcf.gz", "wgs_tidy.parquet", ext_path,
  threads = 8, tidy_format = TRUE
)

# Tidy format with Hive partitioning by SAMPLE_ID
vcf_to_parquet_duckdb_parallel("wgs_cohort.vcf.gz", "wgs_partitioned/", ext_path,
  threads = 8, tidy_format = TRUE, partition_by = "SAMPLE_ID"
)
} # }
```
