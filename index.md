# RBCFTools

RBCFTools provides R bindings to
[bcftools](https://github.com/samtools/bcftools) and
[htslib](https://github.com/samtools/htslib), the standard tools for
reading and manipulating VCF/BCF files. The package bundles these
libraries, so no external installation is required.

## Installation

You can install the development version of RBCFTools from
[GitHub](https://github.com/RGenomicsETL/RBCFTools) with:

``` r
# install.packages("pak")
pak::pak("RGenomicsETL/RBCFTools")
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
# Main executables
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

## Example: Query Remote VCF from S3

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

RBCFTools provides streaming VCF/BCF to Apache Arrow conversion via
[nanoarrow](https://arrow.apache.org/nanoarrow/). This enables
integration with tools like duckdb, and parquet format

### Read VCF as Arrow Stream

``` r
# Open BCF as Arrow array stream
stream <- vcf_open_arrow(bcf_file, batch_size = 100L)

# Read first batch
batch <- stream$get_next()
#> Warning in x$get_schema(): FORMAT/AD should be declared as Number=R per VCF
#> spec; correcting schema
#> Warning in x$get_schema(): FORMAT/GQ should be declared as Type=Integer per VCF
#> spec; correcting schema
#> Warning in x$get_schema(): FORMAT/GT should be declared as Number=1 per VCF
#> spec; correcting schema
#> Warning in x$get_schema(): FORMAT/AD should be declared as Number=R per VCF
#> spec; correcting schema
#> Warning in x$get_schema(): FORMAT/GQ should be declared as Type=Integer per VCF
#> spec; correcting schema
#> Warning in x$get_schema(): FORMAT/GT should be declared as Number=1 per VCF
#> spec; correcting schema
b <- nanoarrow::convert_array(batch)
b
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
#> 1                  NA               NULL                 NA                0|0
#> 2                  NA               NULL                 NA                1|1
#> 3                  NA               NULL                 NA                0|0
#> 4                  NA               NULL                 NA                0|0
#> 5                  NA               NULL                 NA                0|0
#> 6                  NA               NULL                 NA                0|0
#> 7                  NA               NULL                 NA                1|1
#> 8                  NA               NULL                 NA                0|0
#> 9                  NA               NULL                 NA                0|0
#> 10                 NA               NULL                 NA                1|1
#> 11                 NA               NULL                 NA                1|1
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
#> 1                 NULL                 NA                0|0                 NA
#> 2                 NULL                 NA                1|1                 NA
#> 3                 NULL                 NA                0|0                 NA
#> 4                 NULL                 NA                0|0                 NA
#> 5                 NULL                 NA                0|0                 NA
#> 6                 NULL                 NA                0|0                 NA
#> 7                 NULL                 NA                1|1                 NA
#> 8                 NULL                 NA                0|0                 NA
#> 9  0.00, -0.90, -12.68                 NA                0|0                 NA
#> 10  0.00, -0.30, -3.86                 NA                0|0                 NA
#> 11                NULL                 NA                1|1                 NA
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
#> 1                  NA                0|0                 NA                ./.
#> 2                  NA                1|1                 NA                ./.
#> 3                  NA                0|0                 NA                ./.
#> 4                  NA                0|0                 NA                ./.
#> 5                  NA                0|0                 NA                ./.
#> 6                  NA                0|0                 NA                ./.
#> 7                  NA                1|1                 NA                ./.
#> 8                  NA                0|0                 NA                ./.
#> 9                  NA                0|1                 NA                ./.
#> 10                 NA                1|0                 NA                ./.
#> 11                 NA                1|1                 NA                ./.
```

### Convert to Data Frame

``` r
# Convert entire BCF to data.frame
df <- vcf_to_arrow(bcf_file, as = "data.frame")
#> Warning in nanoarrow::convert_array_stream(stream): FORMAT/AD should be
#> declared as Number=R per VCF spec; correcting schema
#> Warning in nanoarrow::convert_array_stream(stream): FORMAT/GQ should be
#> declared as Type=Integer per VCF spec; correcting schema
#> Warning in nanoarrow::convert_array_stream(stream): FORMAT/GT should be
#> declared as Number=1 per VCF spec; correcting schema
#> Warning in nanoarrow::convert_array_stream(stream): FORMAT/AD should be
#> declared as Number=R per VCF spec; correcting schema
#> Warning in nanoarrow::convert_array_stream(stream): FORMAT/GQ should be
#> declared as Type=Integer per VCF spec; correcting schema
#> Warning in nanoarrow::convert_array_stream(stream): FORMAT/GT should be
#> declared as Number=1 per VCF spec; correcting schema
head(df[, c("CHROM", "POS", "REF", "ALT", "QUAL")])
#>   CHROM   POS REF ALT QUAL
#> 1     1 10583   G   A   NA
#> 2     1 11508   A   G   NA
#> 3     1 11565   G   T   NA
#> 4     1 13116   T   G   NA
#> 5     1 13327   G   C   NA
#> 6     1 14699   C   G   NA
```

### Write to Parquet

If you have the arrow package installed

``` r
# Convert BCF to Parquet
vcf_to_parquet(bcf_file, parquet_file, compression = "gzip")
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/AD should
#> be declared as Number=R per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GQ should
#> be declared as Type=Integer per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GT should
#> be declared as Number=1 per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/AD should
#> be declared as Number=R per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GQ should
#> be declared as Type=Integer per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GT should
#> be declared as Number=1 per VCF spec; correcting schema
#> Wrote 11 rows to /tmp/Rtmp04dGr8/file2b6c2444e0d66a.parquet

# Read back with arrow
pq_bcf <- arrow::read_parquet(parquet_file)
pq_bcf
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
#> 1                  NA               NULL                 NA                0|0
#> 2                  NA               NULL                 NA                1|1
#> 3                  NA               NULL                 NA                0|0
#> 4                  NA               NULL                 NA                0|0
#> 5                  NA               NULL                 NA                0|0
#> 6                  NA               NULL                 NA                0|0
#> 7                  NA               NULL                 NA                1|1
#> 8                  NA               NULL                 NA                0|0
#> 9                  NA               NULL                 NA                0|0
#> 10                 NA               NULL                 NA                1|1
#> 11                 NA               NULL                 NA                1|1
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
#> 1                 NULL                 NA                0|0                 NA
#> 2                 NULL                 NA                1|1                 NA
#> 3                 NULL                 NA                0|0                 NA
#> 4                 NULL                 NA                0|0                 NA
#> 5                 NULL                 NA                0|0                 NA
#> 6                 NULL                 NA                0|0                 NA
#> 7                 NULL                 NA                1|1                 NA
#> 8                 NULL                 NA                0|0                 NA
#> 9  0.00, -0.90, -12.68                 NA                0|0                 NA
#> 10  0.00, -0.30, -3.86                 NA                0|0                 NA
#> 11                NULL                 NA                1|1                 NA
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
#> 1                  NA                0|0                 NA                ./.
#> 2                  NA                1|1                 NA                ./.
#> 3                  NA                0|0                 NA                ./.
#> 4                  NA                0|0                 NA                ./.
#> 5                  NA                0|0                 NA                ./.
#> 6                  NA                0|0                 NA                ./.
#> 7                  NA                1|1                 NA                ./.
#> 8                  NA                0|0                 NA                ./.
#> 9                  NA                0|1                 NA                ./.
#> 10                 NA                1|0                 NA                ./.
#> 11                 NA                1|1                 NA                ./.
```

### Query with DuckDB

using duckdb

``` r
# SQL queries on BCF (requires arrow and duckdb packages)
vcf_query(bcf_file, "SELECT CHROM, COUNT(*) as n FROM vcf GROUP BY CHROM")
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/AD should
#> be declared as Number=R per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GQ should
#> be declared as Type=Integer per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GT should
#> be declared as Number=1 per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/AD should
#> be declared as Number=R per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GQ should
#> be declared as Type=Integer per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GT should
#> be declared as Number=1 per VCF spec; correcting schema
#>   CHROM  n
#> 1     1 11

# Filter variants by position
vcf_query(bcf_file, "SELECT CHROM, POS, REF, ALT FROM vcf  LIMIT 5")
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/AD should
#> be declared as Number=R per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GQ should
#> be declared as Type=Integer per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GT should
#> be declared as Number=1 per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/AD should
#> be declared as Number=R per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GQ should
#> be declared as Type=Integer per VCF spec; correcting schema
#> Warning in arrow::RecordBatchReader$import_from_c(stream_out): FORMAT/GT should
#> be declared as Number=1 per VCF spec; correcting schema
#>   CHROM   POS REF ALT
#> 1     1 10583   G   A
#> 2     1 11508   A   G
#> 3     1 11565   G   T
#> 4     1 13116   T   G
#> 5     1 13327   G   C
```

## References

- [bcftools documentation](https://samtools.github.io/bcftools/)
- [bcftools GitHub](https://github.com/samtools/bcftools)
- [htslib GitHub](https://github.com/samtools/htslib)
- [arrow-nanoarrow](https://arrow.apache.org/nanoarrow/)
