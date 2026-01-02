# Get htslib Capabilities

Returns a named list of all capabilities of the bundled htslib library.

## Usage

``` r
htslib_capabilities()
```

## Value

A named list with logical values for each capability:

- configure:

  Whether ./configure was used to build.

- plugins:

  Whether plugins are enabled.

- libcurl:

  Whether libcurl support is enabled.

- s3:

  Whether S3 support is enabled.

- gcs:

  Whether Google Cloud Storage support is enabled.

- libdeflate:

  Whether libdeflate compression is enabled.

- lzma:

  Whether LZMA compression is enabled.

- bzip2:

  Whether bzip2 compression is enabled.

- htscodecs:

  Whether htscodecs library is available.

## Examples

``` r
caps <- htslib_capabilities()
caps$libcurl
#> [1] TRUE
caps$s3
#> [1] TRUE
```
