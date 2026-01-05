# Check if VCF/BCF file has an index

Uses htslib to robustly check for index presence. Works with local
files, remote URLs (S3, GCS, HTTP), and custom index paths.

## Usage

``` r
vcf_has_index(filename, index = NULL)
```

## Arguments

- filename:

  Path to VCF/BCF file

- index:

  Optional explicit index path

## Value

Logical indicating if index exists

## Examples

``` r
if (FALSE) { # \dontrun{
vcf_has_index("variants.vcf.gz")
vcf_has_index("s3://bucket/file.vcf.gz")
vcf_has_index("file.vcf.gz", index = "custom.tbi")
} # }
```
