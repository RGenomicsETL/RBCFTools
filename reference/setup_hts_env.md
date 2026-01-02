# Setup Environment for Remote File Access

Sets the `HTS_PATH` environment variable to point to the bundled htslib
plugins directory. This is required for S3, GCS, and other remote file
access via libcurl.

## Usage

``` r
setup_hts_env()
```

## Value

Invisibly returns the previous value of `HTS_PATH` (or `NA` if unset).

## Details

Call this function before using bcftools/htslib tools with remote URLs
(s3://, gs://, http://, etc.). The function sets `HTS_PATH` to the
package's plugin directory so htslib can find `hfile_libcurl.so` and
`hfile_gcs.so`.

## Examples

``` r
setup_hts_env()
# Now bcftools can access S3 URLs
```
