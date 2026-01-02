# Get All Linking Information for RBCFTools

Returns a list with all paths and flags needed for linking against
htslib and bcftools from this package.

## Usage

``` r
linking_info()
```

## Value

A named list with the following elements:

- htslib_include:

  Path to htslib include directory

- htslib_lib:

  Path to htslib library directory

- bcftools_lib:

  Path to bcftools library directory

- cflags:

  Compiler flags for htslib

- htslib_libs:

  Linker flags for htslib (dynamic)

- htslib_libs_static:

  Linker flags for htslib (static)

- bcftools_libs:

  Linker flags for bcftools

- all_libs:

  Combined linker flags for both bcftools and htslib

## Examples

``` r
info <- linking_info()
info$cflags
#> [1] "-I/home/runner/work/_temp/Library/RBCFTools/htslib/include"
info$all_libs
#> [1] "-L/home/runner/work/_temp/Library/RBCFTools/bcftools/lib -lbcftools -L/home/runner/work/_temp/Library/RBCFTools/htslib/lib -lhts"
```
