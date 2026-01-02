# Get Linker Flags for bcftools Library

Returns the linker flags needed to link against the bcftools library.

## Usage

``` r
bcftools_libs()
```

## Value

A character string containing linker flags including `-L` library path
and `-l` library name.

## Details

Note that bcftools library also depends on htslib, so you typically need
to include both `bcftools_libs()` and
[`htslib_libs()`](https://rgenomicsetl.github.io/RBCFTools/reference/htslib_libs.md)
in your linker flags.

## Examples

``` r
bcftools_libs()
#> [1] "-L/home/runner/work/_temp/Library/RBCFTools/bcftools/lib -lbcftools"
# Full linking: paste(RBCFTools::bcftools_libs(), RBCFTools::htslib_libs())
```
