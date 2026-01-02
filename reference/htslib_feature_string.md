# Get htslib Feature String

Returns a human-readable string describing the enabled features in
htslib.

## Usage

``` r
htslib_feature_string()
```

## Value

A character string describing the enabled features.

## Examples

``` r
htslib_feature_string()
#> [1] "build=configure libcurl=yes S3=yes GCS=yes libdeflate=yes lzma=yes bzip2=yes plugins=yes plugin-path=/home/runner/work/_temp/Library/RBCFTools/htslib/libexec/htslib: htscodecs=1.6.5"
```
