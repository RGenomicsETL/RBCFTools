# Get VCF/BCF schema using DuckDB

Returns the column names and types for a VCF/BCF file as seen by DuckDB.

## Usage

``` r
vcf_schema_duckdb(file, extension_path = NULL, tidy_format = FALSE, con = NULL)
```

## Arguments

- file:

  Path to VCF, VCF.GZ, or BCF file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- tidy_format:

  Logical, if TRUE returns schema for tidy format. Default FALSE.

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

A data.frame with column_name and column_type

## Examples

``` r
if (FALSE) { # \dontrun{
ext_path <- bcf_reader_build(tempdir())
vcf_schema_duckdb("variants.vcf.gz", ext_path)

# Compare wide vs tidy schemas
vcf_schema_duckdb("cohort.vcf.gz", ext_path) # FORMAT_GT_Sample1, FORMAT_GT_Sample2...
vcf_schema_duckdb("cohort.vcf.gz", ext_path, tidy_format = TRUE) # SAMPLE_ID, FORMAT_GT
} # }
```
