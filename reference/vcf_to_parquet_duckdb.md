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
} # }
```
