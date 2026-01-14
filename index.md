# RBCFTools

RBCFTools provides R bindings to
[bcftools](https://github.com/samtools/bcftools) and
[htslib](https://github.com/samtools/htslib), the standard tools for
reading and manipulating VCF/BCF files. The package bundles these
libraries and command-line tools (bcftools, bgzip, tabix), so no
external installation is required. When compiled with libcurl, remote
file access from S3, GCS, and HTTP URLs is supported. The package also
includes support for streaming VCF/BCF to Apache Arrow (IPC) format via
[nanoarrow](https://arrow.apache.org/nanoarrow/), with export to Parquet
format using [duckdb](https://duckdb.org/) via either the [duckdb
nanoarrow
extension](https://duckdb.org/community_extensions/extensions/nanoarrow.html)
or a
[`bcf_reader`](https://rgenomicsetl.github.io/RBCFTools/inst/duckdb_bcf_reader_extension/)
extension bundled in this package.

## Installation

You can install the development version of RBCFTools from r-universe for
unix-alikes (we do not support windows)

``` r
install.packages(
    'RBCFTools',
    repos = c(
              'https://rgenomicsetl.r-universe.dev',
              'https://cloud.r-project.org')
      )
```

## Version Information

``` r
library(RBCFTools)
#> Loading required package: parallel
# Get library versions
bcftools_version()
#> [1] "1.23"
htslib_version()
#> [1] "1.23"
```

## Tool Paths

RBCFTools bundles bcftools and htslib command-line tools. Use the path
functions to locate the executables

``` r
bcftools_path()
#> [1] "/usr/local/lib/R/site-library/RBCFTools/bcftools/bin/bcftools"
bgzip_path()
#> [1] "/usr/local/lib/R/site-library/RBCFTools/htslib/bin/bgzip"
tabix_path()
#> [1] "/usr/local/lib/R/site-library/RBCFTools/htslib/bin/tabix"
# List all available tools
bcftools_tools()
#>  [1] "bcftools"        "color-chrs.pl"   "gff2gff"         "gff2gff.py"     
#>  [5] "guess-ploidy.py" "plot-roh.py"     "plot-vcfstats"   "roh-viz"        
#>  [9] "run-roh.pl"      "vcfutils.pl"     "vrfs-variances"
htslib_tools()
#> [1] "annot-tsv" "bgzip"     "htsfile"   "ref-cache" "tabix"
```

## Capabilities

Check which features were compiled into htslib

``` r
# Get all capabilities as a named list
htslib_capabilities()
#> $configure
#> [1] TRUE
#> 
#> $plugins
#> [1] TRUE
#> 
#> $libcurl
#> [1] TRUE
#> 
#> $s3
#> [1] TRUE
#> 
#> $gcs
#> [1] TRUE
#> 
#> $libdeflate
#> [1] TRUE
#> 
#> $lzma
#> [1] TRUE
#> 
#> $bzip2
#> [1] TRUE
#> 
#> $htscodecs
#> [1] TRUE

# Human-readable feature string
htslib_feature_string()
#> [1] "build=configure libcurl=yes S3=yes GCS=yes libdeflate=yes lzma=yes bzip2=yes plugins=yes plugin-path=/usr/local/lib/R/site-library/RBCFTools/htslib/libexec/htslib: htscodecs=1.6.5"
```

### Feature Constants

Use `HTS_FEATURE_*` constants to check for specific features

``` r
# Check individual features
htslib_has_feature(HTS_FEATURE_LIBCURL)  # Remote file access via libcurl
#> [1] TRUE
htslib_has_feature(HTS_FEATURE_S3)       
#> [1] TRUE
htslib_has_feature(HTS_FEATURE_GCS)      # Google Cloud Storage
#> [1] TRUE
htslib_has_feature(HTS_FEATURE_LIBDEFLATE)
#> [1] TRUE
htslib_has_feature(HTS_FEATURE_LZMA)
#> [1] TRUE
htslib_has_feature(HTS_FEATURE_BZIP2)
#> [1] TRUE
```

These are useful for conditionally enabling features in your code.

## Example Query Of Remote VCF from S3 using bcftools

With libcurl support, bcftools can directly query remote files. Here we
count variants in a small region from the 1000 Genomes cohort VCF on S3:

``` r
# Setup environment for remote file access (S3/GCS)
setup_hts_env()

# Build S3 URL for 1000 Genomes cohort VCF
s3_base <- "s3://1000genomes-dragen-v3.7.6/data/cohorts/"
s3_path <- "gvcf-genotyper-dragen-3.7.6/hg19/3202-samples-cohort/"
s3_vcf_file <- "3202_samples_cohort_gg_chr22.vcf.gz"
s3_vcf_uri <- paste0(s3_base, s3_path, s3_vcf_file)
```

``` r
# Use processx instead of system2
res <- processx::run(
  bcftools_path(),
  c("index", "-n", s3_vcf_uri),
  error_on_status = FALSE,
  echo = FALSE
)
res$stdou
#> [1] "1910766\n"
```

## VCF to Arrow Streams and Duckdb `bcf_reader` extension

RBCFTools provides streaming VCF/BCF to Apache Arrow Stream conversion
via [nanoarrow](https://arrow.apache.org/nanoarrow/). This enables
integration with tools like [duckdb](https://github.com/duckdb/duckdb-r)
and Parquet format convertion when serializing to Arrow IPC. We also
support the
[`bcf_reader`](https://rgenomicsetl.github.io/RBCFTools/inst/duckdb_bcf_reader_extension/)
duckdb extension to read directly into duckb.

The `nanoarrow` stream conversion and `bcf_reader` perform VCF spec
conformance checks on headers (similar to htslib’s
`bcf_hdr_check_sanity()`) and emits R warning or duckdb logs when
correcting non-conformant fields

### Read VCF as Arrow Stream

Open BCF as Arrow array stream and read the batches

``` r

bcf_file <- system.file("extdata", "1000G_3samples.bcf", package = "RBCFTools")
stream <- vcf_open_arrow(bcf_file, batch_size = 100L)

batch <- stream$get_next()
#> Warning in x$get_schema(): FORMAT/AD should be declared as Number=R per VCF
#> spec; correcting schema
#> Warning in x$get_schema(): FORMAT/GQ should be Type=Integer per VCF spec, but
#> header declares Type=Float; using header type
#> Warning in x$get_schema(): FORMAT/GT should be declared as Number=1 per VCF
#> spec; correcting schema
#> Warning in x$get_schema(): FORMAT/AD should be declared as Number=R per VCF
#> spec; correcting schema
#> Warning in x$get_schema(): FORMAT/GQ should be Type=Integer per VCF spec, but
#> header declares Type=Float; using header type
#> Warning in x$get_schema(): FORMAT/GT should be declared as Number=1 per VCF
#> spec; correcting schema

head(nanoarrow::convert_array(batch))
#>   CHROM   POS         ID REF ALT QUAL FILTER INFO.DP INFO.AF       INFO.CB
#> 1     1 10583 rs58108140   G   A   NA   PASS    1557   0.162 UM,BI,BC,NCBI
#> 2     1 11508       <NA>   A   G   NA   PASS      23    0.72         BI,BC
#> 3     1 11565       <NA>   G   T   NA   PASS      45       0         BI,BC
#> 4     1 13116       <NA>   T   G   NA   PASS    2400   0.016         UM,BI
#> 5     1 13327       <NA>   G   C   NA   PASS    2798    0.01         BI,BC
#> 6     1 14699       <NA>   C   G   NA   PASS     408    0.02         BI,BC
#>   INFO.EUR_R2 INFO.AFR_R2 INFO.ASN_R2 INFO.AC INFO.AN samples.HG00098.AD
#> 1       0.248          NA          NA       0       6               NULL
#> 2       0.001          NA          NA       6       6               NULL
#> 3          NA       0.003          NA       0       6               NULL
#> 4       0.106       0.286          NA       0       6               NULL
#> 5       0.396       0.481          NA       0       6               NULL
#> 6       0.061       0.184          NA       0       6               NULL
#>   samples.HG00098.DP samples.HG00098.GL samples.HG00098.GQ samples.HG00098.GT
#> 1                 NA               NULL               3.28                0|0
#> 2                 NA               NULL               2.22                1|1
#> 3                 NA               NULL               1.48                0|0
#> 4                 NA               NULL               9.17                0|0
#> 5                 NA               NULL              15.80                0|0
#> 6                 NA               NULL               6.29                0|0
#>   samples.HG00098.GD samples.HG00098.OG samples.HG00100.AD samples.HG00100.DP
#> 1                 NA                ./.               NULL                 NA
#> 2                 NA                ./.               NULL                 NA
#> 3                 NA                ./.               NULL                 NA
#> 4                 NA                ./.               NULL                 NA
#> 5                 NA                ./.               NULL                 NA
#> 6                 NA                ./.               NULL                 NA
#>   samples.HG00100.GL samples.HG00100.GQ samples.HG00100.GT samples.HG00100.GD
#> 1               NULL               3.28                0|0                 NA
#> 2               NULL               2.22                1|1                 NA
#> 3               NULL               1.48                0|0                 NA
#> 4               NULL               9.17                0|0                 NA
#> 5               NULL              15.80                0|0                 NA
#> 6               NULL               6.29                0|0                 NA
#>   samples.HG00100.OG samples.HG00106.AD samples.HG00106.DP samples.HG00106.GL
#> 1                ./.               NULL                 NA               NULL
#> 2                ./.               NULL                 NA               NULL
#> 3                ./.               NULL                 NA               NULL
#> 4                ./.               NULL                 NA               NULL
#> 5                ./.               2, 0                  2 0.00, -0.60, -8.78
#> 6                ./.               NULL                 NA               NULL
#>   samples.HG00106.GQ samples.HG00106.GT samples.HG00106.GD samples.HG00106.OG
#> 1               3.28                0|0                 NA                ./.
#> 2               2.22                1|1                 NA                ./.
#> 3               1.48                0|0                 NA                ./.
#> 4               9.17                0|0                 NA                ./.
#> 5              21.74                0|0                 NA                ./.
#> 6               6.29                0|0                 NA                ./.
stream$release()
```

### Convert to Data Frame

Convert entire BCF to data.frame

``` r
options(warn = -1)  # Suppress warnings
df <- vcf_to_arrow(bcf_file, as = "data.frame")
df[, c("CHROM", "POS", "REF", "ALT", "QUAL")] |> head()
#>   CHROM   POS REF ALT QUAL
#> 1     1 10583   G   A   NA
#> 2     1 11508   A   G   NA
#> 3     1 11565   G   T   NA
#> 4     1 13116   T   G   NA
#> 5     1 13327   G   C   NA
#> 6     1 14699   C   G   NA
```

### Write to Arrow IPC

Arrow IPC (`.arrows`) format for interoperability with other Arrow tools
using nanoarrow’s native streaming writer

``` r

# Convert BCF to Arrow IPC
ipc_file <- tempfile(fileext = ".arrows")

vcf_to_arrow_ipc(bcf_file, ipc_file)

# Read back with nanoarrow
ipc_data <- as.data.frame(nanoarrow::read_nanoarrow(ipc_file))
ipc_data[, c("CHROM", "POS", "REF", "ALT")] |> head()
#>   CHROM   POS REF ALT
#> 1     1 10583   G   A
#> 2     1 11508   A   G
#> 3     1 11565   G   T
#> 4     1 13116   T   G
#> 5     1 13327   G   C
#> 6     1 14699   C   G
```

### Write VCF Streams to Parquet

Using [duckdb](https://github.com/duckdb/duckdb-r) to convert BCF to
parquet file and perform queries on the parquet file. This involve vcf
stream conversion to data.frame

``` r

parquet_file <- tempfile(fileext = ".parquet")
vcf_to_parquet_arrow(bcf_file, parquet_file, compression = "snappy")
#> Wrote 11 rows to /tmp/Rtmp49gzcy/file3b4d70b34ff.parquet
con <- duckdb::dbConnect(duckdb::duckdb())
pq_bcf <- DBI::dbGetQuery(con, sprintf("SELECT * FROM '%s' LIMIT 100", parquet_file))
pq_me <- DBI::dbGetQuery(
    con, 
    sprintf("SELECT * FROM parquet_metadata('%s')",
    parquet_file))
duckdb::dbDisconnect(con, shutdown = TRUE)
pq_bcf[, c("CHROM", "POS", "REF", "ALT")] |>
  head()
#>   CHROM   POS REF ALT
#> 1     1 10583   G   A
#> 2     1 11508   A   G
#> 3     1 11565   G   T
#> 4     1 13116   T   G
#> 5     1 13327   G   C
#> 6     1 14699   C   G
pq_me |> head()
#>                                 file_name row_group_id row_group_num_rows
#> 1 /tmp/Rtmp49gzcy/file3b4d70b34ff.parquet            0                 11
#> 2 /tmp/Rtmp49gzcy/file3b4d70b34ff.parquet            0                 11
#> 3 /tmp/Rtmp49gzcy/file3b4d70b34ff.parquet            0                 11
#> 4 /tmp/Rtmp49gzcy/file3b4d70b34ff.parquet            0                 11
#> 5 /tmp/Rtmp49gzcy/file3b4d70b34ff.parquet            0                 11
#> 6 /tmp/Rtmp49gzcy/file3b4d70b34ff.parquet            0                 11
#>   row_group_num_columns row_group_bytes column_id file_offset num_values
#> 1                    36            3135         0           0         11
#> 2                    36            3135         1           0         11
#> 3                    36            3135         2           0         11
#> 4                    36            3135         3           0         11
#> 5                    36            3135         4           0         11
#> 6                    36            3135         5           0         11
#>       path_in_schema       type  stats_min  stats_max stats_null_count
#> 1              CHROM BYTE_ARRAY          1          1                0
#> 2                POS     DOUBLE    10583.0    28376.0                0
#> 3                 ID BYTE_ARRAY rs58108140 rs58108140               10
#> 4                REF BYTE_ARRAY          A          T                0
#> 5 ALT, list, element BYTE_ARRAY          A          T               NA
#> 6               QUAL     DOUBLE       <NA>       <NA>               11
#>   stats_distinct_count stats_min_value stats_max_value compression
#> 1                    1               1               1      SNAPPY
#> 2                   NA         10583.0         28376.0      SNAPPY
#> 3                    1      rs58108140      rs58108140      SNAPPY
#> 4                   NA               A               T      SNAPPY
#> 5                   NA               A               T      SNAPPY
#> 6                   NA            <NA>            <NA>      SNAPPY
#>          encodings index_page_offset dictionary_page_offset data_page_offset
#> 1 PLAIN_DICTIONARY                NA                      4               24
#> 2            PLAIN                NA                     NA               52
#> 3 PLAIN_DICTIONARY                NA                    146              175
#> 4            PLAIN                NA                     NA              208
#> 5            PLAIN                NA                     NA              268
#> 6            PLAIN                NA                     NA              335
#>   total_compressed_size total_uncompressed_size key_value_metadata
#> 1                    48                      44               NULL
#> 2                    94                     113               NULL
#> 3                    62                      84               NULL
#> 4                    60                      78               NULL
#> 5                    67                      85               NULL
#> 6                    25                      23               NULL
#>   bloom_filter_offset bloom_filter_length min_is_exact max_is_exact
#> 1                2261                  47         TRUE         TRUE
#> 2                  NA                  NA         TRUE         TRUE
#> 3                2308                  47         TRUE         TRUE
#> 4                  NA                  NA         TRUE         TRUE
#> 5                  NA                  NA         TRUE         TRUE
#> 6                  NA                  NA           NA           NA
#>   row_group_compressed_bytes geo_bbox.xmin geo_bbox.xmax geo_bbox.ymin
#> 1                          1            NA            NA            NA
#> 2                          1            NA            NA            NA
#> 3                          1            NA            NA            NA
#> 4                          1            NA            NA            NA
#> 5                          1            NA            NA            NA
#> 6                          1            NA            NA            NA
#>   geo_bbox.ymax geo_bbox.zmin geo_bbox.zmax geo_bbox.mmin geo_bbox.mmax
#> 1            NA            NA            NA            NA            NA
#> 2            NA            NA            NA            NA            NA
#> 3            NA            NA            NA            NA            NA
#> 4            NA            NA            NA            NA            NA
#> 5            NA            NA            NA            NA            NA
#> 6            NA            NA            NA            NA            NA
#>   geo_types
#> 1      NULL
#> 2      NULL
#> 3      NULL
#> 4      NULL
#> 5      NULL
#> 6      NULL
```

Use `streaming = TRUE` to avoid loading the entire VCF into R memory.
This streams VCF to Arrow IPC (nanoarrow) and then to Parquet via
duckdb, trading memory with serialization overhead using the [duckdb
nanoarrow
extension](https://duckdb.org/community_extensions/extensions/nanoarrow.html)

``` r
bcf_larger <- system.file("extdata", "1000G.ALL.2of4intersection.20100804.genotypes.bcf", package = "RBCFTools")
outfile <-  tempfile(fileext = ".parquet")
vcf_to_parquet_arrow(
    bcf_larger,
    outfile,
    streaming = TRUE,
    batch_size = 10000L,
    row_group_size = 100000L,
    compression = "zstd"
)
#> Wrote 11 rows to /tmp/Rtmp49gzcy/file3b4d3ce3d2d3.parquet (streaming mode)
```

### Query VCF with duckdb after converting the Stream

SQL queries on BCF using duckdb package. For now this is somehow limited
due to convertion from arrow streams to data frame

``` r
vcf_query_arrow(bcf_file, "SELECT CHROM, COUNT(*) as n FROM vcf GROUP BY CHROM")
#>   CHROM  n
#> 1     1 11

# Filter variants by position
vcf_query_arrow(bcf_file, "SELECT CHROM, POS, REF, ALT FROM vcf  LIMIT 5")
#>   CHROM   POS REF ALT
#> 1     1 10583   G   A
#> 2     1 11508   A   G
#> 3     1 11565   G   T
#> 4     1 13116   T   G
#> 5     1 13327   G   C
```

### Query VCF with DuckDB Extension

A native DuckDB extension (`bcf_reader`) for direct SQL queries on
VCF/BCF files without Arrow conversion overhead. The extension uses the
Duckb C API and should be compatible with duckb v1.2.0+

``` r
# Build extension (uses package's bundled htslib)
build_dir <- file.path(tempdir(), "bcf_reader")
ext_path <- bcf_reader_build(build_dir, verbose = FALSE)

# Connect and query a VCF.gz file
con <- vcf_duckdb_connect(ext_path)
vcf_file <- system.file("extdata", "test_deep_variant.vcf.gz", package = "RBCFTools")

# Describe schema
DBI::dbGetQuery(con, sprintf("DESCRIBE SELECT * FROM bcf_read('%s')", vcf_file))
#>                        column_name column_type null  key default extra
#> 1                            CHROM     VARCHAR  YES <NA>    <NA>  <NA>
#> 2                              POS      BIGINT  YES <NA>    <NA>  <NA>
#> 3                               ID     VARCHAR  YES <NA>    <NA>  <NA>
#> 4                              REF     VARCHAR  YES <NA>    <NA>  <NA>
#> 5                              ALT   VARCHAR[]  YES <NA>    <NA>  <NA>
#> 6                             QUAL      DOUBLE  YES <NA>    <NA>  <NA>
#> 7                           FILTER   VARCHAR[]  YES <NA>    <NA>  <NA>
#> 8                         INFO_END     INTEGER  YES <NA>    <NA>  <NA>
#> 9      FORMAT_GT_test_deep_variant     VARCHAR  YES <NA>    <NA>  <NA>
#> 10     FORMAT_GQ_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 11     FORMAT_DP_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 12 FORMAT_MIN_DP_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 13     FORMAT_AD_test_deep_variant   INTEGER[]  YES <NA>    <NA>  <NA>
#> 14    FORMAT_VAF_test_deep_variant     FLOAT[]  YES <NA>    <NA>  <NA>
#> 15     FORMAT_PL_test_deep_variant   INTEGER[]  YES <NA>    <NA>  <NA>
#> 16 FORMAT_MED_DP_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>

# Aggregate query
DBI::dbGetQuery(con, sprintf("
  SELECT CHROM, COUNT(*) as n_variants, 
         MIN(POS) as min_pos, MAX(POS) as max_pos
  FROM bcf_read('%s') 
  GROUP BY CHROM 
  ORDER BY n_variants DESC 
  LIMIT 5", vcf_file))
#>   CHROM n_variants min_pos   max_pos
#> 1    19      35918  111129  59084689
#> 2     1      35846  536895 249211717
#> 3    17      27325    6102  81052229
#> 4    11      24472  180184 134257519
#> 5     2      22032   42993 242836470

# Export directly to Parquet
parquet_out <- tempfile(fileext = ".parquet")
DBI::dbExecute(con, sprintf("
  COPY (SELECT * FROM bcf_read('%s')) 
  TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", vcf_file, parquet_out))
#> [1] 368319

# Verify parquet file size
file.info(parquet_out)$size
#> [1] 3998815

# Same query on Parquet file
DBI::dbGetQuery(con, sprintf("
  SELECT CHROM, COUNT(*) as n_variants, 
         MIN(POS) as min_pos, MAX(POS) as max_pos
  FROM '%s' 
  GROUP BY CHROM 
  ORDER BY n_variants DESC 
  LIMIT 5", parquet_out))
#>   CHROM n_variants min_pos   max_pos
#> 1    19      35918  111129  59084689
#> 2     1      35846  536895 249211717
#> 3    17      27325    6102  81052229
#> 4    11      24472  180184 134257519
#> 5     2      22032   42993 242836470

DBI::dbDisconnect(con)
```

### Tidy (Long) Format Export

Export VCF/BCF to a “tidy” format where each row is one variant-sample
combination. The native `tidy_format` parameter in the bcf_reader
extension transforms wide `FORMAT_<field>_<sample>` columns into a
single `SAMPLE_ID` column plus `FORMAT_<field>` columns - much faster
than SQL-level UNNEST.

``` r
# Build extension
ext_path <- bcf_reader_build(tempdir(), verbose = FALSE)

# Multi-sample VCF: 3 samples x 11 variants = 33 rows
vcf_3samples <- system.file("extdata", "1000G_3samples.vcf.gz", package = "RBCFTools")
tidy_out <- tempfile(fileext = ".parquet")

# Use tidy_format parameter directly
vcf_to_parquet_duckdb(vcf_3samples, tidy_out, extension_path = ext_path, tidy_format = TRUE)
#> Wrote: /tmp/Rtmp49gzcy/file3b4d63dffa2c.parquet

# Query the tidy output
con <- duckdb::dbConnect(duckdb::duckdb())
DBI::dbGetQuery(con, sprintf("
  SELECT CHROM, POS, REF, SAMPLE_ID, FORMAT_GT 
  FROM '%s' 
  LIMIT 9", tidy_out))
#>   CHROM   POS REF SAMPLE_ID FORMAT_GT
#> 1     1 10583   G   HG00098       0|0
#> 2     1 10583   G   HG00100       0|0
#> 3     1 10583   G   HG00106       0|0
#> 4     1 11508   A   HG00098       1|1
#> 5     1 11508   A   HG00100       1|1
#> 6     1 11508   A   HG00106       1|1
#> 7     1 11565   G   HG00098       0|0
#> 8     1 11565   G   HG00100       0|0
#> 9     1 11565   G   HG00106       0|0

# Verify row expansion: variants * samples
DBI::dbGetQuery(con, sprintf("
  SELECT COUNT(*) as total_rows, 
         COUNT(DISTINCT SAMPLE_ID) as n_samples
  FROM '%s'", tidy_out))
#>   total_rows n_samples
#> 1         33         3

DBI::dbDisconnect(con, shutdown = TRUE)
```

This format is ideal for combining single-sample VCFs into cohort tables
or appending to DuckLake tables with MERGE operations.

### Stream Remote VCF using Arrow or DuckDB Extension

Stream remote VCF region directly from S3 using either `nanoarrow` based
`vcf_stream` or `duckb` extension

``` r
s3_vcf_uri <- paste0(s3_base, s3_path, s3_vcf_file)

# Arrow stream
stream <- vcf_open_arrow(
    s3_vcf_uri,
    region = "chr22:16050000-16050500",
    batch_size = 1000L
)
df <- as.data.frame(nanoarrow::convert_array_stream(stream))
df[, c("CHROM", "POS", "REF", "ALT")] |> head()
#>   CHROM      POS REF                  ALT
#> 1 chr22 16050036   A C        , <NON_REF>
#> 2 chr22 16050151   T G        , <NON_REF>
#> 3 chr22 16050213   C T        , <NON_REF>
#> 4 chr22 16050219   C A        , <NON_REF>
#> 5 chr22 16050224   A C        , <NON_REF>
#> 6 chr22 16050229   C A        , <NON_REF>


# Query remote VCF with bcf_reader extension

vcf_query_duckdb(
    s3_vcf_uri,
    ext_path,
    region = "chr22:16050000-16050500",
    query = "SELECT CHROM, POS, REF, ALT FROM vcf LIMIT 5"
)
#>   CHROM      POS REF          ALT
#> 1 chr22 16050036   A C, <NON_REF>
#> 2 chr22 16050151   T G, <NON_REF>
#> 3 chr22 16050213   C T, <NON_REF>
#> 4 chr22 16050219   C A, <NON_REF>
#> 5 chr22 16050224   A C, <NON_REF>
```

### Custom Index File Path

For region queries, an index file is required. By default, RBCFTools
looks for `.tbi` (tabix) or `.csi` indexes using standard naming
conventions. For non-standard index locations such as presigned URLs or
custom paths, use the `index` parameter. Index files are only required
for region queries; when reading an entire file without a region filter,
no index is needed. VCF files try `.tbi` first then fall back to `.csi`,
while BCF files use `.csi` only.

``` r
# Explicit index file path
bcf_file <- system.file("extdata", "1000G_3samples.bcf", package = "RBCFTools")
csi_index <- system.file("extdata", "1000G_3samples.bcf.csi", package = "RBCFTools")

stream <- vcf_open_arrow(bcf_file, index = csi_index)
batch <- stream$get_next()
nanoarrow::convert_array(batch)[, c("CHROM", "POS", "REF")] |> head(3)
#>   CHROM   POS REF
#> 1     1 10583   G
#> 2     1 11508   A
#> 3     1 11565   G
# Alternative: htslib ##idx## syntax in filename
filename_with_idx <- paste0(bcf_file, "##idx##", csi_index)
stream2 <- vcf_open_arrow(filename_with_idx)
batch2 <- stream2$get_next()
nanoarrow::convert_array(batch2)[, c("CHROM", "POS", "REF")] |> head(3)
#>   CHROM   POS REF
#> 1     1 10583   G
#> 2     1 11508   A
#> 3     1 11565   G
```

## Example Application: DuckLake ETL

[`DuckLake`](https://ducklake.select/) is an integrated data lake and
catalog format. It has two components, a parquet files storage and a
metadata dababase layer.

### DuckLake ETL to MinIO Storage backend

To mimick a S3 backend for [`DuckLake`](https://ducklake.select/)
storage we use
[minio](https://rgenomicsetl.github.io/RBCFTools/github.com/minio/minio),
we convert VCF files to parquet and insert then into DuckLake and query
the lake. The lake as a local duckdb metadata database in this example

#### Setup up `minio` storage backend

We start by seting up and configuring a `minio` server

``` r
# DuckLake with S3-compatible storage using local MinIO
if (!requireNamespace("processx", quietly = TRUE)) stop("processx required")
bin_dir <- file.path(tempdir(), "ducklake_bins")
dir.create(bin_dir, recursive = TRUE, showWarnings = FALSE)

# Use installed MinIO and MC binaries
minio_bin <- Sys.which('minio')
mc_bin <- Sys.which('mc')

# Start MinIO (ephemeral) and configure mc
data_dir <- file.path(tempdir(), "ducklake_minio")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
port <- 9000
endpoint <- sprintf("127.0.0.1:%d", port)

# Start MinIO server in background
cmd <- sprintf(
  "%s server %s --address %s > /dev/null 2>&1 & echo $!",
  shQuote(minio_bin),
  shQuote(data_dir),
  endpoint
)
pid_output <- processx::run("sh", c("-c", cmd), echo = FALSE)$stdout
pid <- as.integer(pid_output)
pid
#> [1] 15512
# Give MinIO time to start
Sys.sleep(10)

# Configure mc alias
# remove previous alias
processx::run(
  mc_bin,
  c("alias", "remove", "ducklake_local"),
  error_on_status = FALSE,
  echo = FALSE
)
#> $status
#> [1] 0
#> 
#> $stdout
#> [1] "Removed `ducklake_local` successfully.\n"
#> 
#> $stderr
#> [1] ""
#> 
#> $timeout
#> [1] FALSE
mc_cmd_args <- c("alias", "set", "ducklake_local", 
                  paste0("http://", endpoint), "minioadmin", "minioadmin")
processx::run(mc_bin, mc_cmd_args, echo = FALSE)
#> $status
#> [1] 0
#> 
#> $stdout
#> [1] "Added `ducklake_local` successfully.\n"
#> 
#> $stderr
#> [1] ""
#> 
#> $timeout
#> [1] FALSE

# Create bucket with unique name
bucket <- sprintf("readme-demo-%d", as.integer(Sys.time()))
bucket_cmd_args <- c("mb", paste0("ducklake_local/", bucket))
processx::run(mc_bin, bucket_cmd_args, echo = FALSE)
#> $status
#> [1] 0
#> 
#> $stdout
#> [1] "Bucket created successfully `ducklake_local/readme-demo-1768427938`.\n"
#> 
#> $stderr
#> [1] ""
#> 
#> $timeout
#> [1] FALSE

# Store variables for later use
minio_endpoint <- endpoint
bucket_name <- bucket
data_root_s3 <- paste0("s3://", bucket_name)
data_path_s3 <- paste0(data_root_s3, "/data/")
mc_path <- mc_bin
```

#### Attach a DuckLake

``` r
con <- duckdb::dbConnect(duckdb::duckdb(config = list(
  allow_unsigned_extensions = "true",
  enable_external_access = "true"
)))
stopifnot(DBI::dbIsValid(con))

DBI::dbExecute(con, "INSTALL httpfs")
#> [1] 0
DBI::dbExecute(con, "LOAD httpfs")
#> [1] 0
DBI::dbExecute(con, "INSTALL ducklake FROM core_nightly")
#> [1] 0
DBI::dbExecute(con, "LOAD ducklake")
#> [1] 0

# Provide S3 credentials/endpoints for MinIO
Sys.setenv(
  AWS_ACCESS_KEY_ID = "minioadmin",
  AWS_SECRET_ACCESS_KEY = "minioadmin",
  AWS_DEFAULT_REGION = "us-east-1",
  AWS_S3_ENDPOINT = paste0("http://", minio_endpoint),
  AWS_S3_USE_HTTPS = "FALSE",
  AWS_S3_FORCE_PATH_STYLE = "TRUE",
  AWS_EC2_METADATA_DISABLED = "TRUE"
)

ducklake_create_s3_secret(
  con,
  name = "ducklake_minio",
  key_id = "minioadmin",
  secret = "minioadmin",
  endpoint = minio_endpoint,
  region = "us-east-1",
  use_ssl = FALSE
)

metadata_path <- file.path(tempdir(), sprintf("ducklake_meta_%s.ducklake", bucket_name))
ducklake_attach(
  con,
  metadata_path = metadata_path,
  data_path = data_path_s3,
  alias = "lake",
  extra_options = list(OVERRIDE_DATA_PATH = TRUE)
)

# Work inside the attached lake database
DBI::dbExecute(con, "USE lake")
#> [1] 0
```

### Write a VCF into minio and register to the Lake

``` r
# Ensure we are operating inside the DuckLake catalog
DBI::dbExecute(con, "USE lake")
#> [1] 0

# Load variants via fast VCF to Parquet conversion
vcf_file <- system.file("extdata", "test_deep_variant.vcf.gz", package = "RBCFTools")
ext_path <- bcf_reader_build(tempdir())
#> bcf_reader extension already exists at: /tmp/Rtmp49gzcy/build/bcf_reader.duckdb_extension
#> Use force=TRUE to rebuild.
ducklake_load_vcf(
  con,
  table = "variants",
  vcf_path = vcf_file,
  extension_path = ext_path,
  threads = 1
)
#> Wrote: /tmp/Rtmp49gzcy/variants_20260114_225859.parquet
#> Note: method with signature 'DBIConnection#Id' chosen for function 'dbExistsTable',
#>  target signature 'duckdb_connection#Id'.
#>  "duckdb_connection#ANY" would also be valid
```

### Add another VCF file with different schema

DuckLake supports schema evolution via `ALTER TABLE`. Use
`allow_evolution = TRUE` to automatically add new columns from incoming
files.

``` r
DBI::dbExecute(con, "USE lake")
#> [1] 0
variants_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM variants")$n[1]
variants_count
#> [1] 368319

vcf_file2 <- system.file("extdata", "test_vep.vcf", package = "RBCFTools")
local_parquet2 <- tempfile(fileext = ".parquet")
vcf_to_parquet_duckdb(vcf_file2, local_parquet2, extension_path = ext_path)
#> Wrote: /tmp/Rtmp49gzcy/file3b4d200692b9.parquet

DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) as n FROM read_parquet('%s')", local_parquet2))
#>     n
#> 1 802

s3_parquet2 <- paste0(data_path_s3, "variants/variants_vep.parquet")
mc_cmd_args <- c("cp", local_parquet2, paste0("ducklake_local/", bucket_name, "/data/variants/variants_vep.parquet"))
processx::run(mc_bin, mc_cmd_args, echo = FALSE)
#> $status
#> [1] 0
#> 
#> $stdout
#> [1] "`/tmp/Rtmp49gzcy/file3b4d200692b9.parquet` -> `ducklake_local/readme-demo-1768427938/data/variants/variants_vep.parquet`\n┌────────────┬─────────────┬──────────┬─────────────┐\n│ Total      │ Transferred │ Duration │ Speed       │\n│ 120.96 KiB │ 120.96 KiB  │ 00m00s   │ 13.25 MiB/s │\n└────────────┴─────────────┴──────────┴─────────────┘\n"
#> 
#> $stderr
#> [1] ""
#> 
#> $timeout
#> [1] FALSE

DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) as n FROM read_parquet('%s')", s3_parquet2))
#>     n
#> 1 802

ducklake_register_parquet(
  con,
  table = "lake.variants",
  parquet_files = s3_parquet2,
  create_table = FALSE,
  allow_evolution = TRUE
)

variants_count_after <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM variants")$n[1]
variants_count_after
#> [1] 369121
```

### List lake content

``` r
DBI::dbExecute(con, "USE lake")
#> [1] 0

DBI::dbGetQuery(con, "
  SELECT 
    COUNT(*) as total_variants,
    COUNT(DISTINCT CHROM) as n_chromosomes,
    MIN(POS) as min_position,
    MAX(POS) as max_position
  FROM variants
")
#>   total_variants n_chromosomes min_position max_position
#> 1         369121            25          152    249211717

DBI::dbGetQuery(con, "DESCRIBE variants") |>
  head(20)
#>                        column_name column_type null  key default extra
#> 1                            CHROM     VARCHAR  YES <NA>    <NA>  <NA>
#> 2                              POS      BIGINT  YES <NA>    <NA>  <NA>
#> 3                               ID     VARCHAR  YES <NA>    <NA>  <NA>
#> 4                              REF     VARCHAR  YES <NA>    <NA>  <NA>
#> 5                              ALT   VARCHAR[]  YES <NA>    <NA>  <NA>
#> 6                             QUAL      DOUBLE  YES <NA>    <NA>  <NA>
#> 7                           FILTER   VARCHAR[]  YES <NA>    <NA>  <NA>
#> 8                         INFO_END     INTEGER  YES <NA>    <NA>  <NA>
#> 9      FORMAT_GT_test_deep_variant     VARCHAR  YES <NA>    <NA>  <NA>
#> 10     FORMAT_GQ_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 11     FORMAT_DP_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 12 FORMAT_MIN_DP_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 13     FORMAT_AD_test_deep_variant   INTEGER[]  YES <NA>    <NA>  <NA>
#> 14    FORMAT_VAF_test_deep_variant     FLOAT[]  YES <NA>    <NA>  <NA>
#> 15     FORMAT_PL_test_deep_variant   INTEGER[]  YES <NA>    <NA>  <NA>
#> 16 FORMAT_MED_DP_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 17                      VEP_Allele   VARCHAR[]  YES <NA>    <NA>  <NA>
#> 18                 VEP_Consequence   VARCHAR[]  YES <NA>    <NA>  <NA>
#> 19                      VEP_IMPACT   VARCHAR[]  YES <NA>    <NA>  <NA>
#> 20                      VEP_SYMBOL   VARCHAR[]  YES <NA>    <NA>  <NA>
```

``` r
ducklake_list_files(con, "lake", "variants")
#>                                                                                              data_file
#> 1 s3://readme-demo-1768427938/data/main/variants/ducklake-019bbe84-e761-7f0b-bbe1-ca70187d46f0.parquet
#> 2                                       s3://readme-demo-1768427938/data/variants/variants_vep.parquet
#>   data_file_size_bytes data_file_footer_size data_file_encryption_key
#> 1              5751658                  6275                     NULL
#> 2               123858                 14951                     NULL
#>   delete_file delete_file_size_bytes delete_file_footer_size
#> 1        <NA>                     NA                      NA
#> 2        <NA>                     NA                      NA
#>   delete_file_encryption_key
#> 1                       NULL
#> 2                       NULL
```

### Snapshots and time travel

``` r
ducklake_snapshots(con, "lake")
#>    snapshot_id       snapshot_time schema_version
#> 1            0 2026-01-14 21:58:58              0
#> 2            1 2026-01-14 21:58:59              1
#> 3            2 2026-01-14 21:58:59              2
#> 4            3 2026-01-14 21:58:59              3
#> 5            4 2026-01-14 21:58:59              4
#> 6            5 2026-01-14 21:58:59              5
#> 7            6 2026-01-14 21:58:59              6
#> 8            7 2026-01-14 21:59:00              7
#> 9            8 2026-01-14 21:59:00              8
#> 10           9 2026-01-14 21:59:00              9
#> 11          10 2026-01-14 21:59:00             10
#> 12          11 2026-01-14 21:59:00             11
#> 13          12 2026-01-14 21:59:00             12
#> 14          13 2026-01-14 21:59:00             13
#> 15          14 2026-01-14 21:59:00             14
#> 16          15 2026-01-14 21:59:00             15
#> 17          16 2026-01-14 21:59:00             16
#> 18          17 2026-01-14 21:59:00             17
#> 19          18 2026-01-14 21:59:00             18
#> 20          19 2026-01-14 21:59:00             19
#> 21          20 2026-01-14 21:59:00             20
#> 22          21 2026-01-14 21:59:00             21
#> 23          22 2026-01-14 21:59:00             22
#> 24          23 2026-01-14 21:59:00             23
#> 25          24 2026-01-14 21:59:00             24
#> 26          25 2026-01-14 21:59:00             25
#> 27          26 2026-01-14 21:59:00             26
#> 28          27 2026-01-14 21:59:00             27
#> 29          28 2026-01-14 21:59:00             28
#> 30          29 2026-01-14 21:59:00             29
#> 31          30 2026-01-14 21:59:00             30
#> 32          31 2026-01-14 21:59:00             31
#> 33          32 2026-01-14 21:59:00             32
#> 34          33 2026-01-14 21:59:00             33
#> 35          34 2026-01-14 21:59:00             34
#> 36          35 2026-01-14 21:59:00             35
#> 37          36 2026-01-14 21:59:00             36
#> 38          37 2026-01-14 21:59:00             37
#> 39          38 2026-01-14 21:59:00             38
#> 40          39 2026-01-14 21:59:00             39
#> 41          40 2026-01-14 21:59:00             40
#> 42          41 2026-01-14 21:59:00             41
#> 43          42 2026-01-14 21:59:00             42
#> 44          43 2026-01-14 21:59:00             43
#> 45          44 2026-01-14 21:59:00             44
#> 46          45 2026-01-14 21:59:00             45
#> 47          46 2026-01-14 21:59:00             46
#> 48          47 2026-01-14 21:59:00             47
#> 49          48 2026-01-14 21:59:00             48
#> 50          49 2026-01-14 21:59:00             49
#> 51          50 2026-01-14 21:59:00             50
#> 52          51 2026-01-14 21:59:00             51
#> 53          52 2026-01-14 21:59:00             52
#> 54          53 2026-01-14 21:59:00             53
#> 55          54 2026-01-14 21:59:00             54
#> 56          55 2026-01-14 21:59:00             55
#> 57          56 2026-01-14 21:59:00             56
#> 58          57 2026-01-14 21:59:00             57
#> 59          58 2026-01-14 21:59:00             58
#> 60          59 2026-01-14 21:59:00             59
#> 61          60 2026-01-14 21:59:00             60
#> 62          61 2026-01-14 21:59:00             61
#> 63          62 2026-01-14 21:59:00             62
#> 64          63 2026-01-14 21:59:00             63
#> 65          64 2026-01-14 21:59:00             64
#> 66          65 2026-01-14 21:59:00             65
#> 67          66 2026-01-14 21:59:00             66
#> 68          67 2026-01-14 21:59:00             67
#> 69          68 2026-01-14 21:59:00             68
#> 70          69 2026-01-14 21:59:00             69
#> 71          70 2026-01-14 21:59:00             70
#> 72          71 2026-01-14 21:59:00             71
#> 73          72 2026-01-14 21:59:00             72
#> 74          73 2026-01-14 21:59:00             73
#> 75          74 2026-01-14 21:59:00             74
#> 76          75 2026-01-14 21:59:00             75
#> 77          76 2026-01-14 21:59:00             76
#> 78          77 2026-01-14 21:59:00             77
#> 79          78 2026-01-14 21:59:00             78
#> 80          79 2026-01-14 21:59:00             79
#> 81          80 2026-01-14 21:59:00             80
#> 82          81 2026-01-14 21:59:00             81
#> 83          82 2026-01-14 21:59:00             82
#> 84          83 2026-01-14 21:59:00             83
#> 85          84 2026-01-14 21:59:00             84
#> 86          85 2026-01-14 21:59:00             85
#> 87          86 2026-01-14 21:59:00             86
#> 88          87 2026-01-14 21:59:01             87
#> 89          88 2026-01-14 21:59:01             87
#>                                                   changes author commit_message
#> 1                                   schemas_created, main   <NA>           <NA>
#> 2  tables_created, tables_inserted_into, main.variants, 1   <NA>           <NA>
#> 3                                       tables_altered, 1   <NA>           <NA>
#> 4                                       tables_altered, 1   <NA>           <NA>
#> 5                                       tables_altered, 1   <NA>           <NA>
#> 6                                       tables_altered, 1   <NA>           <NA>
#> 7                                       tables_altered, 1   <NA>           <NA>
#> 8                                       tables_altered, 1   <NA>           <NA>
#> 9                                       tables_altered, 1   <NA>           <NA>
#> 10                                      tables_altered, 1   <NA>           <NA>
#> 11                                      tables_altered, 1   <NA>           <NA>
#> 12                                      tables_altered, 1   <NA>           <NA>
#> 13                                      tables_altered, 1   <NA>           <NA>
#> 14                                      tables_altered, 1   <NA>           <NA>
#> 15                                      tables_altered, 1   <NA>           <NA>
#> 16                                      tables_altered, 1   <NA>           <NA>
#> 17                                      tables_altered, 1   <NA>           <NA>
#> 18                                      tables_altered, 1   <NA>           <NA>
#> 19                                      tables_altered, 1   <NA>           <NA>
#> 20                                      tables_altered, 1   <NA>           <NA>
#> 21                                      tables_altered, 1   <NA>           <NA>
#> 22                                      tables_altered, 1   <NA>           <NA>
#> 23                                      tables_altered, 1   <NA>           <NA>
#> 24                                      tables_altered, 1   <NA>           <NA>
#> 25                                      tables_altered, 1   <NA>           <NA>
#> 26                                      tables_altered, 1   <NA>           <NA>
#> 27                                      tables_altered, 1   <NA>           <NA>
#> 28                                      tables_altered, 1   <NA>           <NA>
#> 29                                      tables_altered, 1   <NA>           <NA>
#> 30                                      tables_altered, 1   <NA>           <NA>
#> 31                                      tables_altered, 1   <NA>           <NA>
#> 32                                      tables_altered, 1   <NA>           <NA>
#> 33                                      tables_altered, 1   <NA>           <NA>
#> 34                                      tables_altered, 1   <NA>           <NA>
#> 35                                      tables_altered, 1   <NA>           <NA>
#> 36                                      tables_altered, 1   <NA>           <NA>
#> 37                                      tables_altered, 1   <NA>           <NA>
#> 38                                      tables_altered, 1   <NA>           <NA>
#> 39                                      tables_altered, 1   <NA>           <NA>
#> 40                                      tables_altered, 1   <NA>           <NA>
#> 41                                      tables_altered, 1   <NA>           <NA>
#> 42                                      tables_altered, 1   <NA>           <NA>
#> 43                                      tables_altered, 1   <NA>           <NA>
#> 44                                      tables_altered, 1   <NA>           <NA>
#> 45                                      tables_altered, 1   <NA>           <NA>
#> 46                                      tables_altered, 1   <NA>           <NA>
#> 47                                      tables_altered, 1   <NA>           <NA>
#> 48                                      tables_altered, 1   <NA>           <NA>
#> 49                                      tables_altered, 1   <NA>           <NA>
#> 50                                      tables_altered, 1   <NA>           <NA>
#> 51                                      tables_altered, 1   <NA>           <NA>
#> 52                                      tables_altered, 1   <NA>           <NA>
#> 53                                      tables_altered, 1   <NA>           <NA>
#> 54                                      tables_altered, 1   <NA>           <NA>
#> 55                                      tables_altered, 1   <NA>           <NA>
#> 56                                      tables_altered, 1   <NA>           <NA>
#> 57                                      tables_altered, 1   <NA>           <NA>
#> 58                                      tables_altered, 1   <NA>           <NA>
#> 59                                      tables_altered, 1   <NA>           <NA>
#> 60                                      tables_altered, 1   <NA>           <NA>
#> 61                                      tables_altered, 1   <NA>           <NA>
#> 62                                      tables_altered, 1   <NA>           <NA>
#> 63                                      tables_altered, 1   <NA>           <NA>
#> 64                                      tables_altered, 1   <NA>           <NA>
#> 65                                      tables_altered, 1   <NA>           <NA>
#> 66                                      tables_altered, 1   <NA>           <NA>
#> 67                                      tables_altered, 1   <NA>           <NA>
#> 68                                      tables_altered, 1   <NA>           <NA>
#> 69                                      tables_altered, 1   <NA>           <NA>
#> 70                                      tables_altered, 1   <NA>           <NA>
#> 71                                      tables_altered, 1   <NA>           <NA>
#> 72                                      tables_altered, 1   <NA>           <NA>
#> 73                                      tables_altered, 1   <NA>           <NA>
#> 74                                      tables_altered, 1   <NA>           <NA>
#> 75                                      tables_altered, 1   <NA>           <NA>
#> 76                                      tables_altered, 1   <NA>           <NA>
#> 77                                      tables_altered, 1   <NA>           <NA>
#> 78                                      tables_altered, 1   <NA>           <NA>
#> 79                                      tables_altered, 1   <NA>           <NA>
#> 80                                      tables_altered, 1   <NA>           <NA>
#> 81                                      tables_altered, 1   <NA>           <NA>
#> 82                                      tables_altered, 1   <NA>           <NA>
#> 83                                      tables_altered, 1   <NA>           <NA>
#> 84                                      tables_altered, 1   <NA>           <NA>
#> 85                                      tables_altered, 1   <NA>           <NA>
#> 86                                      tables_altered, 1   <NA>           <NA>
#> 87                                      tables_altered, 1   <NA>           <NA>
#> 88                                      tables_altered, 1   <NA>           <NA>
#> 89                                tables_inserted_into, 1   <NA>           <NA>
#>    commit_extra_info
#> 1               <NA>
#> 2               <NA>
#> 3               <NA>
#> 4               <NA>
#> 5               <NA>
#> 6               <NA>
#> 7               <NA>
#> 8               <NA>
#> 9               <NA>
#> 10              <NA>
#> 11              <NA>
#> 12              <NA>
#> 13              <NA>
#> 14              <NA>
#> 15              <NA>
#> 16              <NA>
#> 17              <NA>
#> 18              <NA>
#> 19              <NA>
#> 20              <NA>
#> 21              <NA>
#> 22              <NA>
#> 23              <NA>
#> 24              <NA>
#> 25              <NA>
#> 26              <NA>
#> 27              <NA>
#> 28              <NA>
#> 29              <NA>
#> 30              <NA>
#> 31              <NA>
#> 32              <NA>
#> 33              <NA>
#> 34              <NA>
#> 35              <NA>
#> 36              <NA>
#> 37              <NA>
#> 38              <NA>
#> 39              <NA>
#> 40              <NA>
#> 41              <NA>
#> 42              <NA>
#> 43              <NA>
#> 44              <NA>
#> 45              <NA>
#> 46              <NA>
#> 47              <NA>
#> 48              <NA>
#> 49              <NA>
#> 50              <NA>
#> 51              <NA>
#> 52              <NA>
#> 53              <NA>
#> 54              <NA>
#> 55              <NA>
#> 56              <NA>
#> 57              <NA>
#> 58              <NA>
#> 59              <NA>
#> 60              <NA>
#> 61              <NA>
#> 62              <NA>
#> 63              <NA>
#> 64              <NA>
#> 65              <NA>
#> 66              <NA>
#> 67              <NA>
#> 68              <NA>
#> 69              <NA>
#> 70              <NA>
#> 71              <NA>
#> 72              <NA>
#> 73              <NA>
#> 74              <NA>
#> 75              <NA>
#> 76              <NA>
#> 77              <NA>
#> 78              <NA>
#> 79              <NA>
#> 80              <NA>
#> 81              <NA>
#> 82              <NA>
#> 83              <NA>
#> 84              <NA>
#> 85              <NA>
#> 86              <NA>
#> 87              <NA>
#> 88              <NA>
#> 89              <NA>
ducklake_current_snapshot(con, "lake")
#> [1] 88
```

### Configuration

``` r
ducklake_options(con, "lake")
#>   option_name                                                      description
#> 1  created_by                                  Tool used to write the DuckLake
#> 2   data_path                                               Path to data files
#> 3   encrypted Whether or not to encrypt Parquet files written to the data path
#> 4     version                                          DuckLake format version
#>                               value  scope scope_entry
#> 1                 DuckDB d1dc88f950 GLOBAL        <NA>
#> 2 s3://readme-demo-1768427938/data/ GLOBAL        <NA>
#> 3                             false GLOBAL        <NA>
#> 4                               0.3 GLOBAL        <NA>
ducklake_set_option(con, "lake", "parquet_compression", "zstd")
ducklake_options(con, "lake")
#>           option_name
#> 1          created_by
#> 2           data_path
#> 3           encrypted
#> 4 parquet_compression
#> 5             version
#>                                                                                        description
#> 1                                                                  Tool used to write the DuckLake
#> 2                                                                               Path to data files
#> 3                                 Whether or not to encrypt Parquet files written to the data path
#> 4 Compression algorithm for Parquet files (uncompressed, snappy, gzip, zstd, brotli, lz4, lz4_raw)
#> 5                                                                          DuckLake format version
#>                               value  scope scope_entry
#> 1                 DuckDB d1dc88f950 GLOBAL        <NA>
#> 2 s3://readme-demo-1768427938/data/ GLOBAL        <NA>
#> 3                             false GLOBAL        <NA>
#> 4                              zstd GLOBAL        <NA>
#> 5                               0.3 GLOBAL        <NA>
```

``` r
DBI::dbDisconnect(con, shutdown = TRUE)
tools::pskill(pid)
```

### Supported Metadata Databases

DuckLake supports multiple catalog backends

- `DuckDB` : `ducklake:path/to/catalog.ducklake`
- `SQLite`: `ducklake:sqlite://path/to/catalog.db`  
- `PostgreSQL` : `ducklake:postgresql://user:pass@host:5432/db`
- `MySQL`: `ducklake:mysql://user:pass@host:3306/db`

#### Connection Methods

The package provides helpers for different metadata databases

#### Direct Connection

``` r
# DuckDB backend
ducklake_connect_catalog(
  con,
  backend = "duckdb",
  connection_string = "catalog.ducklake",
  data_path = "s3://bucket/data/",
  alias = "lake"
)

# PostgreSQL backend
ducklake_connect_catalog(
  con,
  backend = "postgresql", 
  connection_string = "user:pass@host:5432/db",
  data_path = "s3://bucket/data/",
  alias = "lake"
)
```

##### Secret-based Connection:\*\*

``` r
# Create catalog secret
ducklake_create_catalog_secret(
  con,
  name = "pg_catalog",
  backend = "postgresql",
  connection_string = "user:pass@host:5432/db",
  data_path = "s3://bucket/data/"
)

# Connect using secret
ducklake_connect_catalog(
  con,
  secret_name = "pg_catalog",
  alias = "lake"
)
```

## Command-Line utilities

CLI tools are provided for VCF to Parquet conversion and querying,
including threaded chunking based on contigs using either the
[`bcf_reader`](https://rgenomicsetl.github.io/RBCFTools/inst/scripts/vcf2parquet_duckdb.R)
extension or via [Arrow
IPC](https://rgenomicsetl.github.io/RBCFTools/inst/scripts/vcf2parquet.R)

``` bash
# Get paths using system.file
SCRIPT=$(Rscript -e "cat(system.file('scripts', 'vcf2parquet_duckdb.R', package='RBCFTools'))")
BCF=$(Rscript -e "cat(system.file('extdata', 'test_deep_variant.vcf.gz', package='RBCFTools'))")
OUT_PQ=$(mktemp --suffix=.parquet)
Log=$(mktemp --suffix=.log)

# Convert BCF to Parquet
time $SCRIPT convert --quiet -i $BCF -o $OUT_PQ -t 4  > $Log 2>&1

cat $Log

# Query with DuckDB SQL
$SCRIPT query -i $OUT_PQ -q "SELECT * FROM parquet_scan('$OUT_PQ') LIMIT 5"

# Describe table structure
$SCRIPT query -i $OUT_PQ -q "DESCRIBE SELECT * FROM parquet_scan('$OUT_PQ')"

# Show schema
$SCRIPT schema  --quiet -i $BCF 

# File info
$SCRIPT info -i $OUT_PQ 

rm -f $OUT_PQ
#> 
#> real 0m1.552s
#> user 0m3.553s
#> sys  0m1.937s
#> Building bcf_reader extension...
#>   Build directory: /tmp/Rtmp0EKzgB 
#> Building bcf_reader extension...
#>   Build directory: /tmp/Rtmp0EKzgB
#>   Using htslib from: /usr/local/lib/R/site-library/RBCFTools/htslib/lib
#>   Running: make with explicit htslib paths
#> make[1]: Entering directory '/tmp/Rtmp0EKzgB'
#> rm -rf build
#> make[1]: Leaving directory '/tmp/Rtmp0EKzgB'
#> make[1]: Entering directory '/tmp/Rtmp0EKzgB'
#> mkdir -p build
#> gcc -O2 -Wall -Wextra -Wno-unused-parameter -fPIC -I/usr/local/lib/R/site-library/RBCFTools/htslib/include -I. -c bcf_reader.c -o build/bcf_reader.o
#> gcc -O2 -Wall -Wextra -Wno-unused-parameter -fPIC -I/usr/local/lib/R/site-library/RBCFTools/htslib/include -I. -c vep_parser.c -o build/vep_parser.o
#> gcc -shared -fPIC -o build/libbcf_reader.so build/bcf_reader.o build/vep_parser.o -L/usr/local/lib/R/site-library/RBCFTools/htslib/lib -Wl,-rpath,/usr/local/lib/R/site-library/RBCFTools/htslib/lib -lhts
#> Creating DuckDB extension with metadata...
#> Created: build/bcf_reader.duckdb_extension
#>   Platform: linux_amd64
#>   DuckDB Version: v1.2.0
#>   Extension Version: 1.0.0
#> make[1]: Leaving directory '/tmp/Rtmp0EKzgB'
#> Extension built: /tmp/Rtmp0EKzgB/build/bcf_reader.duckdb_extension
#> ✓ Extension ready: /tmp/Rtmp0EKzgB/build/bcf_reader.duckdb_extension 
#> 
#> Converting VCF to Parquet (DuckDB mode)...
#>   Input: /usr/local/lib/R/site-library/RBCFTools/extdata/test_deep_variant.vcf.gz 
#>   Output: /tmp/tmp.r4vOXRMbFM.parquet 
#>   Compression: zstd 
#>   Row group size: 100000 
#>   Threads: 4 
#> Processing 25 contigs (out of 86 in header) using 4 threads (DuckDB mode)
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0004.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0003.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0002.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0001.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0008.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0007.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0005.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0006.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0012.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0010.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0009.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0011.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0013.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0014.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0016.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0015.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0018.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0020.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0017.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0024.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0022.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0021.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0019.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0025.parquet
#> Wrote: /tmp/Rtmp0EKzgB/vcf_duckdb_parallel_3d8767fb3dc8/contig_0023.parquet
#> Merging temporary Parquet files... to /tmp/tmp.r4vOXRMbFM.parquet
#> Merged 25 parquet files -> tmp.r4vOXRMbFM.parquet (368319 rows)
#> 
#> ✓ Conversion complete!
#>   Time: 0.90 seconds
#>   Output size: 3.77 MB
#> Running query on Parquet file...
#>   CHROM    POS   ID REF ALT QUAL  FILTER INFO_END FORMAT_GT_test_deep_variant
#> 1     1 536895 <NA>   T   C  0.1 RefCall       NA                         ./.
#> 2     1 536924 <NA>   G   A  0.1 RefCall       NA                         ./.
#> 3     1 536948 <NA>   A   G  0.0 RefCall       NA                         0/0
#> 4     1 536986 <NA>   G   T  0.0 RefCall       NA                         0/0
#> 5     1 544490 <NA>   A   G  0.8 RefCall       NA                         ./.
#>   FORMAT_GQ_test_deep_variant FORMAT_DP_test_deep_variant
#> 1                          18                         106
#> 2                          18                         118
#> 3                          31                         104
#> 4                          23                         115
#> 5                           8                          10
#>   FORMAT_MIN_DP_test_deep_variant FORMAT_AD_test_deep_variant
#> 1                              NA                      46, 52
#> 2                              NA                      55, 60
#> 3                              NA                      91, 13
#> 4                              NA                      55, 60
#> 5                              NA                        6, 4
#>   FORMAT_VAF_test_deep_variant FORMAT_PL_test_deep_variant
#> 1                     0.490566                   0, 19, 25
#> 2                     0.508475                   0, 21, 20
#> 3                        0.125                   0, 31, 38
#> 4                     0.521739                   0, 23, 29
#> 5                          0.4                    0, 7, 15
#>   FORMAT_MED_DP_test_deep_variant
#> 1                              NA
#> 2                              NA
#> 3                              NA
#> 4                              NA
#> 5                              NA
#> Running query on Parquet file...
#>                        column_name column_type null  key default extra
#> 1                            CHROM     VARCHAR  YES <NA>    <NA>  <NA>
#> 2                              POS      BIGINT  YES <NA>    <NA>  <NA>
#> 3                               ID     VARCHAR  YES <NA>    <NA>  <NA>
#> 4                              REF     VARCHAR  YES <NA>    <NA>  <NA>
#> 5                              ALT   VARCHAR[]  YES <NA>    <NA>  <NA>
#> 6                             QUAL      DOUBLE  YES <NA>    <NA>  <NA>
#> 7                           FILTER   VARCHAR[]  YES <NA>    <NA>  <NA>
#> 8                         INFO_END     INTEGER  YES <NA>    <NA>  <NA>
#> 9      FORMAT_GT_test_deep_variant     VARCHAR  YES <NA>    <NA>  <NA>
#> 10     FORMAT_GQ_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 11     FORMAT_DP_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 12 FORMAT_MIN_DP_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> 13     FORMAT_AD_test_deep_variant   INTEGER[]  YES <NA>    <NA>  <NA>
#> 14    FORMAT_VAF_test_deep_variant     FLOAT[]  YES <NA>    <NA>  <NA>
#> 15     FORMAT_PL_test_deep_variant   INTEGER[]  YES <NA>    <NA>  <NA>
#> 16 FORMAT_MED_DP_test_deep_variant     INTEGER  YES <NA>    <NA>  <NA>
#> Building bcf_reader extension...
#>   Build directory: /tmp/RtmpfnWqkW 
#> Building bcf_reader extension...
#>   Build directory: /tmp/RtmpfnWqkW
#>   Using htslib from: /usr/local/lib/R/site-library/RBCFTools/htslib/lib
#>   Running: make with explicit htslib paths
#> make[1]: Entering directory '/tmp/RtmpfnWqkW'
#> rm -rf build
#> make[1]: Leaving directory '/tmp/RtmpfnWqkW'
#> make[1]: Entering directory '/tmp/RtmpfnWqkW'
#> mkdir -p build
#> gcc -O2 -Wall -Wextra -Wno-unused-parameter -fPIC -I/usr/local/lib/R/site-library/RBCFTools/htslib/include -I. -c bcf_reader.c -o build/bcf_reader.o
#> gcc -O2 -Wall -Wextra -Wno-unused-parameter -fPIC -I/usr/local/lib/R/site-library/RBCFTools/htslib/include -I. -c vep_parser.c -o build/vep_parser.o
#> gcc -shared -fPIC -o build/libbcf_reader.so build/bcf_reader.o build/vep_parser.o -L/usr/local/lib/R/site-library/RBCFTools/htslib/lib -Wl,-rpath,/usr/local/lib/R/site-library/RBCFTools/htslib/lib -lhts
#> Creating DuckDB extension with metadata...
#> Created: build/bcf_reader.duckdb_extension
#>   Platform: linux_amd64
#>   DuckDB Version: v1.2.0
#>   Extension Version: 1.0.0
#> make[1]: Leaving directory '/tmp/RtmpfnWqkW'
#> Extension built: /tmp/RtmpfnWqkW/build/bcf_reader.duckdb_extension
#> ✓ Extension ready: /tmp/RtmpfnWqkW/build/bcf_reader.duckdb_extension 
#> 
#> VCF DuckDB Schema for: /usr/local/lib/R/site-library/RBCFTools/extdata/test_deep_variant.vcf.gz 
#> 
#>                      column_name column_type
#>                            CHROM   character
#>                              POS     numeric
#>                               ID   character
#>                              REF   character
#>                              ALT        list
#>                             QUAL     numeric
#>                           FILTER        list
#>                         INFO_END     integer
#>      FORMAT_GT_test_deep_variant   character
#>      FORMAT_GQ_test_deep_variant     integer
#>      FORMAT_DP_test_deep_variant     integer
#>  FORMAT_MIN_DP_test_deep_variant     integer
#>      FORMAT_AD_test_deep_variant        list
#>     FORMAT_VAF_test_deep_variant        list
#>      FORMAT_PL_test_deep_variant        list
#>  FORMAT_MED_DP_test_deep_variant     integer
#> Parquet File Information: /tmp/tmp.r4vOXRMbFM.parquet 
#> 
#> File size: 3.77 MB 
#> Total rows: 368319 
#> Number of columns: 27 
#> 
#> Schema (top-level columns):
#>                             name       type
#>                            CHROM BYTE_ARRAY
#>                              POS      INT64
#>                               ID BYTE_ARRAY
#>                              REF BYTE_ARRAY
#>                              ALT       <NA>
#>                             QUAL     DOUBLE
#>                           FILTER       <NA>
#>                         INFO_END      INT32
#>      FORMAT_GT_test_deep_variant BYTE_ARRAY
#>      FORMAT_GQ_test_deep_variant      INT32
#>      FORMAT_DP_test_deep_variant      INT32
#>  FORMAT_MIN_DP_test_deep_variant      INT32
#>      FORMAT_AD_test_deep_variant       <NA>
#>     FORMAT_VAF_test_deep_variant       <NA>
#>      FORMAT_PL_test_deep_variant       <NA>
#>  FORMAT_MED_DP_test_deep_variant      INT32
```

## References

- [bcftools documentation](https://samtools.github.io/bcftools/)

- [bcftools GitHub](https://github.com/samtools/bcftools)

- [htslib GitHub](https://github.com/samtools/htslib)

- [arrow-nanoarrow](https://arrow.apache.org/nanoarrow/)

- [Ducklake minio
  Example](https://github.com/duckdb/ducklake/blob/main/examples/minio-demo-server/README.md)
