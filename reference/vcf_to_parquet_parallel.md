# Parallel VCF to Parquet conversion

Processes VCF/BCF file in parallel by splitting work across
chromosomes/contigs. Requires an indexed file. Each thread processes a
different chromosome, then results are merged into a single Parquet
file.

## Usage

``` r
vcf_to_parquet_parallel(
  input_vcf,
  output_parquet,
  threads = parallel::detectCores(),
  compression = "snappy",
  row_group_size = 100000L,
  streaming = FALSE,
  index = NULL,
  ...
)
```

## Arguments

- input_vcf:

  Path to input VCF/BCF file (must be indexed)

- output_parquet:

  Path for output Parquet file

- threads:

  Number of parallel threads (default: auto-detect)

- compression:

  Compression codec

- row_group_size:

  Row group size

- streaming:

  Use streaming mode

- index:

  Optional explicit index path

- ...:

  Additional arguments passed to vcf_open_arrow

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
# Use 8 threads
vcf_to_parquet_parallel("wgs.vcf.gz", "wgs.parquet", threads = 8)

# With streaming mode for large files
vcf_to_parquet_parallel(
    "huge.vcf.gz", "huge.parquet",
    threads = 16, streaming = TRUE
)
} # }
```
