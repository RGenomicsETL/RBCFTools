# Get VEP annotation schema from VCF header

Parses the VEP/BCSQ/ANN header to extract field names and inferred
types. Types are inferred using bcftools split-vep conventions.

## Usage

``` r
vep_get_schema(filename, tag = NULL)
```

## Arguments

- filename:

  Path to VCF/BCF file

- tag:

  Optional annotation tag ("CSQ", "BCSQ", "ANN"). If NULL (default),
  auto-detects.

## Value

Data frame with columns:

- name:

  Field name (e.g., "Consequence", "SYMBOL", "AF")

- type:

  Inferred type ("Integer", "Float", "String")

- index:

  Position in pipe-delimited string (0-based)

- is_list:

  Whether field can have multiple values

The tag name is stored as an attribute.

## Examples

``` r
if (FALSE) { # \dontrun{
schema <- vep_get_schema("vep_annotated.vcf.gz")
print(schema)
#       name    type index is_list
# 1   Allele  String     0   FALSE
# 2   Consequence String  1    TRUE
# 3   IMPACT  String     2   FALSE
# ...
attr(schema, "tag")  # "CSQ"
} # }
```
