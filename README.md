
<!-- README.md is generated from README.Rmd. Please edit that file -->

# RBCFTools

<!-- badges: start -->

[![R-CMD-check](https://github.com/RGenomicsETL/RBCFTools/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/RGenomicsETL/RBCFTools/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

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
integration with modern analytics tools like DuckDB, Polars, and
Parquet.

### Read VCF as Arrow Stream

``` r
# Open BCF as Arrow array stream
stream <- vcf_open_arrow(bcf_file, batch_size = 100L)

# Read first batch
batch <- stream$get_next()
b <- nanoarrow::convert_array(batch)
b[1:5,1:min(7, dim(b)[2])]
#>   CHROM   POS         ID REF ALT QUAL FILTER
#> 1     1 10583 rs58108140   G   A   NA   PASS
#> 2     1 11508       <NA>   A   G   NA   PASS
#> 3     1 11565       <NA>   G   T   NA   PASS
#> 4     1 13116       <NA>   T   G   NA   PASS
#> 5     1 13327       <NA>   G   C   NA   PASS
```

### Convert to Data Frame

``` r
# Convert entire BCF to data.frame
df <- vcf_to_arrow(bcf_file, as = "data.frame")
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

``` r
# Convert BCF to Parquet (requires arrow package)
vcf_to_parquet(bcf_file, parquet_file, compression = "gzip")
#> Wrote 11 rows to /tmp/Rtmp2hsJAm/file2b341a56a20ecd.parquet

# Read back with arrow
pq_bcf <- arrow::read_parquet(parquet_file)
pq_bcf[1:5,1:min(8,dim(pq_bcf)[2])]
#>   CHROM   POS         ID REF ALT QUAL FILTER INFO.DP INFO.AF INFO.CB
#> 1     1 10583 rs58108140   G   A   NA   PASS      NA    NULL    NULL
#> 2     1 11508       <NA>   A   G   NA   PASS      NA    NULL    NULL
#> 3     1 11565       <NA>   G   T   NA   PASS      NA    NULL    NULL
#> 4     1 13116       <NA>   T   G   NA   PASS      NA    NULL    NULL
#> 5     1 13327       <NA>   G   C   NA   PASS      NA    NULL    NULL
#>   INFO.EUR_R2 INFO.AFR_R2 INFO.ASN_R2
#> 1          NA          NA          NA
#> 2          NA          NA          NA
#> 3          NA          NA          NA
#> 4          NA          NA          NA
#> 5          NA          NA          NA
```

### Query with DuckDB

``` r
# SQL queries on BCF (requires arrow and duckdb packages)
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

## References

- [bcftools documentation](https://samtools.github.io/bcftools/)
- [bcftools GitHub](https://github.com/samtools/bcftools)
- [htslib GitHub](https://github.com/samtools/htslib)
- [VCF specification](https://samtools.github.io/hts-specs/VCFv4.3.pdf)
