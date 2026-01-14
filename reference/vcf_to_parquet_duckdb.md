# Export VCF/BCF to Parquet using DuckDB

Convert a VCF/BCF file to Parquet format for fast subsequent queries.

## Usage

``` r
vcf_to_parquet_duckdb(
  input_file,
  output_file,
  extension_path = NULL,
  columns = NULL,
  region = NULL,
  compression = "zstd",
  row_group_size = 100000L,
  threads = 1L,
  tidy_format = FALSE,
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

- columns:

  Optional character vector of columns to include. NULL for all.

- region:

  Optional genomic region to export (requires index)

- compression:

  Parquet compression: "snappy", "zstd", "gzip", or "none"

- row_group_size:

  Number of rows per row group (default: 100000)

- threads:

  Number of parallel threads for processing (default: 1). When threads
  \> 1 and file is indexed, uses parallel processing by splitting work
  across chromosomes/contigs. See
  [`vcf_to_parquet_duckdb_parallel`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_parquet_duckdb_parallel.md).

- tidy_format:

  Logical, if TRUE exports data in tidy (long) format with one row per
  variant-sample combination and a SAMPLE_ID column. Default FALSE.

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

Invisible path to output file

## Examples

``` r
if (FALSE) { # \dontrun{
ext_path <- bcf_reader_build(tempdir())

# Export entire file
vcf_to_parquet_duckdb("variants.vcf.gz", "variants.parquet", ext_path)

# Export specific columns
vcf_to_parquet_duckdb("variants.vcf.gz", "variants_slim.parquet", ext_path,
  columns = c("CHROM", "POS", "REF", "ALT", "INFO_AF")
)

# Export a region
vcf_to_parquet_duckdb("variants.vcf.gz", "chr22.parquet", ext_path,
  region = "chr22"
)

# Export in tidy format (one row per variant-sample)
vcf_to_parquet_duckdb("cohort.vcf.gz", "cohort_tidy.parquet", ext_path,
  tidy_format = TRUE
)

# Parallel mode for whole-genome VCF (requires index)
vcf_to_parquet_duckdb("wgs.vcf.gz", "wgs.parquet", ext_path, threads = 8)
} # }
```
