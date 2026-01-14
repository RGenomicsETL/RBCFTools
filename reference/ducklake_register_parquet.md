# Register existing Parquet files in a DuckLake table

Adds Parquet files that already exist (from prior ETL) to a DuckLake
table. This is a catalog-only operation; data files are not copied or
moved.

## Usage

``` r
ducklake_register_parquet(
  con,
  table,
  parquet_files,
  create_table = TRUE,
  allow_missing = FALSE,
  ignore_extra_columns = FALSE,
  allow_evolution = FALSE
)
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

- allow_missing:

  Logical, allow missing columns (filled with defaults). Default: FALSE.

- ignore_extra_columns:

  Logical, ignore extra columns in files. Default: FALSE.

- allow_evolution:

  Logical, evolve table schema by adding new columns from files.
  Default: FALSE. When TRUE, new columns found in files are added via
  ALTER TABLE before registration, making all columns queryable.

## Value

Invisibly returns the number of files registered.

## Details

This function uses DuckLake's `ducklake_add_data_files()` to register
external Parquet files in the catalog. The files must already exist and
have a schema compatible with the target table.

**Schema Evolution (`allow_evolution = TRUE`):** When enabled, the
function compares each file's schema against the table schema and adds
any missing columns via `ALTER TABLE ADD COLUMN` before registration.
This allows combining VCF files with different annotations (e.g., VEP
columns) into a single table where all columns are queryable.

## Examples

``` r
if (FALSE) { # \dontrun{
# Register a Parquet file created by vcf_to_parquet_duckdb()
ducklake_register_parquet(con, "variants", "s3://bucket/variants.parquet")

# Register with schema evolution (add new columns from file)
ducklake_register_parquet(con, "variants", "s3://bucket/vep_variants.parquet",
  allow_evolution = TRUE
)
} # }
```
