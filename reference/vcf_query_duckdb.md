# Query a VCF/BCF file using DuckDB SQL

Execute a SQL query against a VCF/BCF file using the bcf_reader
extension. The file is exposed as a table via the `bcf_read()` function.

## Usage

``` r
vcf_query_duckdb(
  file,
  extension_path = NULL,
  query = NULL,
  region = NULL,
  con = NULL
)
```

## Arguments

- file:

  Path to VCF, VCF.GZ, or BCF file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- query:

  SQL query string. Use `bcf_read('{file}')` to reference the file, or
  if NULL, returns all rows with `SELECT * FROM bcf_read('{file}')`.

- region:

  Optional genomic region for indexed files (e.g., "chr1:1000-2000")

- con:

  Optional existing DuckDB connection (with extension already loaded).
  If provided, extension_path is ignored.

## Value

A data.frame with query results

## Examples

``` r
if (FALSE) { # \dontrun{
# First build the extension
ext_path <- bcf_reader_build(tempdir())

# Basic query - get all variants
vcf_query_duckdb("variants.vcf.gz", ext_path)

# Count variants
vcf_query_duckdb("variants.vcf.gz", ext_path,
    query = "SELECT COUNT(*) FROM bcf_read('{file}')"
)

# Filter by chromosome
vcf_query_duckdb("variants.vcf.gz", ext_path,
    query = "SELECT CHROM, POS, REF, ALT FROM bcf_read('{file}') WHERE CHROM = '22'"
)

# Region query (requires index)
vcf_query_duckdb("variants.vcf.gz", ext_path, region = "chr1:1000000-2000000")

# Reuse connection for multiple queries
con <- vcf_duckdb_connect(ext_path)
vcf_query_duckdb("file1.vcf.gz", con = con)
vcf_query_duckdb("file2.vcf.gz", con = con)
DBI::dbDisconnect(con, shutdown = TRUE)
} # }
```
