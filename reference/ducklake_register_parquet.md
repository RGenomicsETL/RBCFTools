# Register existing Parquet files in a DuckLake table

Adds Parquet files that already exist (from prior ETL) to a DuckLake
table. This is a catalog-only operation; data files are not copied or
moved.

## Usage

``` r
ducklake_register_parquet(con, table, parquet_files, create_table = TRUE)
```

## Arguments

- con:

  DuckDB connection with DuckLake attached.

- table:

  Target table name (optionally qualified, e.g., "lake.variants").

- parquet_files:

  Character vector of Parquet file paths/URIs.

- create_table:

  Logical, create the table if it doesn't exist. Default: TRUE. When
  TRUE, schema is inferred from the first Parquet file.

## Value

Invisibly returns the number of files registered.

## Details

This function uses DuckLake's `ducklake_add_data_files()` to register
external Parquet files in the catalog. The files must already exist and
have a schema compatible with the target table.

## Examples

``` r
if (FALSE) { # \dontrun{
# Register a Parquet file created by vcf_to_parquet_duckdb()
ducklake_register_parquet(con, "variants", "s3://bucket/variants.parquet")
} # }
```
