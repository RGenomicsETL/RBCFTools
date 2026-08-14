# Get Path to FastDup Executable

Returns the path to the bundled, RBCFTools-patched FastDup executable.

## Usage

``` r
fastdup_path()
```

## Value

A character string containing the executable path, or an empty string on
builds that do not provide command-line executables.

## Examples

``` r
fastdup_path()
#> [1] "/home/runner/work/_temp/Library/RBCFTools/fastdup/bin/fastdup"
```
