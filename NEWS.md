# RBCFTools 1.23-0.0.2.9000 (development version)

## Tidy VCF export

- `vcf_to_parquet_tidy()`: Export VCF/BCF to tidy (long) format Parquet where each row is one variant-sample combination
  - Adds `SAMPLE_ID` column and transforms `FORMAT_<field>_<sample>` to `FORMAT_<field>`
  - Supports single-sample (simple rename) and multi-sample (unnest-based unpivot) VCFs
  - Compatible with `threads` parameter for parallel processing
  - Ideal for combining multiple single-sample VCFs or appending to DuckLake tables

## DuckLake utilities

- `allow_evolution` parameter for `ducklake_load_vcf()` and `ducklake_register_parquet()` to auto-add new columns via ALTER TABLE
- `ducklake_snapshots()`: list snapshot history
- `ducklake_current_snapshot()`: get current snapshot ID
- `ducklake_set_commit_message()`: set author/message for transactions
- `ducklake_options()`: get DuckLake configuration
- `ducklake_set_option()`: set compression, row group size, etc.
- `ducklake_query_snapshot()`: time travel queries at specific versions
- `ducklake_list_files()`: list Parquet files managed by DuckLake
- `ducklake_merge()`: upsert data using MERGE INTO syntax

## Other changes

- added processx to suggests and use it instead of system2 in docs and tests
- renamed `vcf_query` to `vcf_query_arrow` and vcf_to_parquet to vcf_to_parquet

# RBCFTools 1.23-0.0.2

- renamed `vcf_query` to `vcf_query_arrow` and vcf_to_parquet to vcf_to_parquet
- Version pining release for production testing

# RBCFTools 1.23-0.0.1.9000  (development version)

- bug fixes in the cli argument passing


# RBCFTools 1.23-0.0.1

- First Release to start proper semantic versioning of the Package API

# RBCFTools 1.23-0.0.0.9000 (development version)

- **DuckLake catalog connection abstraction**: Support for DuckDB, SQLite, PostgreSQL, MySQL backends
  - `ducklake_connect_catalog()`: Abstracted connection function for multiple catalog backends
  - `ducklake_create_catalog_secret()`: Create catalog secrets for credential management
  - `ducklake_list_secrets()`: List existing catalog secrets
  - `ducklake_drop_secret()`: Remove catalog secrets
  - `ducklake_update_secret()`: Update existing catalog secrets
  - `ducklake_parse_connection_string()`: Parse DuckLake connection strings

- **DuckDB bcf_reader extension**: Native DuckDB table function for querying VCF/BCF files directly.
  - `bcf_reader_build()`: Build extension from source using package's bundled htslib
  - `vcf_duckdb_connect()`: Create DuckDB connection with extension loaded
  - `vcf_query_duckdb()`: Query VCF/BCF files with SQL

- DuckDB `bcf_reader` extension now auto-parses VEP-style annotations (INFO/CSQ, INFO/BCSQ, INFO/ANN) into typed `VEP_*` columns with all 
transcripts preserved as lists (using a vendored parser); builds remain self-contained with packaged htslib.

- Arrow VCF stream (nanoarrow) now aligns VEP parsing semantics with DuckDB (schema and typing improvements; transcript handling under active development).

- Parallel (contig-based) DuckDB extension Parquet converter.

- Package version reflects bundled htslib/bcftools versions.

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
