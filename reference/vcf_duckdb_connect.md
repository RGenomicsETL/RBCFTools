# Setup DuckDB connection with bcf_reader extension loaded

Creates a DuckDB connection and loads the bcf_reader extension for
VCF/BCF queries.

## Usage

``` r
vcf_duckdb_connect(
  extension_path,
  dbdir = ":memory:",
  read_only = FALSE,
  config = list()
)
```

## Arguments

- extension_path:

  Path to the bcf_reader.duckdb_extension file. Must be explicitly
  provided.

- dbdir:

  Database directory. Default ":memory:" for in-memory database.

- read_only:

  Logical, whether to open in read-only mode. Default FALSE.

- config:

  Named list of DuckDB configuration options.

## Value

A DuckDB connection object with bcf_reader extension loaded

## Examples

``` r
if (FALSE) { # \dontrun{
# First build the extension
ext_path <- bcf_reader_build(tempdir())

# Then connect
con <- vcf_duckdb_connect(ext_path)
DBI::dbGetQuery(con, "SELECT * FROM bcf_read('variants.vcf.gz') LIMIT 10")
DBI::dbDisconnect(con)
} # }
```
