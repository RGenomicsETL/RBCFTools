# Get number of variants using bcftools

Uses bundled bcftools to count variants efficiently. For indexed files,
this is very fast. Can also count per-chromosome.

## Usage

``` r
vcf_count_variants(filename, region = NULL)
```

## Arguments

- filename:

  Path to VCF/BCF file

- region:

  Optional region string (e.g., "chr1" or "chr1:1-1000")

## Value

Integer count of variants

## Examples

``` r
if (FALSE) { # \dontrun{
# Total variants
n <- vcf_count_variants("variants.vcf.gz")

# Variants on chr1
n_chr1 <- vcf_count_variants("variants.vcf.gz", region = "chr1")
} # }
```
