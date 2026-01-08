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
