# Get variant counts per contig using bcftools

Uses bcftools index –stats to get per-contig variant counts. Requires an
indexed file.

## Usage

``` r
vcf_count_per_contig(filename)
```

## Arguments

- filename:

  Path to VCF/BCF file (must be indexed)

## Value

Named integer vector (names = contigs, values = variant counts)

## Examples

``` r
if (FALSE) { # \dontrun{
counts <- vcf_count_per_contig("variants.vcf.gz")
# chr1: 12345, chr2: 23456, ...
} # }
```
