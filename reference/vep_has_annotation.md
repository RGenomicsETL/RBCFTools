# Check if VCF has VEP-style annotations

Check if VCF has VEP-style annotations

## Usage

``` r
vep_has_annotation(filename)
```

## Arguments

- filename:

  Path to VCF/BCF file

## Value

Logical indicating presence of CSQ, BCSQ, or ANN

## Examples

``` r
if (FALSE) { # \dontrun{
if (vep_has_annotation("file.vcf.gz")) {
  schema <- vep_get_schema("file.vcf.gz")
}
} # }
```
