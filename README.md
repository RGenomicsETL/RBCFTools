
<!-- README.md is generated from README.Rmd. Please edit that file -->

# RBCFTools

<!-- badges: start -->

[![R-CMD-check](https://github.com/RGenomicsETL/RBCFTools/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/RGenomicsETL/RBCFTools/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

RBCFTools provides R bindings to
[bcftools](https://github.com/samtools/bcftools) and
[htslib](https://github.com/samtools/htslib), the standard tools for
reading and manipulating VCF/BCF files. The package bundles these
libraries and command-line tools (bcftools, bgzip, tabix), so no
external installation is required. When compiled with libcurl, remote
file access from S3, GCS, and HTTP URLs is supported.

The package also includes experimental support for streaming VCF/BCF to
Apache Arrow (IPC) format via
[nanoarrow](https://arrow.apache.org/nanoarrow/), with export to Parquet
format using [duckdb](https://duckdb.org/)

## Installation

You can install the development version of RBCFTools from
[GitHub](https://github.com/RGenomicsETL/RBCFTools) with:

``` r
install.packages('RBCFTools', repos = c('https://rgenomicsetl.r-universe.dev', 'https://cloud.r-project.org'))
```

## Version Information

``` r
library(RBCFTools)

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

## Example Query Remote VCF from S3 using bcftools

With libcurl support, bcftools can directly query remote files. Here we
count variants in a small region from the 1000 Genomes cohort VCF on S3:

``` r
# Setup environment for remote file access (S3/GCS)
setup_hts_env()

# Build S3 URL for 1000 Genomes cohort VCF
s3_base <- "s3://1000genomes-dragen-v3.7.6/data/cohorts/"
s3_path <- "gvcf-genotyper-dragen-3.7.6/hg19/3202-samples-cohort/"
vcf_file <- "3202_samples_cohort_gg_chr22.vcf.gz"
vcf_url <- paste0(s3_base, s3_path, vcf_file)

# Query a small region (chr22:20000000-20100000) and count variants
result <- system2(
  bcftools_path(),
  args = c("view", "-H", "-r", "chr22:20000000-20100000", vcf_url),
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
#>    CHROM   POS         ID REF ALT QUAL FILTER INFO.DP INFO.AF INFO.CB
#> 1      1 10583 rs58108140   G   A   NA   PASS      NA    NULL    NULL
#> 2      1 11508       <NA>   A   G   NA   PASS      NA    NULL    NULL
#> 3      1 11565       <NA>   G   T   NA   PASS      NA    NULL    NULL
#> 4      1 13116       <NA>   T   G   NA   PASS      NA    NULL    NULL
#> 5      1 13327       <NA>   G   C   NA   PASS      NA    NULL    NULL
#> 6      1 14699       <NA>   C   G   NA   PASS      NA    NULL    NULL
#> 7      1 15274       <NA>   A   T   NA   PASS      NA    NULL    NULL
#> 8      1 15820       <NA>   G   T   NA   PASS      NA    NULL    NULL
#> 9      1 16257       <NA>   G   C   NA   PASS      NA    NULL    NULL
#> 10     1 16378       <NA>   T   C   NA   PASS      NA    NULL    NULL
#> 11     1 28376       <NA>   G   A   NA   PASS      NA    NULL    NULL
#>    INFO.EUR_R2 INFO.AFR_R2 INFO.ASN_R2 INFO.AC INFO.AN samples.HG00098.AD
#> 1           NA          NA          NA    NULL      NA               NULL
#> 2           NA          NA          NA    NULL      NA               NULL
#> 3           NA          NA          NA    NULL      NA               NULL
#> 4           NA          NA          NA    NULL      NA               NULL
#> 5           NA          NA          NA    NULL      NA               NULL
#> 6           NA          NA          NA    NULL      NA               NULL
#> 7           NA          NA          NA    NULL      NA               NULL
#> 8           NA          NA          NA    NULL      NA               NULL
#> 9           NA          NA          NA    NULL      NA               NULL
#> 10          NA          NA          NA    NULL      NA               NULL
#> 11          NA          NA          NA    NULL      NA               NULL
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
parquet file and perform queries on the parquet file

``` r

parquet_file <- tempfile(fileext = ".parquet")
vcf_to_parquet(bcf_file, parquet_file, compression = "snappy")
#> Wrote 11 rows to /tmp/RtmpoQyoDr/file2caf0b35298e18.parquet
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
#> 1 /tmp/RtmpoQyoDr/file2caf0b35298e18.parquet            0                 11
#> 2 /tmp/RtmpoQyoDr/file2caf0b35298e18.parquet            0                 11
#> 3 /tmp/RtmpoQyoDr/file2caf0b35298e18.parquet            0                 11
#> 4 /tmp/RtmpoQyoDr/file2caf0b35298e18.parquet            0                 11
#> 5 /tmp/RtmpoQyoDr/file2caf0b35298e18.parquet            0                 11
#> 6 /tmp/RtmpoQyoDr/file2caf0b35298e18.parquet            0                 11
#>   row_group_num_columns row_group_bytes column_id file_offset num_values
#> 1                    36            2515         0           0         11
#> 2                    36            2515         1           0         11
#> 3                    36            2515         2           0         11
#> 4                    36            2515         3           0         11
#> 5                    36            2515         4           0         11
#> 6                    36            2515         5           0         11
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
#> 1                1874                  47         TRUE         TRUE
#> 2                  NA                  NA         TRUE         TRUE
#> 3                1921                  47         TRUE         TRUE
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
#> Wrote 11 rows to /tmp/RtmpoQyoDr/file2caf0b769b6cc4.parquet (streaming mode)
# describe using duckdb
```

### Query with VCF duckdb

``` r
# SQL queries on BCF (requires duckdb package)
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

### Stream Remote VCF to Arrow

``` r
# Stream remote VCF region directly to Arrow from S3
vcf_url <- paste0(s3_base, s3_path, vcf_file)
stream <- vcf_open_arrow(
    vcf_url,
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

## References

- [bcftools documentation](https://samtools.github.io/bcftools/)
- [bcftools GitHub](https://github.com/samtools/bcftools)
- [htslib GitHub](https://github.com/samtools/htslib)
- [arrow-nanoarrow](https://arrow.apache.org/nanoarrow/)
