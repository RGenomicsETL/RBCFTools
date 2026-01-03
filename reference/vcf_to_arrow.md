# Read VCF/BCF file into an Arrow Table or data frame

Convenience function to read an entire VCF file into memory as an
Arrow-compatible object.

## Usage

``` r
vcf_to_arrow(
  filename,
  as = c("tibble", "data.frame", "arrow_table", "batches"),
  ...
)
```

## Arguments

- filename:

  Path to VCF or BCF file

- as:

  Character string specifying output format: "arrow_table", "tibble",
  "data.frame", or "batches" (list of arrow arrays)

- ...:

  Additional arguments passed to vcf_open_arrow

## Value

Depends on `as` parameter:

- "arrow_table": An Arrow Table (requires arrow package)

- "tibble": A tibble

- "data.frame": A data.frame

- "batches": A list of nanoarrow_array objects
