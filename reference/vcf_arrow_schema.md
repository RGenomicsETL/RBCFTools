# Get the Arrow schema for a VCF file

Reads the header of a VCF/BCF file and returns the corresponding Arrow
schema.

## Usage

``` r
vcf_arrow_schema(filename)
```

## Arguments

- filename:

  Path to VCF or BCF file

## Value

A nanoarrow_schema object
