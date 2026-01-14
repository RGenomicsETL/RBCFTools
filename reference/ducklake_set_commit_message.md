# Set commit message for current transaction

Must be called within a transaction (BEGIN/COMMIT block).

## Usage

``` r
ducklake_set_commit_message(
  con,
  catalog = "lake",
  author,
  message,
  extra_info = NULL
)
```

## Arguments

- con:

  DuckDB connection with DuckLake attached.

- catalog:

  DuckLake catalog name.

- author:

  Author name.

- message:

  Commit message.

- extra_info:

  Optional JSON string with extra metadata.

## Value

Invisible NULL.
