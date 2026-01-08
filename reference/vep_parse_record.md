# Parse VEP annotation string

Parses a CSQ/BCSQ/ANN annotation string into a structured list of data
frames, one per transcript/consequence.

## Usage

``` r
vep_parse_record(csq_value, filename, schema = NULL)
```

## Arguments

- csq_value:

  Raw annotation string (pipe-delimited, comma-separated for multiple
  transcripts)

- filename:

  Path to VCF file (for schema extraction)

- schema:

  Optional pre-parsed schema from
  [`vep_get_schema()`](https://rgenomicsetl.github.io/RBCFTools/reference/vep_get_schema.md).
  If NULL, extracted from filename.

## Value

List of data frames, one per transcript. Each data frame has one row
with columns corresponding to annotation fields, properly typed.

## Examples

``` r
if (FALSE) { # \dontrun{
# Get a CSQ value from a VCF
csq <- "A|missense_variant|MODERATE|BRCA1|..."
result <- vep_parse_record(csq, "annotated.vcf.gz")
result[[1]]$Consequence  # "missense_variant"
result[[1]]$AF           # 0.001 (numeric)
} # }
```
