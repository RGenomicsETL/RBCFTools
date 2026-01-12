# RBCFTools 1.23-0.0.2

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
