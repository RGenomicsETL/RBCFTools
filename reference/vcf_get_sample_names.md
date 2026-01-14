# Get sample names from a VCF/BCF file

Extracts sample names from FORMAT column naming pattern.

## Usage

``` r
vcf_get_sample_names(file, extension_path = NULL, con = NULL)
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
