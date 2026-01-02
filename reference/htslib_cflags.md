# Get Compiler Flags for htslib

Returns the compiler flags (CFLAGS/CPPFLAGS) needed to compile code that
uses htslib.

## Usage

``` r
htslib_cflags()
```

## Value

A character string containing compiler flags including the `-I` include
path.

## Examples

``` r
htslib_cflags()
#> [1] "-I/home/runner/work/_temp/Library/RBCFTools/htslib/include"
# Use in Makevars: PKG_CPPFLAGS = $(shell Rscript -e "cat(RBCFTools::htslib_cflags())")
```
