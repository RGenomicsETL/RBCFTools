# Build SQL for tidy (unpivot) transformation

Build SQL for tidy (unpivot) transformation

## Usage

``` r
build_tidy_sql(
  input_file,
  region,
  schema,
  sample_names,
  format_fields,
  format_cols,
  columns = NULL
)
```

## Arguments

- input_file:

  VCF file path

- region:

  Optional region

- schema:

  Schema data frame

- sample_names:

  Vector of sample names

- format_fields:

  Vector of FORMAT field names (GT, DP, etc.)

- format_cols:

  Vector of all FORMAT column names

- columns:

  Optional vector of non-FORMAT columns to include

## Value

SQL query string
