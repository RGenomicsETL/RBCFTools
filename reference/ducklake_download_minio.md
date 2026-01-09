# Download a static MinIO server binary

Download a static MinIO server binary

## Usage

``` r
ducklake_download_minio(
  dest_dir = tempdir(),
  url = "https://dl.min.io/server/minio/release/linux-amd64/minio",
  filename = "minio"
)
```

## Arguments

- dest_dir:

  Destination directory (created if missing).

- url:

  Optional download URL. Defaults to MinIO Linux amd64 build.

- filename:

  Output filename. Defaults to "minio".

## Value

Path to downloaded binary.
