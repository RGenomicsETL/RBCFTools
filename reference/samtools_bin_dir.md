# Get Path to Samtools Binary Directory

Returns the path to the directory containing the bundled Samtools
executable.

## Usage

``` r
samtools_bin_dir()
```

## Value

A character string containing the path to the Samtools binary directory,
or an empty string when it is unavailable.

## Examples

``` r
samtools_bin_dir()
#> [1] "/home/runner/work/_temp/Library/RBCFTools/samtools/bin"
```
