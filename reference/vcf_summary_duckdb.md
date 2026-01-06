# Summary statistics for a VCF/BCF file using DuckDB

Get summary statistics including variant counts per chromosome.

## Usage

``` r
vcf_summary_duckdb(file, extension_path = NULL, con = NULL)
```

## Arguments

- file:

  Path to VCF, VCF.GZ, or BCF file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- con:

  Optional existing DuckDB connection (with extension loaded).

## Value

A list with total_variants, n_samples, and variants_per_chrom

## Examples

``` r
if (FALSE) { # \dontrun{
ext_path <- bcf_reader_build(tempdir())
vcf_summary_duckdb("variants.vcf.gz", ext_path)
} # }
```
