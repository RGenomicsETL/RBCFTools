# Download a static MinIO server binary

Download a static MinIO server binary

## Usage

``` r
ducklake_download_minio(dest_dir = tempdir(), url = NULL, filename = "minio")
```

## Arguments

- dest_dir:

  Destination directory (created if missing).

- url:

  Optional download URL. Defaults to MinIO Linux build for host arch.

- filename:

  Output filename. Defaults to "minio".

## Value

Path to downloaded binary.
