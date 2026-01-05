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
  threads = 1L,
  index = NULL,
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

- threads:

  Number of parallel threads for processing (default: 1). When threads
  \> 1 and file is indexed, uses parallel processing by splitting work
  across chromosomes/contigs. Each thread processes different regions
  simultaneously. Requires indexed file. See
  [`vcf_to_parquet_parallel`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_parquet_parallel.md)
  for details.

- index:

  Optional explicit index file path

- ...:

  Additional arguments passed to vcf_open_arrow

## Value

Invisibly returns the output path

## Details

**Processing Modes:**

1.  **Standard mode** (`streaming = FALSE, threads = 1`): Loads entire
    VCF into memory as data.frame before writing. Fast for small-medium
    files.

2.  **Streaming mode** (`streaming = TRUE, threads = 1`): Two-stage
    streaming via temporary Arrow IPC file. Minimal memory usage for
    large files.

3.  **Parallel mode** (`threads > 1`): Requires indexed file. Splits
    work by chromosomes, processing multiple regions simultaneously.
    Near-linear speedup with thread count. Best for whole-genome VCFs.

## Examples

``` r
if (FALSE) { # \dontrun{
# Standard mode (fast, loads into memory)
vcf_to_parquet("variants.vcf.gz", "variants.parquet")

# Streaming mode for large files (low memory)
vcf_to_parquet("huge.vcf.gz", "huge.parquet", streaming = TRUE)

# Parallel mode for whole-genome VCF (requires index)
vcf_to_parquet("wgs.vcf.gz", "wgs.parquet", threads = 8)

# Parallel + streaming for massive files
vcf_to_parquet("wgs.vcf.gz", "wgs.parquet", threads = 16, streaming = TRUE)

# With zstd compression
vcf_to_parquet("variants.vcf.gz", "variants.parquet", compression = "zstd")

# Query with DuckDB
library(duckdb)
con <- dbConnect(duckdb())
dbGetQuery(con, "SELECT CHROM, POS, REF FROM 'variants.parquet' WHERE CHROM = 'chr1'")
} # }
```
