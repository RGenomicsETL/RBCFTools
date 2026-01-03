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
  streaming = FALSE,
  ...
)
```

## Arguments

- input_vcf:

  Path to input VCF or BCF file

- output_parquet:

  Path for output Parquet file

- compression:

  Compression codec: "snappy", "gzip", "zstd", "lz4", "uncompressed"

- row_group_size:

  Number of rows per row group (default: 100000)

- streaming:

  Use streaming mode for large files. When TRUE, writes to a temporary
  Arrow IPC file first (via nanoarrow), then converts to Parquet via
  DuckDB. This avoids loading the entire VCF into R memory. Requires the
  DuckDB nanoarrow community extension. Default is FALSE.

- ...:

  Additional arguments passed to vcf_open_arrow

## Value

Invisibly returns the output path

## Details

By default (`streaming = FALSE`), the function loads the entire VCF into
memory as a data.frame before writing to Parquet. This is fast for small
to medium files.

For very large VCF files, set `streaming = TRUE` to use a two-stage
streaming approach:

1.  Stream VCF to a temporary Arrow IPC file (via nanoarrow)

2.  Convert IPC to Parquet via DuckDB (with nanoarrow extension)

This keeps R memory usage minimal regardless of file size.

## Examples

``` r
if (FALSE) { # \dontrun{
# Standard mode (fast, loads into memory)
vcf_to_parquet("variants.vcf.gz", "variants.parquet")

# Streaming mode for large files (low memory)
vcf_to_parquet("huge.vcf.gz", "huge.parquet", streaming = TRUE)

# With zstd compression
vcf_to_parquet("variants.vcf.gz", "variants.parquet", compression = "zstd")

# Query with DuckDB
library(duckdb)
con <- dbConnect(duckdb())
dbGetQuery(con, "SELECT CHROM, POS, REF FROM 'variants.parquet' WHERE CHROM = 'chr1'")
} # }
```
