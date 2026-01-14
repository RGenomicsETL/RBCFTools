# Export VCF/BCF to tidy (long) Parquet format

Converts VCF/BCF to a "tidy" format where each row represents one
variant-sample combination. FORMAT columns are unpivoted from wide
`FORMAT_<field>_<sample>` columns to a single `SAMPLE_ID` column plus
`FORMAT_<field>` columns.

## Usage

``` r
vcf_to_parquet_tidy(
  input_file,
  output_file,
  extension_path = NULL,
  columns = NULL,
  region = NULL,
  compression = "zstd",
  row_group_size = 100000L,
  threads = 1L,
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

  Optional character vector of non-FORMAT columns to include. FORMAT
  columns are always included and transformed to tidy format. NULL
  includes all columns.

- region:

  Optional genomic region to export (requires index)

- compression:

  Parquet compression: "snappy", "zstd", "gzip", or "none"

- row_group_size:

  Number of rows per row group (default: 100000)

- threads:

  Number of parallel threads for processing (default: 1). When threads
  \> 1 and file is indexed, uses parallel processing by splitting work
  across chromosomes/contigs.

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

Invisible path to output file

## Details

This format is ideal for:

- Combining multiple single-sample VCFs into a cohesive dataset

- Appending new samples to existing variant tables

- Downstream analysis with tools that expect long-format data

- Building variant cohort tables for MERGE/UPSERT operations

## Examples

``` r
if (FALSE) { # \dontrun{
ext_path <- bcf_reader_build(tempdir())

# Convert single-sample VCF to tidy format
vcf_to_parquet_tidy("sample1.vcf.gz", "sample1_tidy.parquet", ext_path)

# Convert multi-sample VCF - creates one row per variant-sample
vcf_to_parquet_tidy("cohort.vcf.gz", "cohort_tidy.parquet", ext_path)

# Select specific columns (FORMAT columns always included)
vcf_to_parquet_tidy("sample.vcf.gz", "slim.parquet", ext_path,
  columns = c("CHROM", "POS", "REF", "ALT")
)

# Parallel processing for large files
vcf_to_parquet_tidy("wgs.vcf.gz", "wgs_tidy.parquet", ext_path, threads = 8)

# Multiple single-sample VCFs can be combined:
vcf_to_parquet_tidy("sampleA.vcf.gz", "sampleA.parquet", ext_path)
vcf_to_parquet_tidy("sampleB.vcf.gz", "sampleB.parquet", ext_path)
# Then union in DuckDB or append to DuckLake table
} # }
```
