# Get Linker Flags for htslib

Returns the linker flags needed to link against htslib.

## Usage

``` r
htslib_libs(static = FALSE)
```

## Arguments

- static:

  Logical. If `TRUE`, returns flags for static linking. If `FALSE`
  (default), returns flags for dynamic linking.

## Value

A character string containing linker flags including `-L` library path
and `-l` library names.

## Details

For dynamic linking, returns `-L<libdir> -lhts`. For static linking,
also includes the dependent libraries:
`-lpthread -lz -lm -lbz2 -llzma -ldeflate`.

## Examples

``` r
htslib_libs()
#> [1] "-L/home/runner/work/_temp/Library/RBCFTools/htslib/lib -lhts"
htslib_libs(static = TRUE)
#> [1] "-L/home/runner/work/_temp/Library/RBCFTools/htslib/lib -lhts -lpthread -lz -lm -lbz2 -llzma -ldeflate"
# Use in Makevars: PKG_LIBS = $(shell Rscript -e "cat(RBCFTools::htslib_libs())")
```
