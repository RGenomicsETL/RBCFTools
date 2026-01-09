# Download a static MinIO client (mc) binary

Download a static MinIO client (mc) binary

## Usage

``` r
ducklake_download_mc(
  dest_dir = tempdir(),
  url = "https://dl.min.io/client/mc/release/linux-amd64/mc",
  filename = "mc"
)
```

## Arguments

- dest_dir:

  Destination directory (created if missing).

- url:

  Optional download URL. Defaults to mc Linux amd64 build.

- filename:

  Output filename. Defaults to "mc".

## Value

Path to downloaded binary.
