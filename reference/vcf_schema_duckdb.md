# Get VCF/BCF schema using DuckDB

Returns the column names and types for a VCF/BCF file as seen by DuckDB.

## Usage

``` r
vcf_schema_duckdb(file, extension_path = NULL, con = NULL)
```

## Arguments

- file:

  Path to VCF, VCF.GZ, or BCF file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

A data.frame with column_name and column_type

## Examples

``` r
if (FALSE) { # \dontrun{
ext_path <- bcf_reader_build(tempdir())
vcf_schema_duckdb("variants.vcf.gz", ext_path)
} # }
```
