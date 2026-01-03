# Write VCF/BCF to Arrow IPC format

Converts a VCF/BCF file to Arrow IPC stream format for efficient storage
and interoperability with Arrow-compatible tools. Uses nanoarrow's
native IPC writer for streaming output.

## Usage

``` r
vcf_to_arrow_ipc(input_vcf, output_ipc, ...)
```

## Arguments

- input_vcf:

  Path to input VCF or BCF file

- output_ipc:

  Path for output Arrow IPC file (typically .arrows extension)

- ...:

  Additional arguments passed to vcf_open_arrow

## Value

Invisibly returns the output path

## Examples

``` r
if (FALSE) { # \dontrun{
vcf_to_arrow_ipc("variants.vcf.gz", "variants.arrows")

# Read back with nanoarrow
stream <- nanoarrow::read_nanoarrow("variants.arrows")
df <- as.data.frame(stream)

# Or query with DuckDB
library(duckdb)
con <- dbConnect(duckdb())
dbGetQuery(con, "SELECT * FROM 'variants.arrows' LIMIT 10")
} # }
```
