# Write VCF/BCF to Arrow IPC format

Converts a VCF/BCF file to Arrow IPC (Feather v2) format for efficient
storage and interoperability with Arrow-compatible tools. Uses DuckDB
for IPC writing (no arrow package required).

## Usage

``` r
vcf_to_arrow_ipc(input_vcf, output_ipc, ...)
```

## Arguments

- input_vcf:

  Path to input VCF or BCF file

- output_ipc:

  Path for output Arrow IPC file (typically .arrow or .arrows extension)

- ...:

  Additional arguments passed to vcf_open_arrow

## Value

Invisibly returns the output path

## Examples

``` r
vcf_to_arrow_ipc("variants.vcf.gz", "variants.arrow")
#> Error in normalizePath(filename, mustWork = TRUE): path[1]="variants.vcf.gz": No such file or directory

# Read back with nanoarrow
stream <- nanoarrow::read_nanoarrow("variants.arrow")
#> Warning: cannot open file 'variants.arrow': No such file or directory
#> Error in open.connection(x, "rb"): cannot open the connection
df <- as.data.frame(stream)
#> Error: object 'stream' not found

# Or query with DuckDB
library(duckdb)
#> Loading required package: DBI
con <- dbConnect(duckdb())
dbGetQuery(con, "SELECT * FROM 'variants.arrow' LIMIT 10")
#> Error in dbSendQuery(conn, statement, ...): Catalog Error: Table with name variants.arrow does not exist!
#> Did you mean "sqlite_schema"?
#> 
#> LINE 1: SELECT * FROM 'variants.arrow' LIMIT 10
#>                       ^
#> ℹ Context: rapi_prepare
#> ℹ Error type: CATALOG
```
