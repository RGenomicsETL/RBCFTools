# RBCFTools 1.23-0.0.0.9000 (development version)


- to parquet conversion now support parrallel threading based conversion
- vcf2parquet.R script in inst/

- **VCF to Arrow streaming** via nanoarrow (no `arrow` package required):
  - `vcf_open_arrow()`: Open VCF/BCF as Arrow array stream
  - `vcf_to_arrow()`: Convert to data.frame/tibble/batches
  - `vcf_to_parquet()`: Export to Parquet format via DuckDB
  - `vcf_to_arrow_ipc()`: Export to Arrow IPC format (streaming, no memory overhead)
  - `vcf_query()`: SQL queries on VCF files via DuckDB

- **Streaming mode for large files**: `vcf_to_parquet(..., streaming = TRUE)` 
  streams VCF -> Arrow IPC -> Parquet without loading into R memory.
  Requires DuckDB nanoarrow extension (auto-installed on first use).

- **INFO and FORMAT field extraction**:
  - INFO fields properly parsed in Arrow streams as nested `INFO` data.frame column
  - FORMAT fields extracted as nested `samples` data.frame with sample names as columns
  - Proper GT field decoding (genotype integers to strings like "0|0", "0/1")
  - List-type FORMAT fields (AD, GL, PL) correctly extracted as Arrow list arrays
  - Header sanity checking based on VCF spec (matching htslib's `bcf_hdr_check_sanity()`)
  - R warnings emitted when correcting non-conformant headers

- bundles htslib/bcftools cli and libraries