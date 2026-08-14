# Get Samtools Version

Runs the bundled Samtools executable and returns its version.

## Usage

``` r
samtools_version()
```

## Value

A character string containing the Samtools version, or `NA` when the
executable is unavailable on the current build.

## Examples

``` r
samtools_version()
#> [1] "1.24"
```
