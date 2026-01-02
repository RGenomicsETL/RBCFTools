# Get htslib Include Directory

Returns the path to the htslib header files for use in compilation.

## Usage

``` r
htslib_include_dir()
```

## Value

A character string containing the path to the htslib include directory.

## Details

This directory contains the htslib headers (e.g., `htslib/hts.h`,
`htslib/vcf.h`, etc.). Use this path with `-I` compiler flag when
compiling code that uses htslib.

## Examples

``` r
htslib_include_dir()
#> [1] "/home/runner/work/_temp/Library/RBCFTools/htslib/include"
```
