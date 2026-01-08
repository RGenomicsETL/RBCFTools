# List VEP annotation fields in a VCF file

Convenience function to display available VEP fields and their types.

## Usage

``` r
vep_list_fields(filename)
```

## Arguments

- filename:

  Path to VCF/BCF file

## Value

Invisibly returns the schema data frame

## Examples

``` r
if (FALSE) { # \dontrun{
vep_list_fields("annotated.vcf.gz")
# VEP Annotation Tag: CSQ
# Fields (78 total):
#   1. Allele (String)
#   2. Consequence (String, list)
#   3. IMPACT (String)
#   ...
} # }
```
