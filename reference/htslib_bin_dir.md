# Get Path to htslib Binary Directory

Returns the path to the directory containing htslib executables.

## Usage

``` r
htslib_bin_dir()
```

## Value

A character string containing the path to the htslib bin directory.

## Details

The directory contains the following tools:

- `annot-tsv` - Annotate TSV files

- `bgzip` - Block gzip compression

- `htsfile` - Identify file format

- `ref-cache` - Reference sequence cache management

- `tabix` - Index and query TAB-delimited files

## Examples

``` r
htslib_bin_dir()
#> [1] "/home/runner/work/_temp/Library/RBCFTools/htslib/bin"
```
