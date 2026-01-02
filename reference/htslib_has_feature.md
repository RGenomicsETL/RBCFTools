# Check for a Specific htslib Feature

Checks if a specific feature is enabled in the bundled htslib library.

## Usage

``` r
htslib_has_feature(feature_id)

HTS_FEATURE_CONFIGURE

HTS_FEATURE_PLUGINS

HTS_FEATURE_LIBCURL

HTS_FEATURE_S3

HTS_FEATURE_GCS

HTS_FEATURE_LIBDEFLATE

HTS_FEATURE_LZMA

HTS_FEATURE_BZIP2

HTS_FEATURE_HTSCODECS
```

## Format

An object of class `integer` of length 1.

An object of class `integer` of length 1.

An object of class `integer` of length 1.

An object of class `integer` of length 1.

An object of class `integer` of length 1.

An object of class `integer` of length 1.

An object of class `integer` of length 1.

An object of class `integer` of length 1.

An object of class `integer` of length 1.

## Arguments

- feature_id:

  An integer feature ID. Use one of the `HTS_FEATURE_*` constants.

## Value

A logical value indicating if the feature is enabled.

## Examples

``` r
# Check for libcurl support (feature ID 1024)
htslib_has_feature(1024L)
#> [1] TRUE
```
