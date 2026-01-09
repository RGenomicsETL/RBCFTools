# Download a static MinIO client (mc) binary

Download a static MinIO client (mc) binary

## Usage

``` r
ducklake_download_mc(dest_dir = tempdir(), url = NULL, filename = "mc")
```

## Arguments

- dest_dir:

  Destination directory (created if missing).

- url:

  Optional download URL. Defaults to mc Linux build for host arch.

- filename:

  Output filename. Defaults to "mc".

## Value

Path to downloaded binary.
