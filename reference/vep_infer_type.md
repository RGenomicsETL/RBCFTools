# Infer type from VEP field name

Uses bcftools split-vep conventions to infer the type of a VEP field
from its name.

## Usage

``` r
vep_infer_type(field_name)
```

## Arguments

- field_name:

  Character vector of field names

## Value

Character vector of inferred types ("Integer", "Float", "String")

## Details

Known integer fields: DISTANCE, STRAND, TSL, GENE_PHENO, HGVS_OFFSET,
MOTIF_POS, `existing_*ORFs`, `SpliceAI_pred_DP_*`

Known float fields: AF, `*_AF` (e.g., `gnomAD_AF`), `MAX_AF_*`,
MOTIF_SCORE_CHANGE, `SpliceAI_pred_DS_*`

All others default to String.

## Examples

``` r
vep_infer_type(c("SYMBOL", "AF", "gnomAD_AF", "DISTANCE", "SpliceAI_pred_DS_AG"))
#> [1] "String"  "Float"   "Float"   "Integer" "Float"  
# [1] "String" "Float" "Float" "Integer" "Float"
```
