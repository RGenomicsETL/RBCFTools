# Changelog

## RBCFTools 1.23-0.0.0.9000 (development version)

- DuckDB `bcf_reader` extension now auto-parses VEP-style annotations
  (INFO/CSQ, INFO/BCSQ, INFO/ANN) into typed `VEP_*` columns with all
  transcripts preserved as lists (using a vendored parser); builds
  remain self-contained with packaged htslib.

- Arrow VCF stream (nanoarrow) now aligns VEP parsing semantics with
  DuckDB (schema and typing improvements; transcript handling under
  active development).

- Parallel (contig-based) DuckDB extension Parquet converter.

- Package version reflects bundled htslib/bcftools versions.

- **DuckDB bcf_reader extension**: Native DuckDB table function for
  querying VCF/BCF files directly.

  - [`bcf_reader_build()`](https://rgenomicsetl.github.io/RBCFTools/reference/bcf_reader_build.md):
    Build extension from source using package’s bundled htslib
  - [`vcf_duckdb_connect()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_duckdb_connect.md):
    Create DuckDB connection with extension loaded
  - [`vcf_query_duckdb()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_query_duckdb.md):
    Query VCF/BCF files with SQL

- to parquet conversion now support parrallel threading based conversion

- vcf2parquet.R script in inst/

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

- **INFO and FORMAT field extraction**:

  - INFO fields properly parsed in Arrow streams as nested `INFO`
    data.frame column
  - FORMAT fields extracted as nested `samples` data.frame with sample
    names as columns
  - Proper GT field decoding (genotype integers to strings like “0\|0”,
    “0/1”)
  - List-type FORMAT fields (AD, GL, PL) correctly extracted as Arrow
    list arrays
  - Header sanity checking based on VCF spec (matching htslib’s
    `bcf_hdr_check_sanity()`)
  - R warnings emitted when correcting non-conformant headers

- bundles htslib/bcftools cli and libraries
