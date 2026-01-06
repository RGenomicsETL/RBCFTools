# Count variants in a VCF/BCF file

Fast variant count using DuckDB projection pushdown.

## Usage

``` r
vcf_count_duckdb(file, extension_path = NULL, region = NULL, con = NULL)
```

## Arguments

- file:

  Path to VCF, VCF.GZ, or BCF file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- region:

  Optional genomic region for indexed files

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

Integer count of variants

## Examples

``` r
if (FALSE) { # \dontrun{
ext_path <- bcf_reader_build(tempdir())
vcf_count_duckdb("variants.vcf.gz", ext_path)
vcf_count_duckdb("variants.vcf.gz", ext_path, region = "chr22")
} # }
```
