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
  index = NULL,
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

- index:

  Optional index file path. If NULL (default), uses auto-detection: VCF
  files try .tbi first, then .csi; BCF files use .csi only. Useful for
  non-standard index locations or presigned URLs with different paths.
  Alternatively, use htslib \##idx## syntax in filename (e.g.,
  "file.vcf.gz##idx##custom.tbi"). Note: Index is only required for
  region queries; whole-file streaming needs no index.

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
while (!is.null(batch <- stream$get_next())) {
    # Process batch...
    print(nanoarrow::convert_array(batch))
}

# With region filter
stream <- vcf_open_arrow("variants.vcf.gz", region = "chr1:1-1000000")

# With custom index file (useful for presigned URLs or non-standard locations)
stream <- vcf_open_arrow("variants.vcf.gz", index = "custom_path.tbi", region = "chr1")

# Convert to data frame
df <- vcf_to_arrow("variants.vcf.gz", as = "data.frame")

# Write to parquet (uses DuckDB, no arrow package needed)
vcf_to_parquet("variants.vcf.gz", "variants.parquet")
} # }
```
