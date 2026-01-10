# Update an existing DuckLake catalog secret

Update an existing DuckLake catalog secret

## Usage

``` r
ducklake_update_secret(
  con,
  name,
  connection_string,
  data_path = NULL,
  metadata_parameters = list()
)
```

## Arguments

- con:

  A DuckDB connection.

- name:

  Secret name to update.

- connection_string:

  New database connection string.

- data_path:

  New default data path. Optional.

- metadata_parameters:

  New named list of metadata parameters.

## Value

Invisible NULL.
