# Read Parquet key-value metadata

Reads the custom key-value metadata stored in a Parquet file's footer.
This includes the full VCF header if the file was created with
[`vcf_to_parquet_duckdb`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_parquet_duckdb.md)
with `include_metadata = TRUE`.

## Usage

``` r
parquet_kv_metadata(file, con = NULL)
```

## Arguments

- file:

  Path to Parquet file

- con:

  Optional existing DuckDB connection

## Value

A data frame with columns: key, value. Returns empty data frame if no
custom metadata exists.

## Examples

``` r
if (FALSE) { # \dontrun{
meta <- parquet_kv_metadata("variants.parquet")
# Get the VCF header
vcf_header <- meta[meta$key == "vcf_header", "value"]
cat(vcf_header)
} # }
```
