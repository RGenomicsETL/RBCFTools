# Changelog

## RBCFTools 1.23-0.0.2.9000 (development version)

### Native tidy_format in bcf_reader extension

- **C-level `tidy_format` parameter**: The DuckDB bcf_reader extension
  now supports native tidy format output directly at the C level,
  emitting one row per variant-sample combination with a `SAMPLE_ID`
  column
  - Much faster than SQL-level UNNEST approach (no intermediate data
    duplication)
  - Works with projection pushdown - only reads requested columns
  - Integrates with all vcf\_\*duckdb functions via `tidy_format = TRUE`
    parameter
- **Updated R wrapper functions** with `tidy_format` parameter:
  - `vcf_query_duckdb(..., tidy_format = TRUE)` - query in tidy format
  - `vcf_count_duckdb(..., tidy_format = TRUE)` - count variant-sample
    rows
  - `vcf_schema_duckdb(..., tidy_format = TRUE)` - show tidy schema
  - `vcf_to_parquet_duckdb(..., tidy_format = TRUE)` - export in tidy
    format
  - `vcf_to_parquet_duckdb_parallel(..., tidy_format = TRUE)` - parallel
    tidy export
  - `ducklake_load_vcf(..., tidy_format = TRUE)` - load VCF in tidy
    format to DuckLake
- **Removed SQL-based tidy functions** (replaced by native `tidy_format`
  parameter):
  - Removed `vcf_to_parquet_tidy()`
  - Removed `vcf_to_parquet_tidy_parallel()`
  - Removed `build_tidy_sql()` helper

### DuckLake utilities

- `allow_evolution` parameter for
  [`ducklake_load_vcf()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_load_vcf.md)
  and
  [`ducklake_register_parquet()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_register_parquet.md)
  to auto-add new columns via ALTER TABLE
- [`ducklake_snapshots()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_snapshots.md):
  list snapshot history
- [`ducklake_current_snapshot()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_current_snapshot.md):
  get current snapshot ID
- [`ducklake_set_commit_message()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_set_commit_message.md):
  set author/message for transactions
- [`ducklake_options()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_options.md):
  get DuckLake configuration
- [`ducklake_set_option()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_set_option.md):
  set compression, row group size, etc.
- [`ducklake_query_snapshot()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_query_snapshot.md):
  time travel queries at specific versions
- [`ducklake_list_files()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_list_files.md):
  list Parquet files managed by DuckLake
- [`ducklake_merge()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_merge.md):
  upsert data using MERGE INTO syntax

### Other changes

- added processx to suggests and use it instead of system2 in docs and
  tests
- renamed `vcf_query` to `vcf_query_arrow` and vcf_to_parquet to
  vcf_to_parquet

## RBCFTools 1.23-0.0.2

- renamed `vcf_query` to `vcf_query_arrow` and vcf_to_parquet to
  vcf_to_parquet
- Version pining release for production testing

## RBCFTools 1.23-0.0.1.9000 (development version)

- bug fixes in the cli argument passing

## RBCFTools 1.23-0.0.1

- First Release to start proper semantic versioning of the Package API

## RBCFTools 1.23-0.0.0.9000 (development version)

- **DuckLake catalog connection abstraction**: Support for DuckDB,
  SQLite, PostgreSQL, MySQL backends

  - [`ducklake_connect_catalog()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_connect_catalog.md):
    Abstracted connection function for multiple catalog backends
  - [`ducklake_create_catalog_secret()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_create_catalog_secret.md):
    Create catalog secrets for credential management
  - [`ducklake_list_secrets()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_list_secrets.md):
    List existing catalog secrets
  - [`ducklake_drop_secret()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_drop_secret.md):
    Remove catalog secrets
  - [`ducklake_update_secret()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_update_secret.md):
    Update existing catalog secrets
  - [`ducklake_parse_connection_string()`](https://rgenomicsetl.github.io/RBCFTools/reference/ducklake_parse_connection_string.md):
    Parse DuckLake connection strings

- **DuckDB bcf_reader extension**: Native DuckDB table function for
  querying VCF/BCF files directly.

  - [`bcf_reader_build()`](https://rgenomicsetl.github.io/RBCFTools/reference/bcf_reader_build.md):
    Build extension from source using package’s bundled htslib
  - [`vcf_duckdb_connect()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_duckdb_connect.md):
    Create DuckDB connection with extension loaded
  - [`vcf_query_duckdb()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_query_duckdb.md):
    Query VCF/BCF files with SQL

- DuckDB `bcf_reader` extension now auto-parses VEP-style annotations
  (INFO/CSQ, INFO/BCSQ, INFO/ANN) into typed `VEP_*` columns with all
  transcripts preserved as lists (using a vendored parser); builds
  remain self-contained with packaged htslib.

- Arrow VCF stream (nanoarrow) now aligns VEP parsing semantics with
  DuckDB (schema and typing improvements; transcript handling under
  active development).

- Parallel (contig-based) DuckDB extension Parquet converter.

- Package version reflects bundled htslib/bcftools versions.

- to parquet conversion now support parrallel threading based conversion

- vcf2parquet.R script in inst/

- **VCF to Arrow streaming** via nanoarrow (no `arrow` package
  required):

  - [`vcf_open_arrow()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_open_arrow.md):
    Open VCF/BCF as Arrow array stream
  - [`vcf_to_arrow()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_arrow.md):
    Convert to data.frame/tibble/batches
  - `vcf_to_parquet()`: Export to Parquet format via DuckDB
  - [`vcf_to_arrow_ipc()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_arrow_ipc.md):
    Export to Arrow IPC format (streaming, no memory overhead)
  - `vcf_query()`: SQL queries on VCF files via DuckDB

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
