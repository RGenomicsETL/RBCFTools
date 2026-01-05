# Changelog

## RBCFTools 1.23-0.0.0.9000 (development version)

- **VCF to Arrow streaming** via nanoarrow (no `arrow` package
  required):

  - [`vcf_open_arrow()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_open_arrow.md):
    Open VCF/BCF as Arrow array stream
  - [`vcf_to_arrow()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_arrow.md):
    Convert to data.frame/tibble/batches
  - [`vcf_to_parquet()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_parquet.md):
    Export to Parquet format via DuckDB
  - [`vcf_to_arrow_ipc()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_arrow_ipc.md):
    Export to Arrow IPC format (streaming, no memory overhead)
  - [`vcf_query()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_query.md):
    SQL queries on VCF files via DuckDB

- **Streaming mode for large files**:
  `vcf_to_parquet(..., streaming = TRUE)` streams VCF -\> Arrow IPC -\>
  Parquet without loading into R memory. Requires DuckDB nanoarrow
  extension (auto-installed on first use).

- **FORMAT field extraction**:

  - Proper GT field decoding (genotype integers to strings like “0\|0”,
    “0/1”)
  - List-type FORMAT fields (AD, GL, PL) correctly extracted as Arrow
    list arrays
  - Header sanity checking based on VCF spec (matching htslib’s
    `bcf_hdr_check_sanity()`)
  - R warnings emitted when correcting non-conformant headers

- bundles htslib/bcftools cli and libraries
