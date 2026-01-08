# Read VCF with parsed VEP annotations

Opens a VCF file and parses VEP/BCSQ/ANN annotations into structured
columns. This is a convenience wrapper around `vcf_open_arrow` with VEP
parsing enabled.

## Usage

``` r
vcf_read_vep(filename, vep_tag = NULL, vep_columns = NULL, ...)
```

## Arguments

- filename:

  Path to VCF/BCF file

- vep_tag:

  Annotation tag to parse ("CSQ", "BCSQ", "ANN") or NULL for
  auto-detection

- vep_columns:

  Character vector of VEP fields to extract, or NULL for all fields

- ...:

  Additional arguments passed to `vcf_to_arrow`

## Value

Data frame with VCF columns plus parsed VEP fields as separate columns
prefixed with the tag name (e.g., "CSQ_Consequence", "CSQ_SYMBOL", etc.)

## Examples

``` r
if (FALSE) { # \dontrun{
df <- vcf_read_vep("annotated.vcf.gz",
  vep_columns = c("Consequence", "SYMBOL", "AF", "gnomAD_AF")
)

# Filter by gnomAD frequency
rare <- df[!is.na(df$CSQ_gnomAD_AF) & df$CSQ_gnomAD_AF < 0.001, ]
} # }
```
