# RBCFTools

RBCFTools provides R bindings to
[bcftools](https://github.com/samtools/bcftools) and
[htslib](https://github.com/samtools/htslib), the standard tools for
reading and manipulating VCF/BCF files. The package bundles these
libraries and command-line tools (bcftools, bgzip, tabix), so no
external installation is required. When compiled with libcurl, remote
file access from S3, GCS, and HTTP URLs is supported. The package also
includes experimental support for streaming VCF/BCF to Apache Arrow
(IPC) format via [nanoarrow](https://arrow.apache.org/nanoarrow/), with
export to Parquet format using [duckdb](https://duckdb.org/) via either
the [duckdb nanoarrow
extension](https://duckdb.org/community_extensions/extensions/nanoarrow.html)
or a
[`bcf_reader`](https://rgenomicsetl.github.io/RBCFTools/inst/duckdb_bcf_reader_extension/)
extension bundled in this package.

## Installation

You can install the development version of RBCFTools from
[GitHub](https://github.com/RGenomicsETL/RBCFTools) for unix-alikes (we
do not support windows)

``` r
install.packages('RBCFTools', repos = c('https://rgenomicsetl.r-universe.dev', 'https://cloud.r-project.org'))
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
#> [1] "/usr/lib64/R/library/RBCFTools/bcftools/bin/bcftools"
bgzip_path()
#> [1] "/usr/lib64/R/library/RBCFTools/htslib/bin/bgzip"
tabix_path()
#> [1] "/usr/lib64/R/library/RBCFTools/htslib/bin/tabix"
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
#> [1] "build=configure libcurl=yes S3=yes GCS=yes libdeflate=yes lzma=yes bzip2=yes plugins=yes plugin-path=/usr/lib64/R/library/RBCFTools/htslib/libexec/htslib: htscodecs=1.6.5"
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

## Example Query Remote VCF from S3 using bcftools

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

# Query a small region (chr22:20000000-20100000) and count variants
result <- system2(
  bcftools_path(),
  args = c("view", "-H", "-r", "chr22:20000000-20100000", s3_vcf_uri),
  stdout = TRUE,
  stderr = FALSE
)
length(result)
#> [1] 4622
```

## (Experimental) VCF to Arrow

RBCFTools provides streaming VCF/BCF to Apache Arrow (IPC) conversion
via [nanoarrow](https://arrow.apache.org/nanoarrow/). This enables
integration with tools like [duckdb](https://github.com/duckdb/duckdb-r)
and Parquet format convertion.

The Arrow conversion performs VCF spec conformance checks on headers
(similar to htslib’s `bcf_hdr_check_sanity()`) and emits R warnings when
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

nanoarrow::convert_array(batch)
#>    CHROM   POS         ID REF ALT QUAL FILTER INFO.DP INFO.AF       INFO.CB
#> 1      1 10583 rs58108140   G   A   NA   PASS    1557   0.162 UM,BI,BC,NCBI
#> 2      1 11508       <NA>   A   G   NA   PASS      23    0.72         BI,BC
#> 3      1 11565       <NA>   G   T   NA   PASS      45       0         BI,BC
#> 4      1 13116       <NA>   T   G   NA   PASS    2400   0.016         UM,BI
#> 5      1 13327       <NA>   G   C   NA   PASS    2798    0.01         BI,BC
#> 6      1 14699       <NA>   C   G   NA   PASS     408    0.02         BI,BC
#> 7      1 15274       <NA>   A   T   NA   PASS    1739    0.91         UM,BI
#> 8      1 15820       <NA>   G   T   NA   PASS    1643   0.114      UM,BI,BC
#> 9      1 16257       <NA>   G   C   NA   PASS    5301    0.12    BI,BC,NCBI
#> 10     1 16378       <NA>   T   C   NA   PASS     820    0.51    BI,BC,NCBI
#> 11     1 28376       <NA>   G   A   NA   PASS    2943   0.026         UM,BI
#>    INFO.EUR_R2 INFO.AFR_R2 INFO.ASN_R2 INFO.AC INFO.AN samples.HG00098.AD
#> 1        0.248          NA          NA       0       6               NULL
#> 2        0.001          NA          NA       6       6               NULL
#> 3           NA       0.003          NA       0       6               NULL
#> 4        0.106       0.286          NA       0       6               NULL
#> 5        0.396       0.481          NA       0       6               NULL
#> 6        0.061       0.184          NA       0       6               NULL
#> 7        0.063       0.194          NA       6       6               NULL
#> 8        0.147       0.209          NA       0       6               NULL
#> 9        0.627       0.719          NA       1       6               NULL
#> 10       0.107       0.174          NA       3       6               NULL
#> 11       0.004       0.020          NA       6       6               NULL
#>    samples.HG00098.DP samples.HG00098.GL samples.HG00098.GQ samples.HG00098.GT
#> 1                  NA               NULL               3.28                0|0
#> 2                  NA               NULL               2.22                1|1
#> 3                  NA               NULL               1.48                0|0
#> 4                  NA               NULL               9.17                0|0
#> 5                  NA               NULL              15.80                0|0
#> 6                  NA               NULL               6.29                0|0
#> 7                  NA               NULL               5.08                1|1
#> 8                  NA               NULL               7.01                0|0
#> 9                  NA               NULL               5.61                0|0
#> 10                 NA               NULL               1.29                1|1
#> 11                 NA               NULL               2.68                1|1
#>    samples.HG00098.GD samples.HG00098.OG samples.HG00100.AD samples.HG00100.DP
#> 1                  NA                ./.               NULL                 NA
#> 2                  NA                ./.               NULL                 NA
#> 3                  NA                ./.               NULL                 NA
#> 4                  NA                ./.               NULL                 NA
#> 5                  NA                ./.               NULL                 NA
#> 6                  NA                ./.               NULL                 NA
#> 7                  NA                ./.               NULL                 NA
#> 8                  NA                ./.               NULL                 NA
#> 9                  NA                ./.               3, 0                  3
#> 10                 NA                ./.               3, 1                  1
#> 11                 NA                ./.               NULL                 NA
#>     samples.HG00100.GL samples.HG00100.GQ samples.HG00100.GT samples.HG00100.GD
#> 1                 NULL               3.28                0|0                 NA
#> 2                 NULL               2.22                1|1                 NA
#> 3                 NULL               1.48                0|0                 NA
#> 4                 NULL               9.17                0|0                 NA
#> 5                 NULL              15.80                0|0                 NA
#> 6                 NULL               6.29                0|0                 NA
#> 7                 NULL               5.08                1|1                 NA
#> 8                 NULL               7.01                0|0                 NA
#> 9  0.00, -0.90, -12.68              13.77                0|0                 NA
#> 10  0.00, -0.30, -3.86               2.95                0|0                 NA
#> 11                NULL               2.68                1|1                 NA
#>    samples.HG00100.OG samples.HG00106.AD samples.HG00106.DP  samples.HG00106.GL
#> 1                 ./.               NULL                 NA                NULL
#> 2                 ./.               NULL                 NA                NULL
#> 3                 ./.               NULL                 NA                NULL
#> 4                 ./.               NULL                 NA                NULL
#> 5                 ./.               2, 0                  2  0.00, -0.60, -8.78
#> 6                 ./.               NULL                 NA                NULL
#> 7                 ./.               NULL                 NA                NULL
#> 8                 ./.               NULL                 NA                NULL
#> 9                 ./.               1, 1                  2 -3.65, -0.60, -4.09
#> 10                ./.               4, 5                  2 -2.70, -0.60, -3.86
#> 11                ./.               NULL                 NA                NULL
#>    samples.HG00106.GQ samples.HG00106.GT samples.HG00106.GD samples.HG00106.OG
#> 1                3.28                0|0                 NA                ./.
#> 2                2.22                1|1                 NA                ./.
#> 3                1.48                0|0                 NA                ./.
#> 4                9.17                0|0                 NA                ./.
#> 5               21.74                0|0                 NA                ./.
#> 6                6.29                0|0                 NA                ./.
#> 7                5.08                1|1                 NA                ./.
#> 8                7.01                0|0                 NA                ./.
#> 9               25.82                0|1                 NA                ./.
#> 10              23.85                1|0                 NA                ./.
#> 11               2.68                1|1                 NA                ./.
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

### Write to Parquet

Using [duckdb](https://github.com/duckdb/duckdb-r) to convert BCF to
parquet file and perform queries on the parquet file. This involve vcf
stream conversion to data.frame

``` r

parquet_file <- tempfile(fileext = ".parquet")
vcf_to_parquet(bcf_file, parquet_file, compression = "snappy")
#> Wrote 11 rows to /tmp/RtmpdRJttP/file192e922ad4138e.parquet
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
#>                                    file_name row_group_id row_group_num_rows
#> 1 /tmp/RtmpdRJttP/file192e922ad4138e.parquet            0                 11
#> 2 /tmp/RtmpdRJttP/file192e922ad4138e.parquet            0                 11
#> 3 /tmp/RtmpdRJttP/file192e922ad4138e.parquet            0                 11
#> 4 /tmp/RtmpdRJttP/file192e922ad4138e.parquet            0                 11
#> 5 /tmp/RtmpdRJttP/file192e922ad4138e.parquet            0                 11
#> 6 /tmp/RtmpdRJttP/file192e922ad4138e.parquet            0                 11
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
vcf_to_parquet(
    bcf_larger,
    outfile,
    streaming = TRUE,
    batch_size = 10000L,
    row_group_size = 100000L,
    compression = "zstd"
)
#> Wrote 11 rows to /tmp/RtmpdRJttP/file192e9299ce43a.parquet (streaming mode)
# describe using duckdb
```

### Query VCF with duckdb

SQL queries on BCF using duckdb package. For now this is somehow limited
due to convertion from arrow streams to data frame

``` r
vcf_query(bcf_file, "SELECT CHROM, COUNT(*) as n FROM vcf GROUP BY CHROM")
#>   CHROM  n
#> 1     1 11

# Filter variants by position
vcf_query(bcf_file, "SELECT CHROM, POS, REF, ALT FROM vcf  LIMIT 5")
#>   CHROM   POS REF ALT
#> 1     1 10583   G   A
#> 2     1 11508   A   G
#> 3     1 11565   G   T
#> 4     1 13116   T   G
#> 5     1 13327   G   C
```

### Query VCF with DuckDB Extension

A native DuckDB extension (`bcf_reader`) for direct SQL queries on
VCF/BCF files without Arrow conversion overhead:

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

### Stream Remote VCF to Arrow

Stream remote VCF region directly to Arrow from S3

``` r
s3_vcf_uri <- paste0(s3_base, s3_path, s3_vcf_file)
stream <- vcf_open_arrow(
    s3_vcf_uri,
    region = "chr22:16050000-16050500",
    batch_size = 1000L
)

# Convert to data.frame
df <- as.data.frame(nanoarrow::convert_array_stream(stream))
df[, c("CHROM", "POS", "REF", "ALT")] |> head()
#>   CHROM      POS REF                  ALT
#> 1 chr22 16050036   A C        , <NON_REF>
#> 2 chr22 16050151   T G        , <NON_REF>
#> 3 chr22 16050213   C T        , <NON_REF>
#> 4 chr22 16050219   C A        , <NON_REF>
#> 5 chr22 16050224   A C        , <NON_REF>
#> 6 chr22 16050229   C A        , <NON_REF>
```

### Command-Line Tool

A CLI tool is provided for VCF to Parquet conversion and querying,
including threaded chunking based on contigs

``` bash
# Get paths using system.file
SCRIPT=$(Rscript -e "cat(system.file('scripts', 'vcf2parquet.R', package='RBCFTools'))")
BCF=$(Rscript -e "cat(system.file('extdata', '1000G_3samples.bcf', package='RBCFTools'))")
OUT_PQ=$(mktemp --suffix=.parquet)

# Convert BCF to Parquet
$SCRIPT convert --quiet -i $BCF -o $OUT_PQ

# Query with DuckDB SQL
$SCRIPT query -i $OUT_PQ -q "SELECT CHROM, POS, REF, ALT FROM parquet_scan('$OUT_PQ') LIMIT 5"

# Describe table structure
$SCRIPT query -i $OUT_PQ -q "DESCRIBE SELECT * FROM parquet_scan('$OUT_PQ')"

# Show schema
$SCRIPT schema 0 --quiet -i $BCF

# File info
$SCRIPT info -i $OUT_PQ

rm -f $OUT_PQ
#> Converting VCF to Parquet...
#>   Input: /usr/lib64/R/library/RBCFTools/extdata/1000G_3samples.bcf 
#>   Output: /tmp/tmp.7Z3syeVNeI.parquet 
#>   Compression: zstd 
#>   Batch size: 10000 
#>   Threads: 1 
#>   Streaming: FALSE 
#>   Include INFO: TRUE 
#>   Include FORMAT: TRUE 
#> [W::bcf_hdr_check_sanity] AD should be declared as Number=R
#> [W::bcf_hdr_check_sanity] GQ should be declared as Type=Integer
#> [W::bcf_hdr_check_sanity] GT should be declared as Number=1
#> Wrote 11 rows to /tmp/tmp.7Z3syeVNeI.parquet
#> 
#> ✓ Conversion complete!
#>   Time: 0.78 seconds
#>   Output size: 0.01 MB
#> Running query on Parquet file(s)...
#>   CHROM   POS REF ALT
#> 1     1 10583   G   A
#> 2     1 11508   A   G
#> 3     1 11565   G   T
#> 4     1 13116   T   G
#> 5     1 13327   G   C
#> Running query on Parquet file(s)...
#>   column_name
#> 1       CHROM
#> 2         POS
#> 3          ID
#> 4         REF
#> 5         ALT
#> 6        QUAL
#> 7      FILTER
#> 8        INFO
#> 9     samples
#>                                                                                                                                                                                                                                                                                                    column_type
#> 1                                                                                                                                                                                                                                                                                                      VARCHAR
#> 2                                                                                                                                                                                                                                                                                                       DOUBLE
#> 3                                                                                                                                                                                                                                                                                                      VARCHAR
#> 4                                                                                                                                                                                                                                                                                                      VARCHAR
#> 5                                                                                                                                                                                                                                                                                                    VARCHAR[]
#> 6                                                                                                                                                                                                                                                                                                       DOUBLE
#> 7                                                                                                                                                                                                                                                                                                    VARCHAR[]
#> 8                                                                                                                                                                                         STRUCT(DP INTEGER, AF DOUBLE[], CB VARCHAR[], EUR_R2 DOUBLE, AFR_R2 DOUBLE, ASN_R2 DOUBLE, AC INTEGER[], AN INTEGER)
#> 9 STRUCT(HG00098 STRUCT(AD BLOB, DP INTEGER, GL BLOB, GQ DOUBLE, GT VARCHAR, GD DOUBLE, OG VARCHAR), HG00100 STRUCT(AD INTEGER[], DP INTEGER, GL DOUBLE[], GQ DOUBLE, GT VARCHAR, GD DOUBLE, OG VARCHAR), HG00106 STRUCT(AD INTEGER[], DP INTEGER, GL DOUBLE[], GQ DOUBLE, GT VARCHAR, GD DOUBLE, OG VARCHAR))
#>   null  key default extra
#> 1  YES <NA>    <NA>  <NA>
#> 2  YES <NA>    <NA>  <NA>
#> 3  YES <NA>    <NA>  <NA>
#> 4  YES <NA>    <NA>  <NA>
#> 5  YES <NA>    <NA>  <NA>
#> 6  YES <NA>    <NA>  <NA>
#> 7  YES <NA>    <NA>  <NA>
#> 8  YES <NA>    <NA>  <NA>
#> 9  YES <NA>    <NA>  <NA>
#> Unknown option: 0 
#> Parquet File Information: /tmp/tmp.7Z3syeVNeI.parquet 
#> 
#> File size: 0.01 MB 
#> Total rows: 11 
#> Number of columns: 60 
#> 
#> Schema (top-level columns):
#>     name       type
#>    CHROM BYTE_ARRAY
#>      POS     DOUBLE
#>       ID BYTE_ARRAY
#>      REF BYTE_ARRAY
#>      ALT       <NA>
#>     QUAL     DOUBLE
#>   FILTER       <NA>
#>     INFO       <NA>
#>       DP      INT32
#>       AF       <NA>
#>       CB       <NA>
#>   EUR_R2     DOUBLE
#>   AFR_R2     DOUBLE
#>   ASN_R2     DOUBLE
#>       AC       <NA>
#>       AN      INT32
#>  samples       <NA>
#>  HG00098       <NA>
#>       AD BYTE_ARRAY
#>       DP      INT32
#>       GL BYTE_ARRAY
#>       GQ     DOUBLE
#>       GT BYTE_ARRAY
#>       GD     DOUBLE
#>       OG BYTE_ARRAY
#>  HG00100       <NA>
#>       AD       <NA>
#>       DP      INT32
#>       GL       <NA>
#>       GQ     DOUBLE
#>       GT BYTE_ARRAY
#>       GD     DOUBLE
#>       OG BYTE_ARRAY
#>  HG00106       <NA>
#>       AD       <NA>
#>       DP      INT32
#>       GL       <NA>
#>       GQ     DOUBLE
#>       GT BYTE_ARRAY
#>       GD     DOUBLE
#>       OG BYTE_ARRAY
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

## Limitations and issues

The Arrow supports involves a lot of copies at the C level, let alone
additional copies and converstions when converting to parquet including
Arrow IPC file serialization. Same limitation applies to the SQL query
interface. In theory we can use the arrow package to get `arrow_table`
format that can be registered by `duckdb` but this is an additional
dependency. There is no particular attempt to parse further
vep/snpeff/annovar info fields.

## Future directions

We should improve the code, avoid copies, add more tests and maybe
[ducklake](https://github.com/duckdb/ducklake) support

## References

- [bcftools documentation](https://samtools.github.io/bcftools/)

- [bcftools GitHub](https://github.com/samtools/bcftools)

- [htslib GitHub](https://github.com/samtools/htslib)

- [arrow-nanoarrow](https://arrow.apache.org/nanoarrow/)
