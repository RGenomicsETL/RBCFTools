# Get contig names from VCF/BCF file

Extracts contig names from the VCF/BCF header using htslib.

## Usage

``` r
vcf_get_contigs(filename)
```

## Arguments

- filename:

  Path to VCF/BCF file

## Value

Character vector of contig names

## Examples

``` r
if (FALSE) { # \dontrun{
contigs <- vcf_get_contigs("variants.vcf.gz")
} # }
```
