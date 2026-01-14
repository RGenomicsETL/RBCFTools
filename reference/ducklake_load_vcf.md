# Load VCF into DuckLake (ETL + Registration)

Converts VCF/BCF to Parquet using the fast `bcf_reader` extension, then
registers the Parquet file in a DuckLake catalog table.

## Usage

``` r
ducklake_load_vcf(
  con,
  table,
  vcf_path,
  extension_path,
  output_path = NULL,
  threads = parallel::detectCores(),
  compression = "zstd",
  row_group_size = 100000L,
  region = NULL,
  columns = NULL,
  overwrite = FALSE,
  allow_evolution = FALSE,
  tidy_format = FALSE,
  partition_by = NULL
)
```

## Arguments

- con:

  DuckDB connection with DuckLake attached.

- table:

  Target table name (optionally qualified, e.g., "lake.variants").

- vcf_path:

  Path/URI to VCF/BCF file.

- extension_path:

  Path to bcf_reader.duckdb_extension (required).

- output_path:

  Optional Parquet output path. If NULL, uses DuckLake's DATA_PATH.

- threads:

  Number of threads for conversion.

- compression:

  Parquet compression codec.

- row_group_size:

  Parquet row group size.

- region:

  Optional region filter (e.g., "chr1:1000-2000").

- columns:

  Optional character vector of columns to include.

- overwrite:

  Logical, drop existing table first.

- allow_evolution:

  Logical, evolve table schema by adding new columns from VCF. Default:
  FALSE. When TRUE, new columns found in the VCF are added via ALTER
  TABLE before insertion, making all columns queryable. Useful for
  combining VCFs with different annotations (e.g., VEP columns) or
  different samples (FORMAT\_\*\_SampleName).

- tidy_format:

  Logical, if TRUE exports data in tidy (long) format with one row per
  variant-sample combination and a SAMPLE_ID column. Default FALSE.
  Ideal for cohort analysis and combining multiple single-sample VCFs.

- partition_by:

  Optional character vector of columns to partition by (Hive-style).
  Creates directory structure like
  `output_dir/SAMPLE_ID=HG00098/data_0.parquet`. Note: DuckLake
  registration currently requires single Parquet files; when using
  partition_by, the output_path should point to the partition directory
  and files should be registered separately.

## Value

Invisibly returns the path to the created Parquet file.

## Details

This is the recommended function for loading VCF data into DuckLake. It
uses the `bcf_reader` DuckDB extension for fast VCF→Parquet conversion,
which is significantly faster than the nanoarrow streaming path.

**Workflow:**

1.  VCF → Parquet via
    [`vcf_to_parquet_duckdb()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_parquet_duckdb.md)
    (bcf_reader)

2.  Register Parquet in DuckLake catalog

**Schema Evolution (`allow_evolution = TRUE`):** When loading multiple
VCFs with different schemas (e.g., different samples or different
annotation fields), enable `allow_evolution` to automatically add new
columns to the table schema. This uses DuckLake's
`ALTER TABLE ADD COLUMN` which preserves existing data files without
rewriting.

**Tidy Format (`tidy_format = TRUE`):** When building cohort tables from
multiple single-sample VCFs, use `tidy_format = TRUE` to get one row per
variant-sample combination with a `SAMPLE_ID` column. This format is
ideal for downstream analysis and MERGE/UPSERT operations on DuckLake
tables.

**Partitioning (`partition_by`):** When using `partition_by`, the output
is a Hive-partitioned directory structure. This is useful for large
cohorts where you want efficient per-sample queries. DuckDB
auto-generates Bloom filters for VARCHAR columns like SAMPLE_ID. Note:
For DuckLake, partitioned output requires manual file registration.

## Examples

``` r
if (FALSE) { # \dontrun{
# Build extension
ext_path <- bcf_reader_build(tempdir())

# Setup DuckLake
con <- duckdb::dbConnect(duckdb::duckdb())
ducklake_load(con)
ducklake_attach(con, "catalog.ducklake", "/data/parquet/", alias = "lake")
DBI::dbExecute(con, "USE lake")

# Load first VCF
ducklake_load_vcf(con, "variants", "sample1.vcf.gz", ext_path, threads = 8)

# Load second VCF with different annotations, evolving schema
ducklake_load_vcf(con, "variants", "sample2_vep.vcf.gz", ext_path,
  allow_evolution = TRUE
)

# Load VCF in tidy format (one row per variant-sample)
ducklake_load_vcf(con, "variants_tidy", "cohort.vcf.gz", ext_path,
  tidy_format = TRUE
)

# Query - all columns from both VCFs are available
DBI::dbGetQuery(con, "SELECT CHROM, COUNT(*) FROM variants GROUP BY CHROM")
} # }
```
