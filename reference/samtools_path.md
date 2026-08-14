# Get Path to Samtools Executable

Returns the path to the bundled Samtools executable.

## Usage

``` r
samtools_path()
```

## Value

A character string containing the path to the executable, or an empty
string on builds that do not provide command-line executables.

## Examples

``` r
samtools_path()
#> [1] "/home/runner/work/_temp/Library/RBCFTools/samtools/bin/samtools"
```
