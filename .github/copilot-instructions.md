# RBCFTools Agent Guidelines

This document provides guidance for AI agents working on the RBCFTools codebase, incorporating lessons learned from DuckLake extension integration and debugging.

## DuckLake Extension API & Patterns

### Core DuckLake Concepts

DuckLake is a DuckDB extension that provides lakehouse functionality with:
- **Metadata catalog**: Stores table schemas, snapshots, and metadata (can be DuckDB, SQLite, PostgreSQL, MySQL)
- **Data storage**: Parquet files in local filesystem, S3, GCS, or other supported backends
- **Time travel**: Snapshot-based versioning for querying historical data
- **ACID compliance**: Transaction support with delete+insert pattern for updates

### Connection Patterns

#### 1. Direct Connection (Recommended for simple cases)
```sql
ATTACH 'ducklake:path/to/catalog.ducklake' AS my_lake (DATA_PATH 'path/to/parquet/');
```

#### 2. Secret-Based Connection (Recommended for production)
```sql
-- Create secret
CREATE SECRET my_lake_secret (
  TYPE ducklake,
  METADATA_PATH 'path/to/catalog.ducklake',
  DATA_PATH 'path/to/parquet/'
);

-- Use secret
ATTACH 'ducklake:my_lake_secret' AS my_lake;
```

#### 3. Multi-Backend Support
```sql
-- PostgreSQL backend
ATTACH 'ducklake:postgres:user:pass@host:5432/db' AS lake (DATA_PATH 's3://bucket/');

-- SQLite backend  
ATTACH 'ducklake:sqlite:path/to/catalog.db' AS lake (DATA_PATH 'data/');

-- MySQL backend (not recommended - has known issues)
ATTACH 'ducklake:mysql:user:pass@host:3306/db' AS lake (DATA_PATH 'data/');
```

### Supported ATTACH Options

From DuckDB v1.3+ documentation, these options are supported:
- `CREATE_IF_NOT_EXISTS` (default: true)
- `DATA_PATH` (required for new lakes)
- `READ_ONLY` (default: false) 
- `DATA_INLINING_ROW_LIMIT` (default: 0)
- `ENCRYPTED` (default: false)
- `METADATA_CATALOG` (default: auto-generated)
- `METADATA_SCHEMA` (default: "main")
- `METADATA_PARAMETERS` (MAP of parameters for backend)
- `MIGRATE_IF_REQUIRED` (default: true)
- `OVERRIDE_DATA_PATH` (default: true)
- `SNAPSHOT_TIME` (for time travel queries)
- `SNAPSHOT_VERSION` (for time travel queries)

**❌ CRITICAL**: `SECRET` option is NOT supported in ATTACH statements. Secrets must be referenced in the connection string only.

### Secret Management

#### Creating DuckLake Catalog Secrets
```sql
-- Named secret
CREATE SECRET my_catalog (
  TYPE ducklake,
  METADATA_PATH 'postgres:dbname=lake',
  DATA_PATH 's3://my-bucket/',
  METADATA_PARAMETERS MAP {
    'TYPE': 'postgres', 
    'SECRET': 'postgres_secret'
  }
);

-- Persistent secret (survives restarts)
CREATE PERSISTENT SECRET my_catalog (...);
```

#### Querying Secrets
```sql
-- List all secrets
SELECT * FROM duckdb_secrets();

-- DuckLake secrets have these columns:
-- name, type, provider, persistent, storage, scope, secret_string
```

### Backend-Specific Requirements

#### PostgreSQL Backend
```bash
# Required extensions
INSTALL postgres;
INSTALL postgres_scanner;
LOAD postgres;
LOAD postgres_scanner;
```

#### SQLite Backend  
```bash
# Required extensions
INSTALL sqlite_scanner;
LOAD sqlite_scanner;
```

#### S3/Cloud Storage
```bash
# Create S3 secret first (for cloud DATA_PATH)
CREATE SECRET s3_creds (
  TYPE s3,
  KEY_ID 'minioadmin',
  SECRET 'minioadmin', 
  ENDPOINT 'localhost:9000',
  USE_SSL false,
  URL_STYLE 'path'
);
```

## Implementation Patterns for RBCFTools

### 1. Error Handling for DuckLake

```r
# Always catch DuckDB extension errors
tryCatch({
  DBI::dbExecute(con, attach_sql)
}, error = function(e) {
  if (grepl("Unsupported option.*secret", conditionMessage(e))) {
    stop("SECRET option not supported in DuckLake ATTACH. Use secret_name parameter instead.", call. = FALSE)
  }
  # Re-throw other DuckLake-specific errors
  stop(conditionMessage(e), call. = FALSE)
})
```

### 2. Secret String Parsing

```r
# DuckLake secrets store data as semicolon-separated string
# Format: "name=test;type=ducklake;provider=config;...;metadata_path=path;data_path=path"
parse_secret_field <- function(secret_str, field_name) {
  pattern <- sprintf("%s=([^;]*)", field_name)
  match <- regexpr(pattern, secret_str, perl = TRUE)
  if (match > 0) {
    start <- attr(match, "capture.start")[1]
    length <- attr(match, "capture.length")[1]
    if (start > 0 && length > 0) {
      return(substr(secret_str, start, start + length - 1))
    }
  }
  return(NA_character_)
}
```

### 3. Connection String Formatting

```r
ducklake_format_connection_string <- function(backend, connection_string) {
  switch(backend,
    "duckdb" = connection_string,
    "sqlite" = paste0("sqlite:", connection_string),  # NOT sqlite://
    "postgresql" = paste0("postgresql://", connection_string),
    "mysql" = paste0("mysql://", connection_string)
  )
}
```

### 4. Option Filtering for ATTACH

```r
# Filter out unsupported options when using secrets
build_attach_options <- function(opts, secret_name) {
  if (!is.null(secret_name)) {
    # Remove DATA_PATH when using secret (already in secret)
    opts <- opts[!names(opts) %in% c("DATA_PATH", "SECRET")]
  }
  # Format options for SQL
  # ... (convert logicals to "true"/"false", quote strings, etc.)
}
```

## Debugging DuckLake Issues

### Common Error Patterns

1. **"Unsupported option secret for DuckLake"**
   - Cause: Adding `SECRET` option to ATTACH statement
   - Fix: Use secret name in connection string instead

2. **"Unique file handle conflict"** 
   - Cause: Trying to attach same database with different aliases
   - Fix: Use different database files or detach first

3. **Extension not found errors**
   - Cause: Missing required scanner extensions for backends
   - Fix: Install and load postgres_scanner, sqlite_scanner, etc.

4. **Connection string format errors**
   - Cause: Using wrong protocol (sqlite:// vs sqlite:)
   - Fix: Follow DuckLake documentation exactly

### Debugging Checklist

```r
# 1. Check extension loading
duckdb_extensions <- dbGetQuery(con, "SELECT * FROM duckdb_extensions()")
if (!"ducklake" %in% duckdb_extensions$extensionname) {
  stop("DuckLake extension not loaded", call. = FALSE)
}

# 2. Verify secret creation
secrets <- dbGetQuery(con, "SELECT * FROM duckdb_secrets() WHERE type='ducklake'")
if (nrow(secrets) == 0) {
  warning("No DuckLake secrets found", call. = FALSE)
}

# 3. Test simple ATTACH first
tryCatch({
  dbExecute(con, "ATTACH 'ducklake:test.ducklake' AS test")
}, error = function(e) {
  cat("ATTACH failed:", conditionMessage(e), "\n")
})
```

## Testing Strategy

### Unit Tests for DuckLake Functions

```r
# Test connection string parsing
expect_equal(ducklake_parse_connection_string("ducklake:secret_name")$backend, "secret")
expect_equal(ducklake_parse_connection_string("ducklake:path/file.ducklake")$backend, "duckdb")

# Test secret creation and listing
ducklake_create_catalog_secret(con, "test", "duckdb", tempfile(), tempdir())
secrets <- ducklake_list_secrets(con)
expect_true("test" %in% secrets$name)

# Test error handling
expect_error(
  ducklake_connect_catalog(con, extra_options = list(SECRET = "bad")),
  pattern = "SECRET option not supported"
)
```

### Integration Tests

```r
# Test end-to-end workflow
test_ducklake_workflow <- function() {
  # 1. Create S3 secret for cloud storage
  ducklake_create_s3_secret(con, key_id = "test", secret = "test")
  
  # 2. Create DuckLake catalog secret
  ducklake_create_catalog_secret(con, "lake", "duckdb", meta_path, data_path)
  
  # 3. Connect using secret
  ducklake_connect_catalog(con, secret_name = "lake", alias = "lake")
  
  # 4. Load VCF data
  ducklake_load_vcf(con, "variants", vcf_file, ext_path)
  
  # 5. Verify time travel works
  result <- dbGetQuery(con, "SELECT COUNT(*) FROM lake.variants AT (VERSION => 1)")
  expect_true(nrow(result) > 0)
}
```

## Performance Considerations

### DuckLake Optimization
- Use `CREATE_IF_NOT_EXISTS=false` for existing catalogs to reduce overhead
- Set appropriate `DATA_INLINING_ROW_LIMIT` for small rows (reduces file count)
- Consider `ENCRYPTED=true` for sensitive data (with performance trade-off)
- Use time travel queries carefully - each version maintains full data copies

### RBCFTools Integration
- Parquet export should use optimal row group sizes (100k-1M rows)
- VEP/CSQ parsing should preserve all transcript data by default
- Consider parallel processing for large VCFs with per-chromosome chunking

## Extension Development

### Building with DuckLake Support

```r
# In RBCFTools build process
bcf_reader_build <- function(build_dir) {
  # DuckDB extension API v1.3+
  # Include DuckLake headers for integration if needed
  # Maintain compatibility with both DuckDB v1.2 and v1.3
}
```

### Version Compatibility
- **DuckDB v1.3+**: Required for current DuckLake features
- **DuckDB v1.2**: Limited DuckLake support, no time travel
- Always check extension version: `SELECT duckdb_version()`

## Common Gotchas

1. **SQLite format**: Use `sqlite:` not `sqlite://` in connection strings
2. **Secret scope**: DuckLake secrets are session-only unless `PERSISTENT` keyword used
3. **File permissions**: DuckLake needs write access to both metadata file and data directory
4. **Extension dependencies**: postgres_scanner, sqlite_scanner must be loaded before DuckLake ATTACH
5. **Cloud credentials**: S3/GCS secrets must be created before using cloud DATA_PATH

## Resources

- **DuckLake Official Docs**: https://duckdb.org/docs/extensions/ducklake
- **DuckDB Extension API**: https://duckdb.org/docs/extensions/overview.html
- **VCF Specification**: https://samtools.github.io/hts-specs/VCFv4.3.pdf
- **DuckDB Time Travel**: https://duckdb.org/docs/sql/time_travel

This document should be updated as DuckLake API evolves and new patterns emerge from RBCFTools development.