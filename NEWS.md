# RBCFTools 1.23-0.0.2.9000 (development version)

## Parquet to VCF conversion (bcf_writer)

- `parquet_to_vcf()` - Convert Parquet files back to VCF/VCF.GZ/BCF format:
  - Uses VCF header stored in Parquet metadata for proper formatting
  - Supports both wide format (one row per variant) and tidy format (one row per variant-sample)
  - Tidy format is automatically pivoted back to wide VCF format
  - Proper handling of array columns (ALT, FILTER, multi-value INFO/FORMAT fields)
  - Auto-indexes output with bcftools (configurable via `index` parameter)
  - Output format determined by file extension (.vcf, .vcf.gz, .bcf)
  - Leverages bundled bcftools for validation and compression

## VCF header metadata in Parquet files

- `vcf_to_parquet_duckdb()` now embeds the full VCF header as Parquet key-value metadata by default:
  - `include_metadata = TRUE` (default) stores the complete VCF header in the Parquet file
  - Preserves all INFO, FORMAT, FILTER definitions, contigs, and sample names
  - Stores `tidy_format` flag indicating data layout ("true" or "false")
  - Enables round-trip back to VCF format by retaining full schema information
  - Also stores RBCFTools version for provenance tracking
  - Use `parquet_kv_metadata(file)` to read the header back from Parquet
  - Not supported with `partition_by` (Parquet limitation for partitioned writes)

- New helper functions:
  - `vcf_header_metadata(file)` - Extract full VCF header and package version
  - `parquet_kv_metadata(file)` - Read key-value metadata from Parquet files

## vcf_open_duckdb

- `vcf_open_duckdb()`**: Open VCF/BCF files as DuckDB tables or views
  - In-memory or file-backed database support
  - **Lazy by default**: `as_view = TRUE` (default) creates instant views that re-read VCF on each query
  - `as_view = FALSE` materializes data to a table for fast repeated queries
  - `tidy_format = TRUE` for one row per variant-sample with SAMPLE_ID column
  - `columns` parameter for selecting specific columns
  - `threads` parameter for parallel loading (requires indexed VCF):
    - For views: Creates UNION ALL of per-contig bcf_read() calls (parallelized at query time)
    - For tables: Loads each chromosome in parallel then unions
    - Falls back to single-threaded with warning if VCF not indexed
  - `partition_by` for creating partitioned tables
  - Returns a `vcf_duckdb` object with connection, table name, and metadata
  - `vcf_close_duckdb()` for proper cleanup
  - Print method shows connection details

## Native tidy_format in bcf_reader extension

- C-level `tidy_format` parameter The DuckDB bcf_reader extension now supports native tidy format output directly at the C level, emitting one row per variant-sample combination with a `SAMPLE_ID` column
  - Much faster than SQL-level UNNEST approach (no intermediate data duplication)
  - Works with projection pushdown - only reads requested columns
  - Integrates with all vcf_*duckdb functions via `tidy_format = TRUE` parameter

- Updated R wrapper functions with `tidy_format` parameter:
  - `vcf_query_duckdb(..., tidy_format = TRUE)` - query in tidy format
  - `vcf_count_duckdb(..., tidy_format = TRUE)` - count variant-sample rows
  - `vcf_schema_duckdb(..., tidy_format = TRUE)` - show tidy schema
  - `vcf_to_parquet_duckdb(..., tidy_format = TRUE)` - export in tidy format
  - `vcf_to_parquet_duckdb_parallel(..., tidy_format = TRUE)` - parallel tidy export
  - `ducklake_load_vcf(..., tidy_format = TRUE)` - load VCF in tidy format to DuckLake

- Removed SQL-based tidy functions (replaced by native `tidy_format` parameter):
  - Removed `vcf_to_parquet_tidy()` 
  - Removed `vcf_to_parquet_tidy_parallel()`
  - Removed `build_tidy_sql()` helper

## Hive-style partitioning for Parquet exports

- `partition_by` parameter for efficient per-sample queries on large cohorts:
  - `vcf_to_parquet_duckdb(..., partition_by = "SAMPLE_ID")` - create Hive-partitioned directory
  - `vcf_to_parquet_duckdb_parallel(..., partition_by = "SAMPLE_ID")` - parallel partitioned export
  - `ducklake_load_vcf(..., partition_by = "SAMPLE_ID")` - load partitioned VCF to DuckLake
  - Creates directory structure like `output_dir/SAMPLE_ID=HG00098/data_0.parquet`
  - DuckDB auto-generates Bloom filters for VARCHAR columns (SAMPLE_ID) for efficient row group pruning
  - Supports multi-column partitioning, e.g. `partition_by = c("CHROM", "SAMPLE_ID")`
  - Ideal for large cohort VCFs exported in tidy format

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
