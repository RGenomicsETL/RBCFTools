# Read VCF/BCF file into a data frame or list of batches

Convenience function to read an entire VCF file into memory as an R data
structure.

## Usage

``` r
vcf_to_arrow(filename, as = c("tibble", "data.frame", "batches"), ...)
```

## Arguments

- filename:

  Path to VCF or BCF file

- as:

  Character string specifying output format: "tibble", "data.frame", or
  "batches" (list of nanoarrow arrays)

- ...:

  Additional arguments passed to vcf_open_arrow

## Value

Depends on `as` parameter:

- "tibble": A tibble

- "data.frame": A data.frame

- "batches": A list of nanoarrow_array objects
