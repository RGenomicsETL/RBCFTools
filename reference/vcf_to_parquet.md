# Write VCF/BCF to Parquet format

Converts a VCF/BCF file to Apache Parquet format for efficient storage
and querying with tools like DuckDB, Spark, or Python pandas/polars.

## Usage

``` r
vcf_to_parquet(
  input_vcf,
  output_parquet,
  compression = "snappy",
  row_group_size = 100000L,
  ...
)
```

## Arguments

- input_vcf:

  Path to input VCF or BCF file

- output_parquet:

  Path for output Parquet file

- compression:

  Compression codec: "snappy", "gzip", "zstd", "lz4", "none"

- row_group_size:

  Number of rows per row group (default: 100000)

- ...:

  Additional arguments passed to vcf_open_arrow

## Value

Invisibly returns the output path

## Examples

``` r
if (FALSE) { # \dontrun{
vcf_to_parquet("variants.vcf.gz", "variants.parquet")

# With zstd compression
vcf_to_parquet("variants.vcf.gz", "variants.parquet", compression = "zstd")

# Query with DuckDB
library(duckdb)
con <- dbConnect(duckdb())
dbGetQuery(con, "SELECT CHROM, POS, REF FROM 'variants.parquet' WHERE CHROM = 'chr1'")
} # }
```
