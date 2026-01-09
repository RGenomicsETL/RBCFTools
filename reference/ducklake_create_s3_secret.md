# Create or replace an S3 secret for DuckLake

Create or replace an S3 secret for DuckLake

## Usage

``` r
ducklake_create_s3_secret(
  con,
  name = "ducklake_s3",
  key_id,
  secret,
  endpoint = NULL,
  region = NULL,
  use_ssl = TRUE,
  url_style = "path",
  session_token = NULL
)
```

## Arguments

- con:

  A DuckDB connection.

- name:

  Secret name (identifier). Default: "ducklake_s3".

- key_id:

  S3 key ID.

- secret:

  S3 secret key.

- endpoint:

  Optional S3-compatible endpoint (e.g., "s3.us-east-1.amazonaws.com" or
  "minio:9000").

- region:

  Optional region.

- use_ssl:

  Logical, whether to use SSL. Default: TRUE.

- url_style:

  URL style ("path" or "virtual_host"). Default: "path".

- session_token:

  Optional session token.

## Value

Invisible NULL.
