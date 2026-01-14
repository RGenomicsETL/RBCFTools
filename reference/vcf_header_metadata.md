# Extract VCF header for Parquet key-value storage

Extracts the full VCF header from a file for embedding in Parquet
metadata. This allows round-tripping back to VCF format by preserving
all header information (INFO, FORMAT, FILTER definitions, contigs,
samples).

## Usage

``` r
vcf_header_metadata(file)
```

## Arguments

- file:

  Path to VCF, VCF.GZ, or BCF file

## Value

A named list with two elements:

- `vcf_header`: The complete VCF header (all lines starting with \#)

- `RBCFTools_version`: Package version that created the Parquet

## Examples

``` r
if (FALSE) { # \dontrun{
vcf_file <- system.file("extdata", "1000G_3samples.vcf.gz", package = "RBCFTools")
meta <- vcf_header_metadata(vcf_file)
cat(meta$vcf_header)
} # }
```
