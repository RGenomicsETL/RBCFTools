# Get bcftools Library Directory

Returns the path to the bcftools library files for use in linking.

## Usage

``` r
bcftools_lib_dir()
```

## Value

A character string containing the path to the bcftools lib directory.

## Details

This directory contains `libbcftools.a` (static) and `libbcftools.so`
(shared) libraries.

## Examples

``` r
bcftools_lib_dir()
#> [1] "/home/runner/work/_temp/Library/RBCFTools/bcftools/lib"
```
