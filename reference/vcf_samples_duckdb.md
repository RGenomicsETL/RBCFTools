# List samples in a VCF/BCF file using DuckDB

Extract sample names from FORMAT column names.

## Usage

``` r
vcf_samples_duckdb(file, extension_path = NULL, con = NULL)
```

## Arguments

- file:

  Path to VCF, VCF.GZ, or BCF file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

Character vector of sample names

## Examples

``` r
if (FALSE) { # \dontrun{
ext_path <- bcf_reader_build(tempdir())
vcf_samples_duckdb("variants.vcf.gz", ext_path)
} # }
```
