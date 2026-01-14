# Open a VCF/BCF file as a DuckDB table or view

Creates a DuckDB connection with the VCF data loaded as a table or view.
Supports in-memory or file-backed databases, tidy format output,
parallel loading by chromosome, column selection, and optional Hive
partitioning.

## Usage

``` r
vcf_open_duckdb(
  file,
  extension_path,
  table_name = "variants",
  as_view = TRUE,
  dbdir = ":memory:",
  columns = NULL,
  region = NULL,
  tidy_format = FALSE,
  threads = 1L,
  partition_by = NULL,
  overwrite = FALSE,
  config = list()
)
```

## Arguments

- file:

  Path to VCF, VCF.GZ, or BCF file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- table_name:

  Name for the table/view (default: "variants")

- as_view:

  Logical, create a VIEW instead of materializing a TABLE (default:
  TRUE). Views are instant to create but queries re-read the VCF each
  time. Tables are slower to create but subsequent queries are fast.

- dbdir:

  Database directory. Default ":memory:" for in-memory database. Use a
  file path for persistent storage (e.g., "variants.duckdb").

- columns:

  Optional character vector of columns to include. NULL for all.

- region:

  Optional genomic region filter (e.g., "chr1:1000-2000"). Requires an
  indexed VCF.

- tidy_format:

  Logical, if TRUE loads data in tidy (long) format with one row per
  variant-sample combination and a SAMPLE_ID column. Default FALSE.

- threads:

  Number of threads for parallel loading (default: 1). When \> 1 and VCF
  is indexed:

  - For views (as_view = TRUE): Creates a UNION ALL view of per-contig
    bcf_read() calls. DuckDB parallelizes execution at query time.

  - For tables (as_view = FALSE): Loads each chromosome in parallel then
    unions into a single table.

- partition_by:

  Optional character vector of columns to partition by when creating a
  table (ignored for views). Creates a partitioned table for efficient
  filtering. Only supported for file-backed databases.

- overwrite:

  Logical, drop existing table/view if it exists (default: FALSE).

- config:

  Named list of DuckDB configuration options.

## Value

A list with:

- con:

  DuckDB connection with extension loaded

- table:

  Name of the created table/view

- is_view:

  Logical indicating if a view was created

- file:

  Path to the source VCF file

- dbdir:

  Database directory

- tidy_format:

  Whether tidy format was used

- row_count:

  Number of rows (NULL for views)

## Examples

``` r
if (FALSE) { # \dontrun{
ext_path <- bcf_reader_build(tempdir())

# Open as lazy view (default - instant creation, re-reads VCF each query)
vcf <- vcf_open_duckdb("variants.vcf.gz", ext_path)
DBI::dbGetQuery(vcf$con, "SELECT * FROM variants WHERE CHROM = '22'")
vcf_close_duckdb(vcf)

# Parallel view (UNION ALL of per-contig reads, parallelized at query time)
vcf <- vcf_open_duckdb("wgs.vcf.gz", ext_path, threads = 8)

# Open as materialized table (slower to create, fast repeated queries)
vcf <- vcf_open_duckdb("variants.vcf.gz", ext_path, as_view = FALSE)
DBI::dbGetQuery(vcf$con, "SELECT COUNT(*) FROM variants")

# Tidy format with specific columns
vcf <- vcf_open_duckdb("cohort.vcf.gz", ext_path,
  tidy_format = TRUE,
  columns = c("CHROM", "POS", "REF", "ALT", "SAMPLE_ID", "FORMAT_GT")
)

# Parallel table loading for large files
vcf <- vcf_open_duckdb("wgs.vcf.gz", ext_path, as_view = FALSE, threads = 8)

# Persistent file-backed database
vcf <- vcf_open_duckdb("variants.vcf.gz", ext_path,
  dbdir = "my_variants.duckdb"
)

# Partitioned table for efficient sample queries
vcf <- vcf_open_duckdb("cohort.vcf.gz", ext_path,
  dbdir = "cohort.duckdb",
  tidy_format = TRUE,
  partition_by = "SAMPLE_ID"
)
} # }
```
