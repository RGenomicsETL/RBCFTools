# Get htslib Library Directory

Returns the path to the htslib library files for use in linking.

## Usage

``` r
htslib_lib_dir()
```

## Value

A character string containing the path to the htslib lib directory.

## Details

This directory contains `libhts.a` (static) and `libhts.so` (shared)
libraries. Use this path with `-L` linker flag when linking against
htslib.

## Examples

``` r
htslib_lib_dir()
#> [1] "/home/runner/work/_temp/Library/RBCFTools/htslib/lib"
```
