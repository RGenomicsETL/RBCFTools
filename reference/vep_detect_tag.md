# Detect VEP annotation tag in VCF file

Checks for the presence of CSQ, BCSQ, or ANN annotation tags in the VCF
header and returns the first one found.

## Usage

``` r
vep_detect_tag(filename)
```

## Arguments

- filename:

  Path to VCF/BCF file

## Value

Character string with tag name ("CSQ", "BCSQ", or "ANN"), or NA if no
annotation found

## Examples

``` r
if (FALSE) { # \dontrun{
vep_detect_tag("annotated.vcf.gz")  # Returns "CSQ"
} # }
```
