# Get Path to htslib Plugins Directory

Returns the path to the directory containing htslib plugins (e.g., for
remote file access via libcurl, S3, GCS).

## Usage

``` r
htslib_plugins_dir()
```

## Value

A character string containing the path to the htslib plugins directory.

## Examples

``` r
htslib_plugins_dir()
#> [1] "/home/runner/work/_temp/Library/RBCFTools/htslib/libexec/htslib"
```
