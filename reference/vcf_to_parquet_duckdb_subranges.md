# Parallel VCF to Parquet conversion using DuckDB

For single-chromosome files, splits chromosome into ranges for parallel
processing.

## Usage

``` r
vcf_to_parquet_duckdb_subranges(
  input_file,
  output_file,
  extension_path = NULL,
  columns = NULL,
  compression = "zstd",
  row_group_size = 1e+05,
  threads = parallel::detectCores(),
  contig
)
```

## Arguments

- input_file:

  Input VCF/BCF file path

- output_file:

  Output Parquet file path

- extension_path:

  Path to bcf_reader extension (auto-detected if NULL)

- columns:

  Specific columns to include (NULL for all)

- compression:

  Compression codec (zstd, snappy, gzip, etc)

- row_group_size:

  Parquet row group size

- threads:

  Number of parallel threads for range processing

- contig:

  Single contig name to be split into ranges

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

Invisibly returns the output path

List with conversion metrics

## Details

Processes VCF/BCF file in parallel by splitting work across
chromosomes/contigs using the DuckDB bcf_reader extension. Requires an
indexed file. Each thread processes a different chromosome, then results
are merged into a single Parquet file.

This function:

1.  Checks for index (required for parallel processing)

2.  Extracts contig names from header

3.  Processes each contig in parallel using multiple R processes

4.  Writes each contig to a temporary Parquet file

5.  Merges all temporary files into final output using DuckDB

Contigs that return no variants are skipped automatically.

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
} # }
```
