# Get contig lengths from VCF/BCF file

Extracts contig names and lengths from the VCF/BCF header.

## Usage

``` r
vcf_get_contig_lengths(filename)
```

## Arguments

- filename:

  Path to VCF/BCF file

## Value

Named integer vector (names = contigs, values = lengths)

## Examples

``` r
if (FALSE) { # \dontrun{
lengths <- vcf_get_contig_lengths("variants.vcf.gz")
} # }
```
