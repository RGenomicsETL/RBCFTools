# Create an Arrow stream from a VCF/BCF file

Opens a VCF or BCF file and creates an Arrow array stream that produces
record batches. This enables efficient, streaming access to variant data
in Arrow format.

## Usage

``` r
vcf_open_arrow(
  filename,
  batch_size = 10000L,
  region = NULL,
  samples = NULL,
  include_info = TRUE,
  include_format = TRUE,
  threads = 0L
)
```

## Arguments

- filename:

  Path to VCF or BCF file

- batch_size:

  Number of records per batch (default: 10000)

- region:

  Optional region string for filtering (e.g., "chr1:1000-2000")

- samples:

  Optional sample filter (comma-separated names or "-" prefixed to
  exclude)

- include_info:

  Include INFO fields in output (default: TRUE)

- include_format:

  Include FORMAT/sample data in output (default: TRUE)

- threads:

  Number of decompression threads (default: 0 = auto)

## Value

A nanoarrow_array_stream object

## Examples

``` r
if (FALSE) { # \dontrun{
# Basic usage
stream <- vcf_open_arrow("variants.vcf.gz")

# Read batches
while (!is.null(batch <- nanoarrow::nanoarrow_array_stream_get_next(stream))) {
    # Process batch...
    print(nanoarrow::as_tibble(batch))
}

# With region filter
stream <- vcf_open_arrow("variants.vcf.gz", region = "chr1:1-1000000")

# Convert to data frame
df <- vcf_to_arrow_df("variants.vcf.gz")

# Write to parquet (requires arrow package)
arrow::write_parquet(vcf_to_arrow_df("variants.vcf.gz"), "variants.parquet")
} # }
```
