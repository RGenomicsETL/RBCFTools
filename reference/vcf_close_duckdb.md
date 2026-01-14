# Close a VCF DuckDB connection

Properly closes the DuckDB connection opened by vcf_open_duckdb.

## Usage

``` r
vcf_close_duckdb(vcf, shutdown = TRUE)
```

## Arguments

- vcf:

  A vcf_duckdb object returned by vcf_open_duckdb

- shutdown:

  Logical, whether to shutdown the DuckDB instance (default: TRUE)

## Value

Invisible NULL

## Examples

``` r
if (FALSE) { # \dontrun{
vcf <- vcf_open_duckdb("variants.vcf.gz", ext_path)
# ... do queries ...
vcf_close_duckdb(vcf)
} # }
```
