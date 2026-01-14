# Query VCF/BCF with DuckDB

Enables SQL queries on VCF files using DuckDB. This allows powerful
filtering, aggregation, and joining operations.

## Usage

``` r
vcf_query_arrow(vcf_files, query, ...)
```

## Arguments

- vcf_files:

  Character vector of VCF file paths

- query:

  SQL query string. Use "vcf" as the table name.

- ...:

  Additional arguments passed to vcf_open_arrow

## Value

Query result as a data frame

## Examples

``` r
if (FALSE) { # \dontrun{
# Count variants per chromosome
vcf_query_arrow(
    "variants.vcf.gz",
    "SELECT CHROM, COUNT(*) as n FROM vcf GROUP BY CHROM"
)

# Filter high-quality variants
vcf_query_arrow(
    "variants.vcf.gz",
    "SELECT * FROM vcf WHERE QUAL > 30"
)

# Join multiple VCF files
vcf_query_arrow(
    c("sample1.vcf.gz", "sample2.vcf.gz"),
    "SELECT * FROM vcf WHERE POS BETWEEN 1000 AND 2000"
)
} # }
```
