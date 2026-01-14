# Merge/upsert data into a DuckLake table

Merge/upsert data into a DuckLake table

## Usage

``` r
ducklake_merge(
  con,
  target,
  source,
  on_cols,
  when_matched = "UPDATE",
  when_not_matched = "INSERT",
  update_cols = NULL
)
```

## Arguments

- con:

  DuckDB connection with DuckLake attached.

- target:

  Target table name.

- source:

  Source table/query.

- on_cols:

  Column(s) to match on.

- when_matched:

  Action when matched: "UPDATE", "DELETE", or NULL.

- when_not_matched:

  Action when not matched: "INSERT" or NULL.

- update_cols:

  Columns to update (NULL = all columns).

## Value

Number of rows affected.
