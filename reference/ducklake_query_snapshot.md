# Query table at a specific snapshot (time travel)

Query table at a specific snapshot (time travel)

## Usage

``` r
ducklake_query_snapshot(con, table, snapshot_id, query = "SELECT * FROM tbl")
```

## Arguments

- con:

  DuckDB connection with DuckLake attached.

- table:

  Table name.

- snapshot_id:

  Snapshot version to query.

- query:

  SQL query (use 'tbl' as table alias).

## Value

Query result as data frame.
