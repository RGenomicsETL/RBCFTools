
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

## VCF to Arrow

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
str(nanoarrow::convert_array(batch))
#> 'data.frame':    11 obs. of  9 variables:
#>  $ CHROM  : chr  "1" "1" "1" "1" ...
#>  $ POS    : num  10583 11508 11565 13116 13327 ...
#>  $ ID     : chr  "rs58108140" NA NA NA ...
#>  $ REF    : chr  "G" "A" "G" "T" ...
#>  $ ALT    : list<chr> [1:11] 
#>   ..$ : chr "A"
#>   ..$ : chr "G"
#>   ..$ : chr "T"
#>   ..$ : chr "G"
#>   ..$ : chr "C"
#>   ..$ : chr "G"
#>   ..$ : chr "T"
#>   ..$ : chr "T"
#>   ..$ : chr "C"
#>   ..$ : chr "C"
#>   ..$ : chr "A"
#>   ..@ ptype: chr 
#>  $ QUAL   : num  NA NA NA NA NA NA NA NA NA NA ...
#>  $ FILTER : list<chr> [1:11] 
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..$ : chr "PASS"
#>   ..@ ptype: chr 
#>  $ INFO   :'data.frame': 11 obs. of  6 variables:
#>   ..$ DP    : int  NA NA NA NA NA NA NA NA NA NA ...
#>   ..$ AF    : list<dbl> [1:11] 
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..@ ptype: num 
#>   ..$ CB    : list<chr> [1:11] 
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..$ : NULL
#>   .. ..@ ptype: chr 
#>   ..$ EUR_R2: num  NA NA NA NA NA NA NA NA NA NA ...
#>   ..$ AFR_R2: num  NA NA NA NA NA NA NA NA NA NA ...
#>   ..$ ASN_R2: num  NA NA NA NA NA NA NA NA NA NA ...
#>  $ samples:'data.frame': 11 obs. of  629 variables:
#>   ..$ HG00098:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00100:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 3 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00106:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 2 NA NA NA 2 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00112:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00114:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 2 NA 1 1 1 3 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00116:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 3 NA 2 3 7 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 24.72 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00117:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  2 NA NA 7 20 4 1 2 20 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  8.01 2.22 1.48 29.83 60 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00118:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 NA NA NA 1 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00119:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA 7 1 1 2 7 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 1.48 9.17 36.78 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00120:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  5 NA NA 1 6 1 2 1 9 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  16.43 2.22 1.48 12.03 33.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00122:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 NA NA NA 2 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00123:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 4 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00124:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA 8 1 NA NA 6 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 1.48 9.17 39.59 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00126:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 2 NA NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 12.03 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00131:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA 1 2 4 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00141:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  3 NA NA NA 2 NA NA NA 3 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  10.66 2.22 1.48 9.17 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00142:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA 1 NA 1 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00143:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00144:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00145:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  4 NA NA NA NA NA NA NA 2 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  13.46 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00146:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA 5 NA NA 1 6 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.66 2.22 1.48 9.17 30.81 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00147:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA 1 NA NA NA 1 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.66 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00148:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA NA NA 1 NA 3 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00149:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA 3 NA NA NA 3 3 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 1.48 9.17 24.72 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00150:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 4 NA NA NA 2 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 12.03 27.83 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00151:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA 1 NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00152:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  2 NA NA 1 1 1 3 4 2 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  2.41 2.22 1.48 12.03 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00153:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00156:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA 1 1 NA NA NA 2 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 1.48 12.03 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00158:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA 3 3 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00159:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 2 2 1 NA NA 4 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 14.88 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00160:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00171:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA 1 NA 1 NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.66 2.22 1.48 9.65 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00173:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 2 NA 1 3 3 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00174:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 1 1 NA NA 6 3 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 12.03 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00176:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00177:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00178:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00179:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00180:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 5 NA 2 1 4 6 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 12.03 30.81 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00181:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00182:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00183:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA 1 4 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00185:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00186:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00187:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00188:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 1 1 NA 2 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00189:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA 2 NA NA 2 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.66 2.22 1.48 9.17 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00190:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA NA NA 1 1 3 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.66 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00231:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00239:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 2 NA NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00242:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00243:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 1 1 NA NA 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00244:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 2 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00245:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA 1 7 NA 1 1 9 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 1.48 12.03 36.78 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00247:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 NA NA NA 2 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00258:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  2 NA NA NA NA 2 1 4 8 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  2.41 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00262:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  3 NA NA NA 8 NA NA 5 7 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  23.3 2.22 1.48 9.17 39.59 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00264:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  4 NA NA NA NA NA NA 1 8 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  23.3 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00265:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA 1 NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00266:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 NA NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00267:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 NA NA NA 1 3 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00269:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 2 NA NA NA 2 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00270:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00272:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00306:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  3 NA NA NA NA 1 1 NA NA 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  30.04 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00308:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 2 7 1 1 1 2 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 14.88 36.78 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00311:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 4 4 1 2 3 3 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 27.83 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00312:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 11 NA 2 1 4 5 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 12.03 50 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00357:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA 5 NA NA 1 5 3 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 1.48 9.17 30.81 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00361:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 NA NA 3 NA 3 5 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 12.03 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00366:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 2 NA 1 NA 1 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 12.03 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00367:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 2 1 1 1 NA 2 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 14.88 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00368:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00369:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 2 NA NA NA 2 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00372:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 1 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00373:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA 2 NA NA NA 2 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.66 2.22 1.48 9.17 21.74 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00377:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 3 NA NA 1 2 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.28 2.22 1.48 12.03 24.83 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00380:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA NA NA 1 NA NA 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 1.48 9.17 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00403:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 1 NA NA NA 3 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.73 1.54 4.19 11.31 15.52 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00404:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 NA NA 1 NA 2 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.73 1.54 4.19 11.31 12.58 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00406:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 2 1 1 NA 2 NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  6.18 26.54 6.7 11.31 12.58 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00407:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  2 NA 2 NA 3 NA NA 1 2 3 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  8.62 1.54 9.21 8.47 21.43 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00445:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  3 1 4 2 2 NA NA NA 2 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  18.69 3.42 14.79 14.14 12.57 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00446:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  2 NA 2 NA 3 NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  8.62 1.54 9.21 8.47 14.71 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00452:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 2 2 2 3 NA NA 2 NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  6.18 25.67 24.5 14.14 13.78 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00457:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  2 NA 6 1 1 NA NA NA 1 5 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  8.62 1.54 20.77 11.31 14.24 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00553:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA 1 NA 1 2 3 2 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 2.56 12.03 15.8 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00554:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA NA 1 NA 1 NA NA 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  5.65 2.22 2.56 9.17 18.77 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00559:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 3 7 NA 1 NA 4 4 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.73 1.54 4.19 17.06 33.47 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00560:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA 2 2 NA NA NA 4 6 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  6.18 1.54 4.19 14.14 18.46 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00565:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  1 NA NA 2 4 1 NA NA 2 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  6.18 1.54 4.19 14.14 24.41 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00566:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 3 NA NA NA 4 4 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.73 1.54 4.19 8.47 21.43 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00577:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 1 3 1 NA NA 7 5 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.73 1.54 4.19 11.31 21.43 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00578:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  2 NA NA NA 1 1 1 NA 1 2 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  28.1 1.54 4.19 8.47 15.52 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00592:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA 3 3 NA NA NA 4 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.73 1.54 4.19 17.06 21.43 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00593:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 2 1 NA NA 3 1 ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.73 1.54 4.19 8.47 18.46 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00596:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA NA NA NA NA 2 NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.73 1.54 4.19 8.47 12.58 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   ..$ HG00610:'data.frame':  11 obs. of  7 variables:
#>   .. ..$ AD: list<int> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : int 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: int 
#>   .. ..$ DP: int  NA NA NA NA 1 NA NA NA NA NA ...
#>   .. ..$ GL: list<dbl> [1:11] 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : num 
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..$ : NULL
#>   .. .. ..@ ptype: num 
#>   .. ..$ GQ: num  3.73 1.54 4.19 8.47 15.52 ...
#>   .. ..$ GT: list<chr> [1:11] 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..$ : chr 
#>   .. .. ..@ ptype: chr 
#>   .. ..$ GD: num  NA NA NA NA NA NA NA NA NA NA ...
#>   .. ..$ OG: chr  "" "" "" "" ...
#>   .. [list output truncated]
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
#> Wrote 11 rows to /tmp/RtmpafQrog/file2aec5b7692fe8f.parquet

# Read back with arrow
arrow::read_parquet(parquet_file) |> head()
#>   CHROM   POS         ID REF ALT QUAL FILTER INFO.DP INFO.AF INFO.CB
#> 1     1 10583 rs58108140   G   A   NA   PASS      NA    NULL    NULL
#> 2     1 11508       <NA>   A   G   NA   PASS      NA    NULL    NULL
#> 3     1 11565       <NA>   G   T   NA   PASS      NA    NULL    NULL
#> 4     1 13116       <NA>   T   G   NA   PASS      NA    NULL    NULL
#> 5     1 13327       <NA>   G   C   NA   PASS      NA    NULL    NULL
#> 6     1 14699       <NA>   C   G   NA   PASS      NA    NULL    NULL
#>   INFO.EUR_R2 INFO.AFR_R2 INFO.ASN_R2 samples.HG00098.AD samples.HG00098.DP
#> 1          NA          NA          NA               NULL                 NA
#> 2          NA          NA          NA               NULL                 NA
#> 3          NA          NA          NA               NULL                 NA
#> 4          NA          NA          NA               NULL                 NA
#> 5          NA          NA          NA               NULL                 NA
#> 6          NA          NA          NA               NULL                 NA
#>   samples.HG00098.GL samples.HG00098.GQ samples.HG00098.GT samples.HG00098.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00098.OG samples.HG00100.AD samples.HG00100.DP samples.HG00100.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00100.GQ samples.HG00100.GT samples.HG00100.GD samples.HG00100.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00106.AD samples.HG00106.DP samples.HG00106.GL samples.HG00106.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     2                                 21.74
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00106.GT samples.HG00106.GD samples.HG00106.OG samples.HG00112.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00112.DP samples.HG00112.GL samples.HG00112.GQ samples.HG00112.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00112.GD samples.HG00112.OG samples.HG00114.AD samples.HG00114.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.HG00114.GL samples.HG00114.GQ samples.HG00114.GT samples.HG00114.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 21.74                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00114.OG samples.HG00116.AD samples.HG00116.DP samples.HG00116.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00116.GQ samples.HG00116.GT samples.HG00116.GD samples.HG00116.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              24.72                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00117.AD samples.HG00117.DP samples.HG00117.GL samples.HG00117.GQ
#> 1                                     2                                  8.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     7                                 29.83
#> 5                                    20                                 60.00
#> 6                                     4                                 17.57
#>   samples.HG00117.GT samples.HG00117.GD samples.HG00117.OG samples.HG00118.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00118.DP samples.HG00118.GL samples.HG00118.GQ samples.HG00118.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  1                                 18.77                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00118.GD samples.HG00118.OG samples.HG00119.AD samples.HG00119.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        7
#> 6                 NA                                                        1
#>   samples.HG00119.GL samples.HG00119.GQ samples.HG00119.GT samples.HG00119.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 36.78                                    NA
#> 6                                  9.00                                    NA
#>   samples.HG00119.OG samples.HG00120.AD samples.HG00120.DP samples.HG00120.GL
#> 1                                                        5                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        6                   
#> 6                                                        1                   
#>   samples.HG00120.GQ samples.HG00120.GT samples.HG00120.GD samples.HG00120.OG
#> 1              16.43                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              33.77                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.HG00122.AD samples.HG00122.DP samples.HG00122.GL samples.HG00122.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     1                                 18.77
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00122.GT samples.HG00122.GD samples.HG00122.OG samples.HG00123.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00123.DP samples.HG00123.GL samples.HG00123.GQ samples.HG00123.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00123.GD samples.HG00123.OG samples.HG00124.AD samples.HG00124.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        8
#> 6                 NA                                                        1
#>   samples.HG00124.GL samples.HG00124.GQ samples.HG00124.GT samples.HG00124.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 39.59                                    NA
#> 6                                  9.00                                    NA
#>   samples.HG00124.OG samples.HG00126.AD samples.HG00126.DP samples.HG00126.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00126.GQ samples.HG00126.GT samples.HG00126.GD samples.HG00126.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              21.74                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00131.AD samples.HG00131.DP samples.HG00131.GL samples.HG00131.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00131.GT samples.HG00131.GD samples.HG00131.OG samples.HG00141.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00141.DP samples.HG00141.GL samples.HG00141.GQ samples.HG00141.GT
#> 1                  3                                 10.66                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  2                                 21.74                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00141.GD samples.HG00141.OG samples.HG00142.AD samples.HG00142.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00142.GL samples.HG00142.GQ samples.HG00142.GT samples.HG00142.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00142.OG samples.HG00143.AD samples.HG00143.DP samples.HG00143.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00143.GQ samples.HG00143.GT samples.HG00143.GD samples.HG00143.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00144.AD samples.HG00144.DP samples.HG00144.GL samples.HG00144.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00144.GT samples.HG00144.GD samples.HG00144.OG samples.HG00145.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00145.DP samples.HG00145.GL samples.HG00145.GQ samples.HG00145.GT
#> 1                  4                                 13.46                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00145.GD samples.HG00145.OG samples.HG00146.AD samples.HG00146.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        5
#> 6                 NA                                  NULL                 NA
#>   samples.HG00146.GL samples.HG00146.GQ samples.HG00146.GT samples.HG00146.GD
#> 1                                  5.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 30.81                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00146.OG samples.HG00147.AD samples.HG00147.DP samples.HG00147.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00147.GQ samples.HG00147.GT samples.HG00147.GD samples.HG00147.OG
#> 1               5.66                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              18.77                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00148.AD samples.HG00148.DP samples.HG00148.GL samples.HG00148.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00148.GT samples.HG00148.GD samples.HG00148.OG samples.HG00149.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00149.DP samples.HG00149.GL samples.HG00149.GQ samples.HG00149.GT
#> 1                  1                                  5.65                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  3                                 24.72                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00149.GD samples.HG00149.OG samples.HG00150.AD samples.HG00150.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.HG00150.GL samples.HG00150.GQ samples.HG00150.GT samples.HG00150.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 12.03                                    NA
#> 5                                 27.83                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00150.OG samples.HG00151.AD samples.HG00151.DP samples.HG00151.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00151.GQ samples.HG00151.GT samples.HG00151.GD samples.HG00151.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00152.AD samples.HG00152.DP samples.HG00152.GL samples.HG00152.GQ
#> 1                                     2                                  2.41
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5                                     1                                 18.77
#> 6                                     1                                  9.09
#>   samples.HG00152.GT samples.HG00152.GD samples.HG00152.OG samples.HG00153.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00153.DP samples.HG00153.GL samples.HG00153.GQ samples.HG00153.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00153.GD samples.HG00153.OG samples.HG00156.AD samples.HG00156.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.HG00156.GL samples.HG00156.GQ samples.HG00156.GT samples.HG00156.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 12.03                                    NA
#> 5                                 18.77                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00156.OG samples.HG00158.AD samples.HG00158.DP samples.HG00158.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00158.GQ samples.HG00158.GT samples.HG00158.GD samples.HG00158.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00159.AD samples.HG00159.DP samples.HG00159.GL samples.HG00159.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     2                                 14.88
#> 5                                     2                                 21.74
#> 6                                     1                                  9.00
#>   samples.HG00159.GT samples.HG00159.GD samples.HG00159.OG samples.HG00160.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00160.DP samples.HG00160.GL samples.HG00160.GQ samples.HG00160.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00160.GD samples.HG00160.OG samples.HG00171.AD samples.HG00171.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        1
#>   samples.HG00171.GL samples.HG00171.GQ samples.HG00171.GT samples.HG00171.GD
#> 1                                  5.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                  9.65                                    NA
#> 5               NULL              15.80                                    NA
#> 6                                  9.00                                    NA
#>   samples.HG00171.OG samples.HG00173.AD samples.HG00173.DP samples.HG00173.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                                        2                   
#>   samples.HG00173.GQ samples.HG00173.GT samples.HG00173.GD samples.HG00173.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              18.77                                    NA                   
#> 6              11.80                                    NA                   
#>   samples.HG00174.AD samples.HG00174.DP samples.HG00174.GL samples.HG00174.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5                                     1                                 18.77
#> 6                                     1                                  9.00
#>   samples.HG00174.GT samples.HG00174.GD samples.HG00174.OG samples.HG00176.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00176.DP samples.HG00176.GL samples.HG00176.GQ samples.HG00176.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00176.GD samples.HG00176.OG samples.HG00177.AD samples.HG00177.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00177.GL samples.HG00177.GQ samples.HG00177.GT samples.HG00177.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00177.OG samples.HG00178.AD samples.HG00178.DP samples.HG00178.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00178.GQ samples.HG00178.GT samples.HG00178.GD samples.HG00178.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00179.AD samples.HG00179.DP samples.HG00179.GL samples.HG00179.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00179.GT samples.HG00179.GD samples.HG00179.OG samples.HG00180.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00180.DP samples.HG00180.GL samples.HG00180.GQ samples.HG00180.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  5                                 30.81                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00180.GD samples.HG00180.OG samples.HG00181.AD samples.HG00181.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00181.GL samples.HG00181.GQ samples.HG00181.GT samples.HG00181.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00181.OG samples.HG00182.AD samples.HG00182.DP samples.HG00182.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00182.GQ samples.HG00182.GT samples.HG00182.GD samples.HG00182.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00183.AD samples.HG00183.DP samples.HG00183.GL samples.HG00183.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00183.GT samples.HG00183.GD samples.HG00183.OG samples.HG00185.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00185.DP samples.HG00185.GL samples.HG00185.GQ samples.HG00185.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00185.GD samples.HG00185.OG samples.HG00186.AD samples.HG00186.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00186.GL samples.HG00186.GQ samples.HG00186.GT samples.HG00186.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00186.OG samples.HG00187.AD samples.HG00187.DP samples.HG00187.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00187.GQ samples.HG00187.GT samples.HG00187.GD samples.HG00187.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00188.AD samples.HG00188.DP samples.HG00188.GL samples.HG00188.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     1                                 18.77
#> 6                                     1                                  9.00
#>   samples.HG00188.GT samples.HG00188.GD samples.HG00188.OG samples.HG00189.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00189.DP samples.HG00189.GL samples.HG00189.GQ samples.HG00189.GT
#> 1                  1                                  5.66                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  2                                 21.74                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00189.GD samples.HG00189.OG samples.HG00190.AD samples.HG00190.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00190.GL samples.HG00190.GQ samples.HG00190.GT samples.HG00190.GD
#> 1                                  5.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00190.OG samples.HG00231.AD samples.HG00231.DP samples.HG00231.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00231.GQ samples.HG00231.GT samples.HG00231.GD samples.HG00231.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00239.AD samples.HG00239.DP samples.HG00239.GL samples.HG00239.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     2                                 21.74
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00239.GT samples.HG00239.GD samples.HG00239.OG samples.HG00242.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00242.DP samples.HG00242.GL samples.HG00242.GQ samples.HG00242.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  1                                 18.77                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00242.GD samples.HG00242.OG samples.HG00243.AD samples.HG00243.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                                        1
#>   samples.HG00243.GL samples.HG00243.GQ samples.HG00243.GT samples.HG00243.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 18.77                                    NA
#> 6                                  9.00                                    NA
#>   samples.HG00243.OG samples.HG00244.AD samples.HG00244.DP samples.HG00244.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00244.GQ samples.HG00244.GT samples.HG00244.GD samples.HG00244.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00245.AD samples.HG00245.DP samples.HG00245.GL samples.HG00245.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5                                     7                                 36.78
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00245.GT samples.HG00245.GD samples.HG00245.OG samples.HG00247.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00247.DP samples.HG00247.GL samples.HG00247.GQ samples.HG00247.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  1                                 18.77                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00247.GD samples.HG00247.OG samples.HG00258.AD samples.HG00258.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        2
#>   samples.HG00258.GL samples.HG00258.GQ samples.HG00258.GT samples.HG00258.GD
#> 1                                  2.41                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6                                 11.71                                    NA
#>   samples.HG00258.OG samples.HG00262.AD samples.HG00262.DP samples.HG00262.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        8                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00262.GQ samples.HG00262.GT samples.HG00262.GD samples.HG00262.OG
#> 1              23.30                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              39.59                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00264.AD samples.HG00264.DP samples.HG00264.GL samples.HG00264.GQ
#> 1                                     4                                 23.30
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00264.GT samples.HG00264.GD samples.HG00264.OG samples.HG00265.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                      
#>   samples.HG00265.DP samples.HG00265.GL samples.HG00265.GQ samples.HG00265.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                  1                                  9.00                   
#>   samples.HG00265.GD samples.HG00265.OG samples.HG00266.AD samples.HG00266.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.HG00266.GL samples.HG00266.GQ samples.HG00266.GT samples.HG00266.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 18.77                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00266.OG samples.HG00267.AD samples.HG00267.DP samples.HG00267.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00267.GQ samples.HG00267.GT samples.HG00267.GD samples.HG00267.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              18.77                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00269.AD samples.HG00269.DP samples.HG00269.GL samples.HG00269.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     2                                 21.74
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00269.GT samples.HG00269.GD samples.HG00269.OG samples.HG00270.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00270.DP samples.HG00270.GL samples.HG00270.GQ samples.HG00270.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00270.GD samples.HG00270.OG samples.HG00272.AD samples.HG00272.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00272.GL samples.HG00272.GQ samples.HG00272.GT samples.HG00272.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00272.OG samples.HG00306.AD samples.HG00306.DP samples.HG00306.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                                        1                   
#>   samples.HG00306.GQ samples.HG00306.GT samples.HG00306.GD samples.HG00306.OG
#> 1              30.04                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.HG00308.AD samples.HG00308.DP samples.HG00308.GL samples.HG00308.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     2                                 14.88
#> 5                                     7                                 36.78
#> 6                                     1                                  9.00
#>   samples.HG00308.GT samples.HG00308.GD samples.HG00308.OG samples.HG00311.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.HG00311.DP samples.HG00311.GL samples.HG00311.GQ samples.HG00311.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  4                                 27.83                   
#> 6                  4                                 25.42                   
#>   samples.HG00311.GD samples.HG00311.OG samples.HG00312.AD samples.HG00312.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                       11
#> 6                 NA                                  NULL                 NA
#>   samples.HG00312.GL samples.HG00312.GQ samples.HG00312.GT samples.HG00312.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 12.03                                    NA
#> 5                                 50.00                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00312.OG samples.HG00357.AD samples.HG00357.DP samples.HG00357.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        5                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00357.GQ samples.HG00357.GT samples.HG00357.GD samples.HG00357.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              30.81                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00361.AD samples.HG00361.DP samples.HG00361.GL samples.HG00361.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00361.GT samples.HG00361.GD samples.HG00361.OG samples.HG00366.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00366.DP samples.HG00366.GL samples.HG00366.GQ samples.HG00366.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  2                                 21.74                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00366.GD samples.HG00366.OG samples.HG00367.AD samples.HG00367.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        1
#> 6                 NA                                                        1
#>   samples.HG00367.GL samples.HG00367.GQ samples.HG00367.GT samples.HG00367.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 14.88                                    NA
#> 5                                 18.77                                    NA
#> 6                                  9.00                                    NA
#>   samples.HG00367.OG samples.HG00368.AD samples.HG00368.DP samples.HG00368.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00368.GQ samples.HG00368.GT samples.HG00368.GD samples.HG00368.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00369.AD samples.HG00369.DP samples.HG00369.GL samples.HG00369.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     2                                 21.74
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00369.GT samples.HG00369.GD samples.HG00369.OG samples.HG00372.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00372.DP samples.HG00372.GL samples.HG00372.GQ samples.HG00372.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.HG00372.GD samples.HG00372.OG samples.HG00373.AD samples.HG00373.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.HG00373.GL samples.HG00373.GQ samples.HG00373.GT samples.HG00373.GD
#> 1                                  5.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 21.74                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.HG00373.OG samples.HG00377.AD samples.HG00377.DP samples.HG00377.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00377.GQ samples.HG00377.GT samples.HG00377.GD samples.HG00377.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              24.83                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.HG00380.AD samples.HG00380.DP samples.HG00380.GL samples.HG00380.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.HG00380.GT samples.HG00380.GD samples.HG00380.OG samples.HG00403.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00403.DP samples.HG00403.GL samples.HG00403.GQ samples.HG00403.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  1                                 15.52                   
#> 6                 NA               NULL               6.49                   
#>   samples.HG00403.GD samples.HG00403.OG samples.HG00404.AD samples.HG00404.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00404.GL samples.HG00404.GQ samples.HG00404.GT samples.HG00404.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 11.31                                    NA
#> 5               NULL              12.58                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.HG00404.OG samples.HG00406.AD samples.HG00406.DP samples.HG00406.GL
#> 1                                                        1                   
#> 2                                                        2                   
#> 3                                                        1                   
#> 4                                                        1                   
#> 5                                  NULL                 NA               NULL
#> 6                                                        2                   
#>   samples.HG00406.GQ samples.HG00406.GT samples.HG00406.GD samples.HG00406.OG
#> 1               6.18                                    NA                   
#> 2              26.54                                    NA                   
#> 3               6.70                                    NA                   
#> 4              11.31                                    NA                   
#> 5              12.58                                    NA                   
#> 6               6.73                                    NA                   
#>   samples.HG00407.AD samples.HG00407.DP samples.HG00407.GL samples.HG00407.GQ
#> 1                                     2                                  8.62
#> 2               NULL                 NA               NULL               1.54
#> 3                                     2                                  9.21
#> 4               NULL                 NA               NULL               8.47
#> 5                                     3                                 21.43
#> 6               NULL                 NA               NULL               6.49
#>   samples.HG00407.GT samples.HG00407.GD samples.HG00407.OG samples.HG00445.AD
#> 1                                    NA                                      
#> 2                                    NA                                      
#> 3                                    NA                                      
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00445.DP samples.HG00445.GL samples.HG00445.GQ samples.HG00445.GT
#> 1                  3                                 18.69                   
#> 2                  1                                  3.42                   
#> 3                  4                                 14.79                   
#> 4                  2                                 14.14                   
#> 5                  2                                 12.57                   
#> 6                 NA               NULL               6.49                   
#>   samples.HG00445.GD samples.HG00445.OG samples.HG00446.AD samples.HG00446.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                                        2
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        3
#> 6                 NA                                  NULL                 NA
#>   samples.HG00446.GL samples.HG00446.GQ samples.HG00446.GT samples.HG00446.GD
#> 1                                  8.62                                    NA
#> 2               NULL               1.54                                    NA
#> 3                                  9.21                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 14.71                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.HG00446.OG samples.HG00452.AD samples.HG00452.DP samples.HG00452.GL
#> 1                                                        1                   
#> 2                                                        2                   
#> 3                                                        2                   
#> 4                                                        2                   
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00452.GQ samples.HG00452.GT samples.HG00452.GD samples.HG00452.OG
#> 1               6.18                                    NA                   
#> 2              25.67                                    NA                   
#> 3              24.50                                    NA                   
#> 4              14.14                                    NA                   
#> 5              13.78                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.HG00457.AD samples.HG00457.DP samples.HG00457.GL samples.HG00457.GQ
#> 1                                     2                                  8.62
#> 2               NULL                 NA               NULL               1.54
#> 3                                     6                                 20.77
#> 4                                     1                                 11.31
#> 5                                     1                                 14.24
#> 6               NULL                 NA               NULL               6.49
#>   samples.HG00457.GT samples.HG00457.GD samples.HG00457.OG samples.HG00553.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                  NULL
#> 6                                    NA                                      
#>   samples.HG00553.DP samples.HG00553.GL samples.HG00553.GQ samples.HG00553.GT
#> 1                  1                                  5.65                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 12.03                   
#> 5                 NA               NULL              15.80                   
#> 6                  1                                  8.14                   
#>   samples.HG00553.GD samples.HG00553.OG samples.HG00554.AD samples.HG00554.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.HG00554.GL samples.HG00554.GQ samples.HG00554.GT samples.HG00554.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 18.77                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.HG00554.OG samples.HG00559.AD samples.HG00559.DP samples.HG00559.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                        7                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00559.GQ samples.HG00559.GT samples.HG00559.GD samples.HG00559.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              17.06                                    NA                   
#> 5              33.47                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.HG00560.AD samples.HG00560.DP samples.HG00560.GL samples.HG00560.GQ
#> 1                                     1                                  6.18
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     2                                 14.14
#> 5                                     2                                 18.46
#> 6               NULL                 NA               NULL               6.49
#>   samples.HG00560.GT samples.HG00560.GD samples.HG00560.OG samples.HG00565.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.HG00565.DP samples.HG00565.GL samples.HG00565.GQ samples.HG00565.GT
#> 1                  1                                  6.18                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  2                                 14.14                   
#> 5                  4                                 24.41                   
#> 6                  1                                  9.22                   
#>   samples.HG00565.GD samples.HG00565.OG samples.HG00566.AD samples.HG00566.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        3
#> 6                 NA                                  NULL                 NA
#>   samples.HG00566.GL samples.HG00566.GQ samples.HG00566.GT samples.HG00566.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 21.43                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.HG00566.OG samples.HG00577.AD samples.HG00577.DP samples.HG00577.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        3                   
#> 6                                                        1                   
#>   samples.HG00577.GQ samples.HG00577.GT samples.HG00577.GD samples.HG00577.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              11.31                                    NA                   
#> 5              21.43                                    NA                   
#> 6               9.22                                    NA                   
#>   samples.HG00578.AD samples.HG00578.DP samples.HG00578.GL samples.HG00578.GQ
#> 1                                     2                                 28.10
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     1                                 15.52
#> 6                                     1                                  9.22
#>   samples.HG00578.GT samples.HG00578.GD samples.HG00578.OG samples.HG00592.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00592.DP samples.HG00592.GL samples.HG00592.GQ samples.HG00592.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  3                                 17.06                   
#> 5                  3                                 21.43                   
#> 6                 NA               NULL               6.49                   
#>   samples.HG00592.GD samples.HG00592.OG samples.HG00593.AD samples.HG00593.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                                        1
#>   samples.HG00593.GL samples.HG00593.GQ samples.HG00593.GT samples.HG00593.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 18.46                                    NA
#> 6                                  9.22                                    NA
#>   samples.HG00593.OG samples.HG00596.AD samples.HG00596.DP samples.HG00596.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.HG00596.GQ samples.HG00596.GT samples.HG00596.GD samples.HG00596.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.HG00610.AD samples.HG00610.DP samples.HG00610.GL samples.HG00610.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     1                                 15.52
#> 6               NULL                 NA               NULL               6.49
#>   samples.HG00610.GT samples.HG00610.GD samples.HG00610.OG samples.HG00611.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.HG00611.DP samples.HG00611.GL samples.HG00611.GQ samples.HG00611.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  2                                 18.46                   
#> 6                 NA               NULL               6.49                   
#>   samples.HG00611.GD samples.HG00611.OG samples.HG00625.AD samples.HG00625.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00625.GL samples.HG00625.GQ samples.HG00625.GT samples.HG00625.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5               NULL              12.58                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.HG00625.OG samples.HG00626.AD samples.HG00626.DP samples.HG00626.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.HG00626.GQ samples.HG00626.GT samples.HG00626.GD samples.HG00626.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              15.52                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.HG00628.AD samples.HG00628.DP samples.HG00628.GL samples.HG00628.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     1                                  9.98
#> 5               NULL                 NA               NULL              12.58
#> 6               NULL                 NA               NULL               6.49
#>   samples.HG00628.GT samples.HG00628.GD samples.HG00628.OG samples.HG00629.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.HG00629.DP samples.HG00629.GL samples.HG00629.GQ samples.HG00629.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                 NA               NULL              12.58                   
#> 6                 NA               NULL               6.49                   
#>   samples.HG00629.GD samples.HG00629.OG samples.HG00634.AD samples.HG00634.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00634.GL samples.HG00634.GQ samples.HG00634.GT samples.HG00634.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5               NULL              12.58                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.HG00634.OG samples.HG00635.AD samples.HG00635.DP samples.HG00635.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                                        1                   
#>   samples.HG00635.GQ samples.HG00635.GT samples.HG00635.GD samples.HG00635.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6               9.22                                    NA                   
#>   samples.HG00637.AD samples.HG00637.DP samples.HG00637.GL samples.HG00637.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               2.56
#> 4                                     2                                 14.88
#> 5                                     4                                 27.83
#> 6               NULL                 NA               NULL               5.49
#>   samples.HG00637.GT samples.HG00637.GD samples.HG00637.OG samples.HG00638.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.HG00638.DP samples.HG00638.GL samples.HG00638.GQ samples.HG00638.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL               9.17                   
#> 5                  2                                 21.74                   
#> 6                  1                                  8.14                   
#>   samples.HG00638.GD samples.HG00638.OG samples.HG00640.AD samples.HG00640.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.HG00640.GL samples.HG00640.GQ samples.HG00640.GT samples.HG00640.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                  9.65                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.HG00640.OG samples.NA06984.AD samples.NA06984.DP samples.NA06984.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA06984.GQ samples.NA06984.GT samples.NA06984.GD samples.NA06984.OG
#> 1               5.66                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA06985.AD samples.NA06985.DP samples.NA06985.GL samples.NA06985.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA06985.GT samples.NA06985.GD samples.NA06985.OG samples.NA06986.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA06986.DP samples.NA06986.GL samples.NA06986.GQ samples.NA06986.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                 10                                 45.23                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA06986.GD samples.NA06986.OG samples.NA06989.AD samples.NA06989.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                                        2
#>   samples.NA06989.GL samples.NA06989.GQ samples.NA06989.GT samples.NA06989.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 21.74                                    NA
#> 6                                 28.24                                    NA
#>   samples.NA06989.OG samples.NA06994.AD samples.NA06994.DP samples.NA06994.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA06994.GQ samples.NA06994.GT samples.NA06994.GD samples.NA06994.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              18.77                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA07000.AD samples.NA07000.DP samples.NA07000.GL samples.NA07000.GQ
#> 1                                     1                                  5.65
#> 2                                     1                                  4.34
#> 3                                     4                                 60.00
#> 4                                     1                                 12.03
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA07000.GT samples.NA07000.GD samples.NA07000.OG samples.NA07037.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA07037.DP samples.NA07037.GL samples.NA07037.GQ samples.NA07037.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                 13                                 60.00                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA07037.GD samples.NA07037.OG samples.NA07048.AD samples.NA07048.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA07048.GL samples.NA07048.GQ samples.NA07048.GT samples.NA07048.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA07048.OG samples.NA07051.AD samples.NA07051.DP samples.NA07051.GL
#> 1                                                        2                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA07051.GQ samples.NA07051.GT samples.NA07051.GD samples.NA07051.OG
#> 1               8.01                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              17.81                                    NA                   
#> 5              24.72                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA07056.AD samples.NA07056.DP samples.NA07056.GL samples.NA07056.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     4                                 20.87
#> 5                                     7                                 36.78
#> 6                                     5                                 20.43
#>   samples.NA07056.GT samples.NA07056.GD samples.NA07056.OG samples.NA07346.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA07346.DP samples.NA07346.GL samples.NA07346.GQ samples.NA07346.GT
#> 1                  1                                  5.65                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  5                                  7.53                   
#> 6                  1                                  9.09                   
#>   samples.NA07346.GD samples.NA07346.OG samples.NA07347.AD samples.NA07347.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        3
#> 6                 NA                                                        1
#>   samples.NA07347.GL samples.NA07347.GQ samples.NA07347.GT samples.NA07347.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 24.72                                    NA
#> 6                                  9.00                                    NA
#>   samples.NA07347.OG samples.NA07357.AD samples.NA07357.DP samples.NA07357.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA07357.GQ samples.NA07357.GT samples.NA07357.GD samples.NA07357.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              24.72                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA10847.AD samples.NA10847.DP samples.NA10847.GL samples.NA10847.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     3                                 24.83
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA10847.GT samples.NA10847.GD samples.NA10847.OG samples.NA10851.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA10851.DP samples.NA10851.GL samples.NA10851.GQ samples.NA10851.GT
#> 1                  4                                 13.56                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  4                                 27.83                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA10851.GD samples.NA10851.OG samples.NA11829.AD samples.NA11829.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA11829.GL samples.NA11829.GQ samples.NA11829.GT samples.NA11829.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 27.72                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA11829.OG samples.NA11830.AD samples.NA11830.DP samples.NA11830.GL
#> 1                                                        4                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        5                   
#> 6                                                        1                   
#>   samples.NA11830.GQ samples.NA11830.GT samples.NA11830.GD samples.NA11830.OG
#> 1              24.26                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              14.88                                    NA                   
#> 5              30.81                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.NA11831.AD samples.NA11831.DP samples.NA11831.GL samples.NA11831.GQ
#> 1                                     2                                  8.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5                                     6                                 33.67
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA11831.GT samples.NA11831.GD samples.NA11831.OG samples.NA11832.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA11832.DP samples.NA11832.GL samples.NA11832.GQ samples.NA11832.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  3                                 14.02                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA11832.GD samples.NA11832.OG samples.NA11840.AD samples.NA11840.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        1
#>   samples.NA11840.GL samples.NA11840.GQ samples.NA11840.GT samples.NA11840.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6                                  9.00                                    NA
#>   samples.NA11840.OG samples.NA11843.AD samples.NA11843.DP samples.NA11843.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        5                   
#> 6                                                        1                   
#>   samples.NA11843.GQ samples.NA11843.GT samples.NA11843.GD samples.NA11843.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              14.88                                    NA                   
#> 5              30.81                                    NA                   
#> 6               9.02                                    NA                   
#>   samples.NA11881.AD samples.NA11881.DP samples.NA11881.GL samples.NA11881.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA11881.GT samples.NA11881.GD samples.NA11881.OG samples.NA11892.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA11892.DP samples.NA11892.GL samples.NA11892.GQ samples.NA11892.GT
#> 1                  2                                  8.01                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                 11                                 50.00                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA11892.GD samples.NA11892.OG samples.NA11893.AD samples.NA11893.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        9
#> 6                 NA                                  NULL                 NA
#>   samples.NA11893.GL samples.NA11893.GQ samples.NA11893.GT samples.NA11893.GD
#> 1                                 10.75                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 12.03                                    NA
#> 5                                 43.01                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA11893.OG samples.NA11894.AD samples.NA11894.DP samples.NA11894.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        2                   
#> 6                                                        1                   
#>   samples.NA11894.GQ samples.NA11894.GT samples.NA11894.GD samples.NA11894.OG
#> 1              22.40                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              21.74                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.NA11918.AD samples.NA11918.DP samples.NA11918.GL samples.NA11918.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA11918.GT samples.NA11918.GD samples.NA11918.OG samples.NA11919.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA11919.DP samples.NA11919.GL samples.NA11919.GQ samples.NA11919.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  1                                 18.77                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA11919.GD samples.NA11919.OG samples.NA11920.AD samples.NA11920.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA11920.GL samples.NA11920.GQ samples.NA11920.GT samples.NA11920.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 21.74                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA11920.OG samples.NA11930.AD samples.NA11930.DP samples.NA11930.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA11930.GQ samples.NA11930.GT samples.NA11930.GD samples.NA11930.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              24.83                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA11931.AD samples.NA11931.DP samples.NA11931.GL samples.NA11931.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA11931.GT samples.NA11931.GD samples.NA11931.OG samples.NA11932.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA11932.DP samples.NA11932.GL samples.NA11932.GQ samples.NA11932.GT
#> 1                  2                                  8.01                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA11932.GD samples.NA11932.OG samples.NA11933.AD samples.NA11933.DP
#> 1                 NA                                                        4
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        8
#> 6                 NA                                  NULL                 NA
#>   samples.NA11933.GL samples.NA11933.GQ samples.NA11933.GT samples.NA11933.GD
#> 1                                 27.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                  5.69                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA11933.OG samples.NA11992.AD samples.NA11992.DP samples.NA11992.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA11992.GQ samples.NA11992.GT samples.NA11992.GD samples.NA11992.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              21.74                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA11993.AD samples.NA11993.DP samples.NA11993.GL samples.NA11993.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     1                                 18.77
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA11993.GT samples.NA11993.GD samples.NA11993.OG samples.NA11994.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA11994.DP samples.NA11994.GL samples.NA11994.GQ samples.NA11994.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  4                                 27.83                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA11994.GD samples.NA11994.OG samples.NA11995.AD samples.NA11995.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA11995.GL samples.NA11995.GQ samples.NA11995.GT samples.NA11995.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA11995.OG samples.NA12003.AD samples.NA12003.DP samples.NA12003.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA12003.GQ samples.NA12003.GT samples.NA12003.GD samples.NA12003.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              21.74                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12004.AD samples.NA12004.DP samples.NA12004.GL samples.NA12004.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA12004.GT samples.NA12004.GD samples.NA12004.OG samples.NA12005.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA12005.DP samples.NA12005.GL samples.NA12005.GQ samples.NA12005.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12005.GD samples.NA12005.OG samples.NA12006.AD samples.NA12006.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA12006.GL samples.NA12006.GQ samples.NA12006.GT samples.NA12006.GD
#> 1                                 28.39                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12006.OG samples.NA12043.AD samples.NA12043.DP samples.NA12043.GL
#> 1                                                        2                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA12043.GQ samples.NA12043.GT samples.NA12043.GD samples.NA12043.OG
#> 1               8.01                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              18.77                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12044.AD samples.NA12044.DP samples.NA12044.GL samples.NA12044.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA12044.GT samples.NA12044.GD samples.NA12044.OG samples.NA12045.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA12045.DP samples.NA12045.GL samples.NA12045.GQ samples.NA12045.GT
#> 1                  1                                  5.65                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  2                                 21.74                   
#> 6                  1                                  9.02                   
#>   samples.NA12045.GD samples.NA12045.OG samples.NA12046.AD samples.NA12046.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA12046.GL samples.NA12046.GQ samples.NA12046.GT samples.NA12046.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 27.72                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12046.OG samples.NA12058.AD samples.NA12058.DP samples.NA12058.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA12058.GQ samples.NA12058.GT samples.NA12058.GD samples.NA12058.OG
#> 1              31.94                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              18.77                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12144.AD samples.NA12144.DP samples.NA12144.GL samples.NA12144.GQ
#> 1                                     2                                  8.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     4                                 27.83
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA12144.GT samples.NA12144.GD samples.NA12144.OG samples.NA12154.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA12154.DP samples.NA12154.GL samples.NA12154.GQ samples.NA12154.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  2                                 14.88                   
#> 5                 12                                 50.00                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12154.GD samples.NA12154.OG samples.NA12155.AD samples.NA12155.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA12155.GL samples.NA12155.GQ samples.NA12155.GT samples.NA12155.GD
#> 1                                  8.01                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 18.77                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12155.OG samples.NA12156.AD samples.NA12156.DP samples.NA12156.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA12156.GQ samples.NA12156.GT samples.NA12156.GD samples.NA12156.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12249.AD samples.NA12249.DP samples.NA12249.GL samples.NA12249.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA12249.GT samples.NA12249.GD samples.NA12249.OG samples.NA12272.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA12272.DP samples.NA12272.GL samples.NA12272.GQ samples.NA12272.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12272.GD samples.NA12272.OG samples.NA12273.AD samples.NA12273.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA12273.GL samples.NA12273.GQ samples.NA12273.GT samples.NA12273.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12273.OG samples.NA12275.AD samples.NA12275.DP samples.NA12275.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA12275.GQ samples.NA12275.GT samples.NA12275.GD samples.NA12275.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12287.AD samples.NA12287.DP samples.NA12287.GL samples.NA12287.GQ
#> 1                                     3                                 27.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     3                                 24.72
#> 6                                     1                                  9.00
#>   samples.NA12287.GT samples.NA12287.GD samples.NA12287.OG samples.NA12340.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA12340.DP samples.NA12340.GL samples.NA12340.GQ samples.NA12340.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12340.GD samples.NA12340.OG samples.NA12341.AD samples.NA12341.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA12341.GL samples.NA12341.GQ samples.NA12341.GT samples.NA12341.GD
#> 1                                  8.01                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 18.77                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12341.OG samples.NA12342.AD samples.NA12342.DP samples.NA12342.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA12342.GQ samples.NA12342.GT samples.NA12342.GD samples.NA12342.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              18.77                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12347.AD samples.NA12347.DP samples.NA12347.GL samples.NA12347.GQ
#> 1                                     3                                 22.40
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     2                                 14.88
#> 5                                     9                                 43.01
#> 6                                     1                                  9.00
#>   samples.NA12347.GT samples.NA12347.GD samples.NA12347.OG samples.NA12348.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA12348.DP samples.NA12348.GL samples.NA12348.GQ samples.NA12348.GT
#> 1                  9                                 60.00                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  2                                 14.88                   
#> 5                 12                                 50.00                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12348.GD samples.NA12348.OG samples.NA12383.AD samples.NA12383.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        8
#> 6                 NA                                  NULL                 NA
#>   samples.NA12383.GL samples.NA12383.GQ samples.NA12383.GT samples.NA12383.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 14.88                                    NA
#> 5                                 39.59                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12383.OG samples.NA12399.AD samples.NA12399.DP samples.NA12399.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        1                   
#> 6                                                        1                   
#>   samples.NA12399.GQ samples.NA12399.GT samples.NA12399.GD samples.NA12399.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              18.77                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.NA12400.AD samples.NA12400.DP samples.NA12400.GL samples.NA12400.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5                                     7                                 36.78
#> 6                                     1                                  9.00
#>   samples.NA12400.GT samples.NA12400.GD samples.NA12400.OG samples.NA12413.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA12413.DP samples.NA12413.GL samples.NA12413.GQ samples.NA12413.GT
#> 1                  4                                 15.36                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  4                                 20.87                   
#> 5                 16                                 60.00                   
#> 6                  2                                 11.71                   
#>   samples.NA12413.GD samples.NA12413.OG samples.NA12414.AD samples.NA12414.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA12414.GL samples.NA12414.GQ samples.NA12414.GT samples.NA12414.GD
#> 1                                  5.64                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12414.OG samples.NA12489.AD samples.NA12489.DP samples.NA12489.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA12489.GQ samples.NA12489.GT samples.NA12489.GD samples.NA12489.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              21.74                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12546.AD samples.NA12546.DP samples.NA12546.GL samples.NA12546.GQ
#> 1                                     4                                 60.00
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     3                                 24.72
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA12546.GT samples.NA12546.GD samples.NA12546.OG samples.NA12716.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA12716.DP samples.NA12716.GL samples.NA12716.GQ samples.NA12716.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  2                                 14.88                   
#> 5                  2                                 21.74                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12716.GD samples.NA12716.OG samples.NA12717.AD samples.NA12717.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA12717.GL samples.NA12717.GQ samples.NA12717.GT samples.NA12717.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 18.77                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12717.OG samples.NA12718.AD samples.NA12718.DP samples.NA12718.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA12718.GQ samples.NA12718.GT samples.NA12718.GD samples.NA12718.OG
#> 1              31.94                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              24.72                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12749.AD samples.NA12749.DP samples.NA12749.GL samples.NA12749.GQ
#> 1                                     4                                 13.56
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     1                                 18.77
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA12749.GT samples.NA12749.GD samples.NA12749.OG samples.NA12750.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA12750.DP samples.NA12750.GL samples.NA12750.GQ samples.NA12750.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  3                                 24.72                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12750.GD samples.NA12750.OG samples.NA12751.AD samples.NA12751.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA12751.GL samples.NA12751.GQ samples.NA12751.GT samples.NA12751.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12751.OG samples.NA12761.AD samples.NA12761.DP samples.NA12761.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA12761.GQ samples.NA12761.GT samples.NA12761.GD samples.NA12761.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              21.74                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12762.AD samples.NA12762.DP samples.NA12762.GL samples.NA12762.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA12762.GT samples.NA12762.GD samples.NA12762.OG samples.NA12763.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA12763.DP samples.NA12763.GL samples.NA12763.GQ samples.NA12763.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  2                                 21.74                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12763.GD samples.NA12763.OG samples.NA12775.AD samples.NA12775.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                        1
#> 6                 NA                                                        1
#>   samples.NA12775.GL samples.NA12775.GQ samples.NA12775.GT samples.NA12775.GD
#> 1                                 24.20                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 17.91                                    NA
#> 5                                 18.77                                    NA
#> 6                                  9.02                                    NA
#>   samples.NA12775.OG samples.NA12776.AD samples.NA12776.DP samples.NA12776.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA12776.GQ samples.NA12776.GT samples.NA12776.GD samples.NA12776.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              21.74                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12777.AD samples.NA12777.DP samples.NA12777.GL samples.NA12777.GQ
#> 1                                     2                                  8.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5                                     9                                 43.01
#> 6                                     1                                  9.00
#>   samples.NA12777.GT samples.NA12777.GD samples.NA12777.OG samples.NA12778.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA12778.DP samples.NA12778.GL samples.NA12778.GQ samples.NA12778.GT
#> 1                  1                                  5.62                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  6                                 33.77                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12778.GD samples.NA12778.OG samples.NA12812.AD samples.NA12812.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA12812.GL samples.NA12812.GQ samples.NA12812.GT samples.NA12812.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12812.OG samples.NA12813.AD samples.NA12813.DP samples.NA12813.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA12813.GQ samples.NA12813.GT samples.NA12813.GD samples.NA12813.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12814.AD samples.NA12814.DP samples.NA12814.GL samples.NA12814.GQ
#> 1                                     2                                  8.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6                                     3                                 14.65
#>   samples.NA12814.GT samples.NA12814.GD samples.NA12814.OG samples.NA12815.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA12815.DP samples.NA12815.GL samples.NA12815.GQ samples.NA12815.GT
#> 1                  1                                  5.65                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12815.GD samples.NA12815.OG samples.NA12828.AD samples.NA12828.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA12828.GL samples.NA12828.GQ samples.NA12828.GT samples.NA12828.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA12828.OG samples.NA12830.AD samples.NA12830.DP samples.NA12830.GL
#> 1                                                       13                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        5                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA12830.GQ samples.NA12830.GT samples.NA12830.GD samples.NA12830.OG
#> 1              60.00                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              30.71                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12872.AD samples.NA12872.DP samples.NA12872.GL samples.NA12872.GQ
#> 1                                     1                                  5.66
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA12872.GT samples.NA12872.GD samples.NA12872.OG samples.NA12873.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA12873.DP samples.NA12873.GL samples.NA12873.GQ samples.NA12873.GT
#> 1                  2                                  8.01                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA12873.GD samples.NA12873.OG samples.NA12874.AD samples.NA12874.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        1
#>   samples.NA12874.GL samples.NA12874.GQ samples.NA12874.GT samples.NA12874.GD
#> 1                                 10.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6                                  9.00                                    NA
#>   samples.NA12874.OG samples.NA12889.AD samples.NA12889.DP samples.NA12889.GL
#> 1                                                        2                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA12889.GQ samples.NA12889.GT samples.NA12889.GD samples.NA12889.OG
#> 1               8.01                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA12890.AD samples.NA12890.DP samples.NA12890.GL samples.NA12890.GQ
#> 1                                     1                                  5.64
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     1                                 18.77
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA12890.GT samples.NA12890.GD samples.NA12890.OG samples.NA18486.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18486.DP samples.NA18486.GL samples.NA18486.GQ samples.NA18486.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                 11                                 60.00                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA18486.GD samples.NA18486.OG samples.NA18487.AD samples.NA18487.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                        2
#> 6                 NA                                                        4
#>   samples.NA18487.GL samples.NA18487.GQ samples.NA18487.GT samples.NA18487.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 20.30                                    NA
#> 5                                 27.42                                    NA
#> 6                                 16.61                                    NA
#>   samples.NA18487.OG samples.NA18489.AD samples.NA18489.DP samples.NA18489.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        7                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18489.GQ samples.NA18489.GT samples.NA18489.GD samples.NA18489.OG
#> 1              10.98                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              14.32                                    NA                   
#> 5              42.22                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA18498.AD samples.NA18498.DP samples.NA18498.GL samples.NA18498.GQ
#> 1                                     2                                 13.80
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     2                                 17.24
#> 5                                     6                                 39.59
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA18498.GT samples.NA18498.GD samples.NA18498.OG samples.NA18499.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18499.DP samples.NA18499.GL samples.NA18499.GQ samples.NA18499.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                 16                                 60.00                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA18499.GD samples.NA18499.OG samples.NA18501.AD samples.NA18501.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        7
#> 6                 NA                                  NULL                 NA
#>   samples.NA18501.GL samples.NA18501.GQ samples.NA18501.GT samples.NA18501.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 42.22                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA18501.OG samples.NA18502.AD samples.NA18502.DP samples.NA18502.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                       15                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18502.GQ samples.NA18502.GT samples.NA18502.GD samples.NA18502.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              60.00                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA18504.AD samples.NA18504.DP samples.NA18504.GL samples.NA18504.GQ
#> 1                                     1                                 10.98
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                     2                                 27.42
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA18504.GT samples.NA18504.GD samples.NA18504.OG samples.NA18505.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18505.DP samples.NA18505.GL samples.NA18505.GQ samples.NA18505.GT
#> 1                  2                                 13.80                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                  5                                 36.58                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA18505.GD samples.NA18505.OG samples.NA18507.AD samples.NA18507.DP
#> 1                 NA                                                        5
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA18507.GL samples.NA18507.GQ samples.NA18507.GT samples.NA18507.GD
#> 1                                 22.73                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                 27.42                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA18507.OG samples.NA18508.AD samples.NA18508.DP samples.NA18508.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                       16                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18508.GQ samples.NA18508.GT samples.NA18508.GD samples.NA18508.OG
#> 1              16.71                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              14.32                                    NA                   
#> 5              60.00                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA18510.AD samples.NA18510.DP samples.NA18510.GL samples.NA18510.GQ
#> 1                                     1                                 10.98
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     3                                 20.20
#> 5                                     6                                 39.59
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA18510.GT samples.NA18510.GD samples.NA18510.OG samples.NA18511.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18511.DP samples.NA18511.GL samples.NA18511.GQ samples.NA18511.GT
#> 1                  2                                 13.80                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                  6                                 39.59                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA18511.GD samples.NA18511.OG samples.NA18516.AD samples.NA18516.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        7
#> 6                 NA                                  NULL                 NA
#>   samples.NA18516.GL samples.NA18516.GQ samples.NA18516.GT samples.NA18516.GD
#> 1                                 10.77                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                  5.52                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA18516.OG samples.NA18517.AD samples.NA18517.DP samples.NA18517.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA18517.GQ samples.NA18517.GT samples.NA18517.GD samples.NA18517.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              21.44                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA18519.AD samples.NA18519.DP samples.NA18519.GL samples.NA18519.GQ
#> 1                                     2                                 13.71
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5               NULL                 NA               NULL              21.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA18519.GT samples.NA18519.GD samples.NA18519.OG samples.NA18520.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18520.DP samples.NA18520.GL samples.NA18520.GQ samples.NA18520.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  2                                 27.42                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA18520.GD samples.NA18520.OG samples.NA18522.AD samples.NA18522.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        8
#> 6                 NA                                  NULL                 NA
#>   samples.NA18522.GL samples.NA18522.GQ samples.NA18522.GT samples.NA18522.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 45.23                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA18522.OG samples.NA18523.AD samples.NA18523.DP samples.NA18523.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        9                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18523.GQ samples.NA18523.GT samples.NA18523.GD samples.NA18523.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              50.00                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA18525.AD samples.NA18525.DP samples.NA18525.GL samples.NA18525.GQ
#> 1                                     4                                 12.94
#> 2                                     2                                  5.31
#> 3                                     2                                 17.19
#> 4                                     4                                 20.11
#> 5               NULL                 NA               NULL              12.58
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18525.GT samples.NA18525.GD samples.NA18525.OG samples.NA18526.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18526.DP samples.NA18526.GL samples.NA18526.GQ samples.NA18526.GT
#> 1                  1                                  6.18                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  3                                 21.53                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18526.GD samples.NA18526.OG samples.NA18527.AD samples.NA18527.DP
#> 1                 NA                                                        2
#> 2                 NA                                                        3
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA18527.GL samples.NA18527.GQ samples.NA18527.GT samples.NA18527.GD
#> 1                                  8.62                                    NA
#> 2                                 16.41                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 17.06                                    NA
#> 5                                 14.90                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18527.OG samples.NA18532.AD samples.NA18532.DP samples.NA18532.GL
#> 1                                                        2                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        6                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18532.GQ samples.NA18532.GT samples.NA18532.GD samples.NA18532.OG
#> 1              26.64                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              30.41                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18535.AD samples.NA18535.DP samples.NA18535.GL samples.NA18535.GQ
#> 1                                     1                                  6.18
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     2                                 14.14
#> 5                                     5                                 27.50
#> 6                                     1                                  9.22
#>   samples.NA18535.GT samples.NA18535.GD samples.NA18535.OG samples.NA18537.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18537.DP samples.NA18537.GL samples.NA18537.GQ samples.NA18537.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  4                                 24.51                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18537.GD samples.NA18537.OG samples.NA18538.AD samples.NA18538.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA18538.GL samples.NA18538.GQ samples.NA18538.GT samples.NA18538.GD
#> 1                                  6.18                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 14.14                                    NA
#> 5                                 15.52                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18538.OG samples.NA18539.AD samples.NA18539.DP samples.NA18539.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA18539.GQ samples.NA18539.GT samples.NA18539.GD samples.NA18539.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18541.AD samples.NA18541.DP samples.NA18541.GL samples.NA18541.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     1                                 15.52
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18541.GT samples.NA18541.GD samples.NA18541.OG samples.NA18542.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18542.DP samples.NA18542.GL samples.NA18542.GQ samples.NA18542.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  4                                 24.41                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18542.GD samples.NA18542.OG samples.NA18545.AD samples.NA18545.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA18545.GL samples.NA18545.GQ samples.NA18545.GT samples.NA18545.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 18.46                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18545.OG samples.NA18547.AD samples.NA18547.DP samples.NA18547.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18547.GQ samples.NA18547.GT samples.NA18547.GD samples.NA18547.OG
#> 1               6.18                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              21.43                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18550.AD samples.NA18550.DP samples.NA18550.GL samples.NA18550.GQ
#> 1                                     1                                  6.18
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     9                                 39.21
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18550.GT samples.NA18550.GD samples.NA18550.OG samples.NA18552.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18552.DP samples.NA18552.GL samples.NA18552.GQ samples.NA18552.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  1                                 15.52                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18552.GD samples.NA18552.OG samples.NA18553.AD samples.NA18553.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                                        1
#>   samples.NA18553.GL samples.NA18553.GQ samples.NA18553.GT samples.NA18553.GD
#> 1                                  6.18                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 24.51                                    NA
#> 6                                  9.22                                    NA
#>   samples.NA18553.OG samples.NA18555.AD samples.NA18555.DP samples.NA18555.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                                        1                   
#>   samples.NA18555.GQ samples.NA18555.GT samples.NA18555.GD samples.NA18555.OG
#> 1               6.18                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6               9.31                                    NA                   
#>   samples.NA18558.AD samples.NA18558.DP samples.NA18558.GL samples.NA18558.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5               NULL                 NA               NULL              12.58
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18558.GT samples.NA18558.GD samples.NA18558.OG samples.NA18560.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA18560.DP samples.NA18560.GL samples.NA18560.GQ samples.NA18560.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  6                                 30.51                   
#> 6                  1                                  9.22                   
#>   samples.NA18560.GD samples.NA18560.OG samples.NA18561.AD samples.NA18561.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA18561.GL samples.NA18561.GQ samples.NA18561.GT samples.NA18561.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 24.41                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18561.OG samples.NA18562.AD samples.NA18562.DP samples.NA18562.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18562.GQ samples.NA18562.GT samples.NA18562.GD samples.NA18562.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              18.46                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18563.AD samples.NA18563.DP samples.NA18563.GL samples.NA18563.GQ
#> 1                                     3                                  3.59
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     4                                 24.51
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18563.GT samples.NA18563.GD samples.NA18563.OG samples.NA18564.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18564.DP samples.NA18564.GL samples.NA18564.GQ samples.NA18564.GT
#> 1                  1                                  6.18                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  2                                 14.14                   
#> 5                  3                                 21.53                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18564.GD samples.NA18564.OG samples.NA18565.AD samples.NA18565.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA18565.GL samples.NA18565.GQ samples.NA18565.GT samples.NA18565.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 18.46                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18565.OG samples.NA18566.AD samples.NA18566.DP samples.NA18566.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        3                   
#> 6                                                        1                   
#>   samples.NA18566.GQ samples.NA18566.GT samples.NA18566.GD samples.NA18566.OG
#> 1               6.18                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              21.53                                    NA                   
#> 6               9.22                                    NA                   
#>   samples.NA18567.AD samples.NA18567.DP samples.NA18567.GL samples.NA18567.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     1                                 11.31
#> 5                                     7                                 33.47
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18567.GT samples.NA18567.GD samples.NA18567.OG samples.NA18570.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18570.DP samples.NA18570.GL samples.NA18570.GQ samples.NA18570.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  7                                 33.47                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18570.GD samples.NA18570.OG samples.NA18571.AD samples.NA18571.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA18571.GL samples.NA18571.GQ samples.NA18571.GT samples.NA18571.GD
#> 1                                  6.18                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 24.51                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18571.OG samples.NA18572.AD samples.NA18572.DP samples.NA18572.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        9                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18572.GQ samples.NA18572.GT samples.NA18572.GD samples.NA18572.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              39.21                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18573.AD samples.NA18573.DP samples.NA18573.GL samples.NA18573.GQ
#> 1                                     2                                  8.62
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     7                                 33.47
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18573.GT samples.NA18573.GD samples.NA18573.OG samples.NA18574.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA18574.DP samples.NA18574.GL samples.NA18574.GQ samples.NA18574.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  9                                 39.21                   
#> 6                  1                                  9.22                   
#>   samples.NA18574.GD samples.NA18574.OG samples.NA18576.AD samples.NA18576.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA18576.GL samples.NA18576.GQ samples.NA18576.GT samples.NA18576.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 24.51                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18576.OG samples.NA18577.AD samples.NA18577.DP samples.NA18577.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                       13                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18577.GQ samples.NA18577.GT samples.NA18577.GD samples.NA18577.OG
#> 1               6.18                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              60.00                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18579.AD samples.NA18579.DP samples.NA18579.GL samples.NA18579.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     1                                 11.31
#> 5                                     3                                 21.43
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18579.GT samples.NA18579.GD samples.NA18579.OG samples.NA18582.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18582.DP samples.NA18582.GL samples.NA18582.GQ samples.NA18582.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  7                                 33.37                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18582.GD samples.NA18582.OG samples.NA18592.AD samples.NA18592.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA18592.GL samples.NA18592.GQ samples.NA18592.GT samples.NA18592.GD
#> 1                                  6.18                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 18.56                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18592.OG samples.NA18593.AD samples.NA18593.DP samples.NA18593.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        7                   
#> 6                                                        1                   
#>   samples.NA18593.GQ samples.NA18593.GT samples.NA18593.GD samples.NA18593.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              33.37                                    NA                   
#> 6               9.22                                    NA                   
#>   samples.NA18603.AD samples.NA18603.DP samples.NA18603.GL samples.NA18603.GQ
#> 1                                     1                                  6.18
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     2                                 18.46
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18603.GT samples.NA18603.GD samples.NA18603.OG samples.NA18605.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA18605.DP samples.NA18605.GL samples.NA18605.GQ samples.NA18605.GT
#> 1                  2                                 22.23                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                 NA               NULL              12.58                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18605.GD samples.NA18605.OG samples.NA18608.AD samples.NA18608.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA18608.GL samples.NA18608.GQ samples.NA18608.GT samples.NA18608.GD
#> 1                                  6.18                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 18.56                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18608.OG samples.NA18609.AD samples.NA18609.DP samples.NA18609.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        5                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18609.GQ samples.NA18609.GT samples.NA18609.GD samples.NA18609.OG
#> 1               6.18                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              27.50                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18611.AD samples.NA18611.DP samples.NA18611.GL samples.NA18611.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     1                                 11.31
#> 5                                     3                                 21.43
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18611.GT samples.NA18611.GD samples.NA18611.OG samples.NA18612.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18612.DP samples.NA18612.GL samples.NA18612.GQ samples.NA18612.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  2                                 18.46                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18612.GD samples.NA18612.OG samples.NA18614.AD samples.NA18614.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        3
#> 6                 NA                                                        1
#>   samples.NA18614.GL samples.NA18614.GQ samples.NA18614.GT samples.NA18614.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 14.24                                    NA
#> 5                                 21.43                                    NA
#> 6                                  9.22                                    NA
#>   samples.NA18614.OG samples.NA18615.AD samples.NA18615.DP samples.NA18615.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                        6                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18615.GQ samples.NA18615.GT samples.NA18615.GD samples.NA18615.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              17.06                                    NA                   
#> 5              30.51                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18616.AD samples.NA18616.DP samples.NA18616.GL samples.NA18616.GQ
#> 1                                     2                                  8.62
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     2                                 13.80
#> 5                                     3                                 21.43
#> 6                                     1                                  9.22
#>   samples.NA18616.GT samples.NA18616.GD samples.NA18616.OG samples.NA18617.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA18617.DP samples.NA18617.GL samples.NA18617.GQ samples.NA18617.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  5                                 27.50                   
#> 6                  4                                 17.73                   
#>   samples.NA18617.GD samples.NA18617.OG samples.NA18618.AD samples.NA18618.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        2
#>   samples.NA18618.GL samples.NA18618.GQ samples.NA18618.GT samples.NA18618.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5               NULL              12.58                                    NA
#> 6                                 11.95                                    NA
#>   samples.NA18618.OG samples.NA18619.AD samples.NA18619.DP samples.NA18619.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        8                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18619.GQ samples.NA18619.GT samples.NA18619.GD samples.NA18619.OG
#> 1               6.19                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              14.14                                    NA                   
#> 5              36.38                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18620.AD samples.NA18620.DP samples.NA18620.GL samples.NA18620.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     4                                 24.41
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18620.GT samples.NA18620.GD samples.NA18620.OG samples.NA18621.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18621.DP samples.NA18621.GL samples.NA18621.GQ samples.NA18621.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  1                                 15.52                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18621.GD samples.NA18621.OG samples.NA18622.AD samples.NA18622.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        3
#> 6                 NA                                  NULL                 NA
#>   samples.NA18622.GL samples.NA18622.GQ samples.NA18622.GT samples.NA18622.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 11.31                                    NA
#> 5                                 21.53                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18622.OG samples.NA18623.AD samples.NA18623.DP samples.NA18623.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                                        1                   
#>   samples.NA18623.GQ samples.NA18623.GT samples.NA18623.GD samples.NA18623.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6               9.22                                    NA                   
#>   samples.NA18624.AD samples.NA18624.DP samples.NA18624.GL samples.NA18624.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     1                                 11.31
#> 5                                     3                                 21.43
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18624.GT samples.NA18624.GD samples.NA18624.OG samples.NA18625.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18625.DP samples.NA18625.GL samples.NA18625.GQ samples.NA18625.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  1                                 15.52                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18625.GD samples.NA18625.OG samples.NA18626.AD samples.NA18626.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA18626.GL samples.NA18626.GQ samples.NA18626.GT samples.NA18626.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 14.14                                    NA
#> 5                                 24.51                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18626.OG samples.NA18627.AD samples.NA18627.DP samples.NA18627.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                        7                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18627.GQ samples.NA18627.GT samples.NA18627.GD samples.NA18627.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              17.16                                    NA                   
#> 5              33.47                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18628.AD samples.NA18628.DP samples.NA18628.GL samples.NA18628.GQ
#> 1                                     1                                  6.19
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     1                                 11.31
#> 5                                     9                                 39.21
#> 6                                     1                                  9.22
#>   samples.NA18628.GT samples.NA18628.GD samples.NA18628.OG samples.NA18630.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18630.DP samples.NA18630.GL samples.NA18630.GQ samples.NA18630.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  1                                 15.52                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18630.GD samples.NA18630.OG samples.NA18631.AD samples.NA18631.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA18631.GL samples.NA18631.GQ samples.NA18631.GT samples.NA18631.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 18.56                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18631.OG samples.NA18632.AD samples.NA18632.DP samples.NA18632.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        4                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18632.GQ samples.NA18632.GT samples.NA18632.GD samples.NA18632.OG
#> 1               6.18                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              24.51                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18633.AD samples.NA18633.DP samples.NA18633.GL samples.NA18633.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     1                                 15.52
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18633.GT samples.NA18633.GD samples.NA18633.OG samples.NA18634.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18634.DP samples.NA18634.GL samples.NA18634.GQ samples.NA18634.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  3                                 21.43                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18634.GD samples.NA18634.OG samples.NA18636.AD samples.NA18636.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA18636.GL samples.NA18636.GQ samples.NA18636.GT samples.NA18636.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 24.41                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18636.OG samples.NA18638.AD samples.NA18638.DP samples.NA18638.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18638.GQ samples.NA18638.GT samples.NA18638.GD samples.NA18638.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              15.52                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18640.AD samples.NA18640.DP samples.NA18640.GL samples.NA18640.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3                                     3                                 12.03
#> 4                                     3                                 17.16
#> 5               NULL                 NA               NULL              12.58
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18640.GT samples.NA18640.GD samples.NA18640.OG samples.NA18642.AD
#> 1                                    NA                                      
#> 2                                    NA                                      
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA18642.DP samples.NA18642.GL samples.NA18642.GQ samples.NA18642.GT
#> 1                  2                                  8.62                   
#> 2                  1                                  2.61                   
#> 3                 NA               NULL               4.19                   
#> 4                  2                                 14.14                   
#> 5                 NA               NULL              12.58                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18642.GD samples.NA18642.OG samples.NA18643.AD samples.NA18643.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                                        1
#> 3                 NA                                                        2
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA18643.GL samples.NA18643.GQ samples.NA18643.GT samples.NA18643.GD
#> 1               NULL               3.73                                    NA
#> 2                                  3.43                                    NA
#> 3                                  9.29                                    NA
#> 4               NULL               8.47                                    NA
#> 5               NULL              12.58                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18643.OG samples.NA18745.AD samples.NA18745.DP samples.NA18745.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18745.GQ samples.NA18745.GT samples.NA18745.GD samples.NA18745.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              15.52                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18853.AD samples.NA18853.DP samples.NA18853.GL samples.NA18853.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     2                                 17.24
#> 5                                     7                                 42.22
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA18853.GT samples.NA18853.GD samples.NA18853.OG samples.NA18856.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA18856.DP samples.NA18856.GL samples.NA18856.GQ samples.NA18856.GT
#> 1                  5                                  9.38                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                  7                                 42.22                   
#> 6                  1                                  8.14                   
#>   samples.NA18856.GD samples.NA18856.OG samples.NA18858.AD samples.NA18858.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        7
#> 6                 NA                                  NULL                 NA
#>   samples.NA18858.GL samples.NA18858.GQ samples.NA18858.GT samples.NA18858.GD
#> 1                                 16.71                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 42.22                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA18858.OG samples.NA18861.AD samples.NA18861.DP samples.NA18861.GL
#> 1                                                        4                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        6                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18861.GQ samples.NA18861.GT samples.NA18861.GD samples.NA18861.OG
#> 1              19.76                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              39.59                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA18867.AD samples.NA18867.DP samples.NA18867.GL samples.NA18867.GQ
#> 1                                     3                                 16.71
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     3                                 20.20
#> 5                                     5                                 36.58
#> 6                                     2                                 10.80
#>   samples.NA18867.GT samples.NA18867.GD samples.NA18867.OG samples.NA18868.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18868.DP samples.NA18868.GL samples.NA18868.GQ samples.NA18868.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  5                                 26.25                   
#> 5                 15                                 60.00                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA18868.GD samples.NA18868.OG samples.NA18870.AD samples.NA18870.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        7
#> 6                 NA                                  NULL                 NA
#>   samples.NA18870.GL samples.NA18870.GQ samples.NA18870.GT samples.NA18870.GD
#> 1                                 13.80                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 42.22                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA18870.OG samples.NA18871.AD samples.NA18871.DP samples.NA18871.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        6                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18871.GQ samples.NA18871.GT samples.NA18871.GD samples.NA18871.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              14.32                                    NA                   
#> 5              39.59                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA18873.AD samples.NA18873.DP samples.NA18873.GL samples.NA18873.GQ
#> 1                                     1                                 10.98
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                     8                                 45.23
#> 6                                     2                                 10.80
#>   samples.NA18873.GT samples.NA18873.GD samples.NA18873.OG samples.NA18874.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18874.DP samples.NA18874.GL samples.NA18874.GQ samples.NA18874.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  4                                 23.17                   
#> 5                 20                                 60.00                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA18874.GD samples.NA18874.OG samples.NA18907.AD samples.NA18907.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        9
#> 6                 NA                                  NULL                 NA
#>   samples.NA18907.GL samples.NA18907.GQ samples.NA18907.GT samples.NA18907.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                 50.00                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA18907.OG samples.NA18908.AD samples.NA18908.DP samples.NA18908.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                       23                   
#> 6                                                        2                   
#>   samples.NA18908.GQ samples.NA18908.GT samples.NA18908.GD samples.NA18908.OG
#> 1              16.71                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              20.20                                    NA                   
#> 5              60.00                                    NA                   
#> 6              10.80                                    NA                   
#>   samples.NA18909.AD samples.NA18909.DP samples.NA18909.GL samples.NA18909.GQ
#> 1                                     2                                 13.80
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5               NULL                 NA               NULL              21.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA18909.GT samples.NA18909.GD samples.NA18909.OG samples.NA18910.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18910.DP samples.NA18910.GL samples.NA18910.GQ samples.NA18910.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  5                                 36.58                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA18910.GD samples.NA18910.OG samples.NA18912.AD samples.NA18912.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA18912.GL samples.NA18912.GQ samples.NA18912.GT samples.NA18912.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 24.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA18912.OG samples.NA18916.AD samples.NA18916.DP samples.NA18916.GL
#> 1                                                        2                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18916.GQ samples.NA18916.GT samples.NA18916.GD samples.NA18916.OG
#> 1              13.80                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              27.42                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA18940.AD samples.NA18940.DP samples.NA18940.GL samples.NA18940.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     2                                 18.56
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18940.GT samples.NA18940.GD samples.NA18940.OG samples.NA18941.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18941.DP samples.NA18941.GL samples.NA18941.GQ samples.NA18941.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  1                                 15.52                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18941.GD samples.NA18941.OG samples.NA18942.AD samples.NA18942.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                        5
#> 6                 NA                                                        2
#>   samples.NA18942.GL samples.NA18942.GQ samples.NA18942.GT samples.NA18942.GD
#> 1                                  8.62                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 17.06                                    NA
#> 5                                 27.50                                    NA
#> 6                                 11.95                                    NA
#>   samples.NA18942.OG samples.NA18943.AD samples.NA18943.DP samples.NA18943.GL
#> 1                                                        6                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18943.GQ samples.NA18943.GT samples.NA18943.GD samples.NA18943.OG
#> 1              60.00                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              15.52                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18944.AD samples.NA18944.DP samples.NA18944.GL samples.NA18944.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     6                                 30.51
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18944.GT samples.NA18944.GD samples.NA18944.OG samples.NA18945.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18945.DP samples.NA18945.GL samples.NA18945.GQ samples.NA18945.GT
#> 1                  1                                  6.18                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                 10                                 42.22                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18945.GD samples.NA18945.OG samples.NA18947.AD samples.NA18947.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        6
#> 6                 NA                                  NULL                 NA
#>   samples.NA18947.GL samples.NA18947.GQ samples.NA18947.GT samples.NA18947.GD
#> 1                                 11.31                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 11.31                                    NA
#> 5                                 30.41                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18947.OG samples.NA18948.AD samples.NA18948.DP samples.NA18948.GL
#> 1                                                        8                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        9                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18948.GQ samples.NA18948.GT samples.NA18948.GD samples.NA18948.OG
#> 1              25.95                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              11.31                                    NA                   
#> 5              39.59                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18949.AD samples.NA18949.DP samples.NA18949.GL samples.NA18949.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     3                                 21.43
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18949.GT samples.NA18949.GD samples.NA18949.OG samples.NA18950.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA18950.DP samples.NA18950.GL samples.NA18950.GQ samples.NA18950.GT
#> 1                  1                                  6.18                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  2                                 14.14                   
#> 5                 11                                 45.23                   
#> 6                  1                                  9.22                   
#>   samples.NA18950.GD samples.NA18950.OG samples.NA18951.AD samples.NA18951.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                        3
#> 6                 NA                                  NULL                 NA
#>   samples.NA18951.GL samples.NA18951.GQ samples.NA18951.GT samples.NA18951.GD
#> 1                                  6.18                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 14.64                                    NA
#> 5                                 21.43                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18951.OG samples.NA18952.AD samples.NA18952.DP samples.NA18952.GL
#> 1                                                        7                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA18952.GQ samples.NA18952.GT samples.NA18952.GD samples.NA18952.OG
#> 1              23.11                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18953.AD samples.NA18953.DP samples.NA18953.GL samples.NA18953.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     5                                 27.40
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18953.GT samples.NA18953.GD samples.NA18953.OG samples.NA18955.AD
#> 1                                    NA                                      
#> 2                                    NA                                      
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA18955.DP samples.NA18955.GL samples.NA18955.GQ samples.NA18955.GT
#> 1                  1                                  6.18                   
#> 2                  1                                  3.42                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                 NA               NULL              12.58                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18955.GD samples.NA18955.OG samples.NA18956.AD samples.NA18956.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                       10
#> 6                 NA                                  NULL                 NA
#>   samples.NA18956.GL samples.NA18956.GQ samples.NA18956.GT samples.NA18956.GD
#> 1                                 23.71                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 14.14                                    NA
#> 5                                 42.22                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18956.OG samples.NA18959.AD samples.NA18959.DP samples.NA18959.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        4                   
#> 6                                                        1                   
#>   samples.NA18959.GQ samples.NA18959.GT samples.NA18959.GD samples.NA18959.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              24.51                                    NA                   
#> 6               9.22                                    NA                   
#>   samples.NA18960.AD samples.NA18960.DP samples.NA18960.GL samples.NA18960.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     1                                 15.52
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18960.GT samples.NA18960.GD samples.NA18960.OG samples.NA18961.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA18961.DP samples.NA18961.GL samples.NA18961.GQ samples.NA18961.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                 NA               NULL              12.58                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18961.GD samples.NA18961.OG samples.NA18963.AD samples.NA18963.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        4
#>   samples.NA18963.GL samples.NA18963.GQ samples.NA18963.GT samples.NA18963.GD
#> 1                                 21.48                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 11.31                                    NA
#> 5               NULL              12.58                                    NA
#> 6                                 23.18                                    NA
#>   samples.NA18963.OG samples.NA18964.AD samples.NA18964.DP samples.NA18964.GL
#> 1                                                        5                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                       14                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18964.GQ samples.NA18964.GT samples.NA18964.GD samples.NA18964.OG
#> 1              17.16                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              13.20                                    NA                   
#> 5              60.00                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18965.AD samples.NA18965.DP samples.NA18965.GL samples.NA18965.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     2                                 14.14
#> 5                                     9                                 39.21
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18965.GT samples.NA18965.GD samples.NA18965.OG samples.NA18967.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA18967.DP samples.NA18967.GL samples.NA18967.GQ samples.NA18967.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                 NA               NULL              12.58                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18967.GD samples.NA18967.OG samples.NA18968.AD samples.NA18968.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA18968.GL samples.NA18968.GQ samples.NA18968.GT samples.NA18968.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 15.52                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18968.OG samples.NA18970.AD samples.NA18970.DP samples.NA18970.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                                        2                   
#>   samples.NA18970.GQ samples.NA18970.GT samples.NA18970.GD samples.NA18970.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6              11.95                                    NA                   
#>   samples.NA18971.AD samples.NA18971.DP samples.NA18971.GL samples.NA18971.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     2                                 18.46
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18971.GT samples.NA18971.GD samples.NA18971.OG samples.NA18972.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA18972.DP samples.NA18972.GL samples.NA18972.GQ samples.NA18972.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                 NA               NULL              12.58                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18972.GD samples.NA18972.OG samples.NA18973.AD samples.NA18973.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        6
#> 6                 NA                                  NULL                 NA
#>   samples.NA18973.GL samples.NA18973.GQ samples.NA18973.GT samples.NA18973.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 11.31                                    NA
#> 5                                 30.51                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18973.OG samples.NA18974.AD samples.NA18974.DP samples.NA18974.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA18974.GQ samples.NA18974.GT samples.NA18974.GD samples.NA18974.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18975.AD samples.NA18975.DP samples.NA18975.GL samples.NA18975.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5               NULL                 NA               NULL              12.58
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA18975.GT samples.NA18975.GD samples.NA18975.OG samples.NA18976.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18976.DP samples.NA18976.GL samples.NA18976.GQ samples.NA18976.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  1                                 15.52                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18976.GD samples.NA18976.OG samples.NA18977.AD samples.NA18977.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        6
#> 5                 NA                                                       13
#> 6                 NA                                                        2
#>   samples.NA18977.GL samples.NA18977.GQ samples.NA18977.GT samples.NA18977.GD
#> 1                                  6.18                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 25.99                                    NA
#> 5                                 60.00                                    NA
#> 6                                 30.66                                    NA
#>   samples.NA18977.OG samples.NA18979.AD samples.NA18979.DP samples.NA18979.GL
#> 1                                  NULL                 NA               NULL
#> 2                                                        2                   
#> 3                                                        2                   
#> 4                                                        3                   
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18979.GQ samples.NA18979.GT samples.NA18979.GD samples.NA18979.OG
#> 1               3.73                                    NA                   
#> 2              25.23                                    NA                   
#> 3               9.21                                    NA                   
#> 4              17.06                                    NA                   
#> 5              13.72                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18980.AD samples.NA18980.DP samples.NA18980.GL samples.NA18980.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     8                                 36.38
#> 6                                     1                                  9.22
#>   samples.NA18980.GT samples.NA18980.GD samples.NA18980.OG samples.NA18981.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18981.DP samples.NA18981.GL samples.NA18981.GQ samples.NA18981.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  1                                 15.52                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18981.GD samples.NA18981.OG samples.NA18982.AD samples.NA18982.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                        7
#> 6                 NA                                                        2
#>   samples.NA18982.GL samples.NA18982.GQ samples.NA18982.GT samples.NA18982.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 17.06                                    NA
#> 5                                 33.47                                    NA
#> 6                                 11.95                                    NA
#>   samples.NA18982.OG samples.NA18983.AD samples.NA18983.DP samples.NA18983.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        9                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA18983.GQ samples.NA18983.GT samples.NA18983.GD samples.NA18983.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              11.31                                    NA                   
#> 5              39.59                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18984.AD samples.NA18984.DP samples.NA18984.GL samples.NA18984.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     3                                 17.16
#> 5                                    14                                 60.00
#> 6                                     1                                  9.22
#>   samples.NA18984.GT samples.NA18984.GD samples.NA18984.OG samples.NA18985.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA18985.DP samples.NA18985.GL samples.NA18985.GQ samples.NA18985.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  6                                 30.51                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA18985.GD samples.NA18985.OG samples.NA18986.AD samples.NA18986.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        7
#> 6                 NA                                  NULL                 NA
#>   samples.NA18986.GL samples.NA18986.GQ samples.NA18986.GT samples.NA18986.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 11.31                                    NA
#> 5                                 33.47                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA18986.OG samples.NA18987.AD samples.NA18987.DP samples.NA18987.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        5                   
#> 6                                                        2                   
#>   samples.NA18987.GQ samples.NA18987.GT samples.NA18987.GD samples.NA18987.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              11.31                                    NA                   
#> 5              27.50                                    NA                   
#> 6              11.95                                    NA                   
#>   samples.NA18988.AD samples.NA18988.DP samples.NA18988.GL samples.NA18988.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     1                                 11.31
#> 5                                    14                                 60.00
#> 6                                     1                                  9.22
#>   samples.NA18988.GT samples.NA18988.GD samples.NA18988.OG samples.NA18989.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA18989.DP samples.NA18989.GL samples.NA18989.GQ samples.NA18989.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                 11                                 45.23                   
#> 6                  1                                  9.22                   
#>   samples.NA18989.GD samples.NA18989.OG samples.NA18990.AD samples.NA18990.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        4
#> 6                 NA                                                        1
#>   samples.NA18990.GL samples.NA18990.GQ samples.NA18990.GT samples.NA18990.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 11.31                                    NA
#> 5                                 24.51                                    NA
#> 6                                  9.22                                    NA
#>   samples.NA18990.OG samples.NA18997.AD samples.NA18997.DP samples.NA18997.GL
#> 1                                                        1                   
#> 2                                                        1                   
#> 3                                                        2                   
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA18997.GQ samples.NA18997.GT samples.NA18997.GD samples.NA18997.OG
#> 1               6.17                                    NA                   
#> 2               3.43                                    NA                   
#> 3              23.33                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA18999.AD samples.NA18999.DP samples.NA18999.GL samples.NA18999.GQ
#> 1                                     1                                  6.12
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     1                                 10.88
#> 5                                     5                                 27.40
#> 6                                     2                                 11.95
#>   samples.NA18999.GT samples.NA18999.GD samples.NA18999.OG samples.NA19000.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19000.DP samples.NA19000.GL samples.NA19000.GQ samples.NA19000.GT
#> 1                  1                                  6.18                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  2                                 18.46                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA19000.GD samples.NA19000.OG samples.NA19001.AD samples.NA19001.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA19001.GL samples.NA19001.GQ samples.NA19001.GT samples.NA19001.GD
#> 1                                  6.18                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 14.24                                    NA
#> 5                                 14.24                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA19001.OG samples.NA19002.AD samples.NA19002.DP samples.NA19002.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        9                   
#> 6                                                        2                   
#>   samples.NA19002.GQ samples.NA19002.GT samples.NA19002.GD samples.NA19002.OG
#> 1               6.18                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              39.59                                    NA                   
#> 6              11.95                                    NA                   
#>   samples.NA19003.AD samples.NA19003.DP samples.NA19003.GL samples.NA19003.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5                                     1                                 15.52
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA19003.GT samples.NA19003.GD samples.NA19003.OG samples.NA19004.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19004.DP samples.NA19004.GL samples.NA19004.GQ samples.NA19004.GT
#> 1                  4                                 14.25                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  5                                 23.09                   
#> 5                 15                                 60.00                   
#> 6                  3                                 14.91                   
#>   samples.NA19004.GD samples.NA19004.OG samples.NA19005.AD samples.NA19005.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA19005.GL samples.NA19005.GQ samples.NA19005.GT samples.NA19005.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 15.52                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA19005.OG samples.NA19007.AD samples.NA19007.DP samples.NA19007.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19007.GQ samples.NA19007.GT samples.NA19007.GD samples.NA19007.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              14.13                                    NA                   
#> 5              18.46                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA19009.AD samples.NA19009.DP samples.NA19009.GL samples.NA19009.GQ
#> 1                                     2                                  2.12
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4               NULL                 NA               NULL               8.47
#> 5               NULL                 NA               NULL              12.58
#> 6                                     1                                  9.18
#>   samples.NA19009.GT samples.NA19009.GD samples.NA19009.OG samples.NA19010.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19010.DP samples.NA19010.GL samples.NA19010.GQ samples.NA19010.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  3                                 17.16                   
#> 5                 13                                 60.00                   
#> 6                  3                                 24.78                   
#>   samples.NA19010.GD samples.NA19010.OG samples.NA19012.AD samples.NA19012.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        1
#>   samples.NA19012.GL samples.NA19012.GQ samples.NA19012.GT samples.NA19012.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5               NULL              12.58                                    NA
#> 6                                  9.22                                    NA
#>   samples.NA19012.OG samples.NA19027.AD samples.NA19027.DP samples.NA19027.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                                        2                   
#> 4                                                        1                   
#> 5                                  NULL                 NA               NULL
#> 6                                                        1                   
#>   samples.NA19027.GQ samples.NA19027.GT samples.NA19027.GD samples.NA19027.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3              22.86                                    NA                   
#> 4              14.32                                    NA                   
#> 5              21.44                                    NA                   
#> 6               8.11                                    NA                   
#>   samples.NA19044.AD samples.NA19044.DP samples.NA19044.GL samples.NA19044.GQ
#> 1                                     1                                 10.98
#> 2               NULL                 NA               NULL               1.82
#> 3                                     4                                 23.86
#> 4                                     4                                 23.17
#> 5               NULL                 NA               NULL              21.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19044.GT samples.NA19044.GD samples.NA19044.OG samples.NA19054.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19054.DP samples.NA19054.GL samples.NA19054.GQ samples.NA19054.GT
#> 1                  2                                  8.62                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  2                                 18.46                   
#> 6                  1                                  9.22                   
#>   samples.NA19054.GD samples.NA19054.OG samples.NA19055.AD samples.NA19055.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        7
#> 6                 NA                                                        1
#>   samples.NA19055.GL samples.NA19055.GQ samples.NA19055.GT samples.NA19055.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                  2.33                                    NA
#> 6                                  9.22                                    NA
#>   samples.NA19055.OG samples.NA19056.AD samples.NA19056.DP samples.NA19056.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                                        1                   
#>   samples.NA19056.GQ samples.NA19056.GT samples.NA19056.GD samples.NA19056.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              18.46                                    NA                   
#> 6               9.22                                    NA                   
#>   samples.NA19057.AD samples.NA19057.DP samples.NA19057.GL samples.NA19057.GQ
#> 1                                     1                                  6.19
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     2                                 14.14
#> 5                                     8                                 36.38
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA19057.GT samples.NA19057.GD samples.NA19057.OG samples.NA19058.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19058.DP samples.NA19058.GL samples.NA19058.GQ samples.NA19058.GT
#> 1                  1                                  6.18                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                 NA               NULL               8.47                   
#> 5                  4                                 24.41                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA19058.GD samples.NA19058.OG samples.NA19059.AD samples.NA19059.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        4
#> 6                 NA                                                        3
#>   samples.NA19059.GL samples.NA19059.GQ samples.NA19059.GT samples.NA19059.GD
#> 1                                  2.12                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 14.14                                    NA
#> 5                                 24.41                                    NA
#> 6                                 14.81                                    NA
#>   samples.NA19059.OG samples.NA19060.AD samples.NA19060.DP samples.NA19060.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        9                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19060.GQ samples.NA19060.GT samples.NA19060.GD samples.NA19060.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              11.31                                    NA                   
#> 5              39.59                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA19062.AD samples.NA19062.DP samples.NA19062.GL samples.NA19062.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     2                                 14.14
#> 5                                     3                                 21.43
#> 6                                     1                                  9.22
#>   samples.NA19062.GT samples.NA19062.GD samples.NA19062.OG samples.NA19063.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19063.DP samples.NA19063.GL samples.NA19063.GQ samples.NA19063.GT
#> 1                  1                                  6.18                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  3                                 17.06                   
#> 5                  5                                 27.50                   
#> 6                  3                                 14.91                   
#>   samples.NA19063.GD samples.NA19063.OG samples.NA19064.AD samples.NA19064.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        3
#> 6                 NA                                  NULL                 NA
#>   samples.NA19064.GL samples.NA19064.GQ samples.NA19064.GT samples.NA19064.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 14.14                                    NA
#> 5                                 21.53                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA19064.OG samples.NA19065.AD samples.NA19065.DP samples.NA19065.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                                        1                   
#> 4                                  NULL                 NA               NULL
#> 5                                                        8                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19065.GQ samples.NA19065.GT samples.NA19065.GD samples.NA19065.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               6.70                                    NA                   
#> 4               8.47                                    NA                   
#> 5              36.38                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA19066.AD samples.NA19066.DP samples.NA19066.GL samples.NA19066.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     3                                 11.34
#> 5                                     7                                 33.37
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA19066.GT samples.NA19066.GD samples.NA19066.OG samples.NA19067.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19067.DP samples.NA19067.GL samples.NA19067.GQ samples.NA19067.GT
#> 1                  2                                  8.62                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  3                                 17.06                   
#> 5                 10                                 42.22                   
#> 6                  1                                  9.22                   
#>   samples.NA19067.GD samples.NA19067.OG samples.NA19068.AD samples.NA19068.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA19068.GL samples.NA19068.GQ samples.NA19068.GT samples.NA19068.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 18.46                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA19068.OG samples.NA19070.AD samples.NA19070.DP samples.NA19070.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                       10                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19070.GQ samples.NA19070.GT samples.NA19070.GD samples.NA19070.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              14.14                                    NA                   
#> 5              42.22                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA19072.AD samples.NA19072.DP samples.NA19072.GL samples.NA19072.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     7                                 21.61
#> 5                                     7                                 33.47
#> 6                                     2                                 11.95
#>   samples.NA19072.GT samples.NA19072.GD samples.NA19072.OG samples.NA19074.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19074.DP samples.NA19074.GL samples.NA19074.GQ samples.NA19074.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  2                                 14.14                   
#> 5                  6                                 30.51                   
#> 6                  2                                 11.95                   
#>   samples.NA19074.GD samples.NA19074.OG samples.NA19075.AD samples.NA19075.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        6
#> 6                 NA                                                        4
#>   samples.NA19075.GL samples.NA19075.GQ samples.NA19075.GT samples.NA19075.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 30.41                                    NA
#> 6                                 17.84                                    NA
#>   samples.NA19075.OG samples.NA19076.AD samples.NA19076.DP samples.NA19076.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19076.GQ samples.NA19076.GT samples.NA19076.GD samples.NA19076.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4              11.31                                    NA                   
#> 5              18.46                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA19077.AD samples.NA19077.DP samples.NA19077.GL samples.NA19077.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     5                                 23.09
#> 5                                     6                                 30.51
#> 6               NULL                 NA               NULL               6.49
#>   samples.NA19077.GT samples.NA19077.GD samples.NA19077.OG samples.NA19078.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19078.DP samples.NA19078.GL samples.NA19078.GQ samples.NA19078.GT
#> 1                  4                                 16.62                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  3                                 17.16                   
#> 5                  8                                 36.38                   
#> 6                  6                                 23.77                   
#>   samples.NA19078.GD samples.NA19078.OG samples.NA19079.AD samples.NA19079.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                       12
#> 6                 NA                                                        3
#>   samples.NA19079.GL samples.NA19079.GQ samples.NA19079.GT samples.NA19079.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4               NULL               8.47                                    NA
#> 5                                 50.00                                    NA
#> 6                                 14.81                                    NA
#>   samples.NA19079.OG samples.NA19082.AD samples.NA19082.DP samples.NA19082.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA19082.GQ samples.NA19082.GT samples.NA19082.GD samples.NA19082.OG
#> 1               3.73                                    NA                   
#> 2               1.54                                    NA                   
#> 3               4.19                                    NA                   
#> 4               8.47                                    NA                   
#> 5              12.58                                    NA                   
#> 6               6.49                                    NA                   
#>   samples.NA19083.AD samples.NA19083.DP samples.NA19083.GL samples.NA19083.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     3                                 17.06
#> 5                                    17                                 60.00
#> 6                                     4                                 14.86
#>   samples.NA19083.GT samples.NA19083.GD samples.NA19083.OG samples.NA19084.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19084.DP samples.NA19084.GL samples.NA19084.GQ samples.NA19084.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  3                                 17.06                   
#> 5                 15                                 60.00                   
#> 6                  2                                 12.05                   
#>   samples.NA19084.GD samples.NA19084.OG samples.NA19085.AD samples.NA19085.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA19085.GL samples.NA19085.GQ samples.NA19085.GT samples.NA19085.GD
#> 1               NULL               3.73                                    NA
#> 2               NULL               1.54                                    NA
#> 3               NULL               4.19                                    NA
#> 4                                 11.31                                    NA
#> 5                                 18.46                                    NA
#> 6               NULL               6.49                                    NA
#>   samples.NA19085.OG samples.NA19086.AD samples.NA19086.DP samples.NA19086.GL
#> 1                                                        1                   
#> 2                                                        1                   
#> 3                                                        1                   
#> 4                                                        4                   
#> 5                                  NULL                 NA               NULL
#> 6                                                        4                   
#>   samples.NA19086.GQ samples.NA19086.GT samples.NA19086.GD samples.NA19086.OG
#> 1               6.18                                    NA                   
#> 2               2.62                                    NA                   
#> 3               6.70                                    NA                   
#> 4              20.01                                    NA                   
#> 5              12.58                                    NA                   
#> 6              29.91                                    NA                   
#>   samples.NA19087.AD samples.NA19087.DP samples.NA19087.GL samples.NA19087.GQ
#> 1               NULL                 NA               NULL               3.73
#> 2               NULL                 NA               NULL               1.54
#> 3               NULL                 NA               NULL               4.19
#> 4                                     5                                  8.21
#> 5                                    15                                 21.03
#> 6                                     6                                 23.77
#>   samples.NA19087.GT samples.NA19087.GD samples.NA19087.OG samples.NA19088.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19088.DP samples.NA19088.GL samples.NA19088.GQ samples.NA19088.GT
#> 1                 NA               NULL               3.73                   
#> 2                 NA               NULL               1.54                   
#> 3                 NA               NULL               4.19                   
#> 4                  1                                 11.31                   
#> 5                  2                                 18.46                   
#> 6                 NA               NULL               6.49                   
#>   samples.NA19088.GD samples.NA19088.OG samples.NA19093.AD samples.NA19093.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                       13
#> 6                 NA                                  NULL                 NA
#>   samples.NA19093.GL samples.NA19093.GQ samples.NA19093.GT samples.NA19093.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                 60.00                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19093.OG samples.NA19098.AD samples.NA19098.DP samples.NA19098.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19098.GQ samples.NA19098.GT samples.NA19098.GD samples.NA19098.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              24.44                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19099.AD samples.NA19099.DP samples.NA19099.GL samples.NA19099.GQ
#> 1                                     1                                 10.98
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                    12                                 60.00
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19099.GT samples.NA19099.GD samples.NA19099.OG samples.NA19102.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19102.DP samples.NA19102.GL samples.NA19102.GQ samples.NA19102.GT
#> 1                  2                                 13.80                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  4                                 33.57                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19102.GD samples.NA19102.OG samples.NA19107.AD samples.NA19107.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                       14
#> 6                 NA                                                        1
#>   samples.NA19107.GL samples.NA19107.GQ samples.NA19107.GT samples.NA19107.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 17.24                                    NA
#> 5                                 60.00                                    NA
#> 6                                  8.16                                    NA
#>   samples.NA19107.OG samples.NA19108.AD samples.NA19108.DP samples.NA19108.GL
#> 1                                                        6                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                       11                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19108.GQ samples.NA19108.GT samples.NA19108.GD samples.NA19108.OG
#> 1               7.66                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              60.00                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19113.AD samples.NA19113.DP samples.NA19113.GL samples.NA19113.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2                                     1                                  2.32
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5               NULL                 NA               NULL              21.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19113.GT samples.NA19113.GD samples.NA19113.OG samples.NA19114.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19114.DP samples.NA19114.GL samples.NA19114.GQ samples.NA19114.GT
#> 1                  2                                 13.80                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  2                                 27.42                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19114.GD samples.NA19114.OG samples.NA19116.AD samples.NA19116.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                        5
#> 6                 NA                                                        1
#>   samples.NA19116.GL samples.NA19116.GQ samples.NA19116.GT samples.NA19116.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 20.20                                    NA
#> 5                                 36.58                                    NA
#> 6                                  8.14                                    NA
#>   samples.NA19116.OG samples.NA19119.AD samples.NA19119.DP samples.NA19119.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA19119.GQ samples.NA19119.GT samples.NA19119.GD samples.NA19119.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              21.44                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19129.AD samples.NA19129.DP samples.NA19129.GL samples.NA19129.GQ
#> 1                                     2                                 13.80
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                     9                                 50.00
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19129.GT samples.NA19129.GD samples.NA19129.OG samples.NA19130.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19130.DP samples.NA19130.GL samples.NA19130.GQ samples.NA19130.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                  2                                 27.42                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19130.GD samples.NA19130.OG samples.NA19131.AD samples.NA19131.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA19131.GL samples.NA19131.GQ samples.NA19131.GT samples.NA19131.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5               NULL              21.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19131.OG samples.NA19137.AD samples.NA19137.DP samples.NA19137.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA19137.GQ samples.NA19137.GT samples.NA19137.GD samples.NA19137.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              21.44                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19138.AD samples.NA19138.DP samples.NA19138.GL samples.NA19138.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5               NULL                 NA               NULL              21.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19138.GT samples.NA19138.GD samples.NA19138.OG samples.NA19141.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                      
#>   samples.NA19141.DP samples.NA19141.GL samples.NA19141.GQ samples.NA19141.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                 NA               NULL              21.44                   
#> 6                  1                                  8.14                   
#>   samples.NA19141.GD samples.NA19141.OG samples.NA19143.AD samples.NA19143.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA19143.GL samples.NA19143.GQ samples.NA19143.GT samples.NA19143.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5               NULL              21.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19143.OG samples.NA19144.AD samples.NA19144.DP samples.NA19144.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA19144.GQ samples.NA19144.GT samples.NA19144.GD samples.NA19144.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              21.44                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19147.AD samples.NA19147.DP samples.NA19147.GL samples.NA19147.GQ
#> 1                                     4                                 19.76
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                    11                                 60.00
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19147.GT samples.NA19147.GD samples.NA19147.OG samples.NA19152.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA19152.DP samples.NA19152.GL samples.NA19152.GQ samples.NA19152.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                 NA               NULL              21.44                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19152.GD samples.NA19152.OG samples.NA19153.AD samples.NA19153.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA19153.GL samples.NA19153.GQ samples.NA19153.GT samples.NA19153.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5               NULL              21.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19153.OG samples.NA19159.AD samples.NA19159.DP samples.NA19159.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19159.GQ samples.NA19159.GT samples.NA19159.GD samples.NA19159.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              27.42                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19160.AD samples.NA19160.DP samples.NA19160.GL samples.NA19160.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                     1                                 24.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19160.GT samples.NA19160.GD samples.NA19160.OG samples.NA19171.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19171.DP samples.NA19171.GL samples.NA19171.GQ samples.NA19171.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  1                                 24.44                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19171.GD samples.NA19171.OG samples.NA19172.AD samples.NA19172.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        5
#> 6                 NA                                  NULL                 NA
#>   samples.NA19172.GL samples.NA19172.GQ samples.NA19172.GT samples.NA19172.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                 36.58                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19172.OG samples.NA19184.AD samples.NA19184.DP samples.NA19184.GL
#> 1                                                        2                   
#> 2                                                        3                   
#> 3                                                        4                   
#> 4                                                        2                   
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA19184.GQ samples.NA19184.GT samples.NA19184.GD samples.NA19184.OG
#> 1              13.80                                    NA                   
#> 2              22.27                                    NA                   
#> 3              12.27                                    NA                   
#> 4              17.33                                    NA                   
#> 5              21.44                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19189.AD samples.NA19189.DP samples.NA19189.GL samples.NA19189.GQ
#> 1                                     2                                 13.80
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     4                                 23.17
#> 5                                     8                                  9.12
#> 6                                     1                                  8.14
#>   samples.NA19189.GT samples.NA19189.GD samples.NA19189.OG samples.NA19190.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19190.DP samples.NA19190.GL samples.NA19190.GQ samples.NA19190.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                 23                                 60.00                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19190.GD samples.NA19190.OG samples.NA19200.AD samples.NA19200.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA19200.GL samples.NA19200.GQ samples.NA19200.GT samples.NA19200.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 27.52                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19200.OG samples.NA19201.AD samples.NA19201.DP samples.NA19201.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA19201.GQ samples.NA19201.GT samples.NA19201.GD samples.NA19201.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              21.44                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19204.AD samples.NA19204.DP samples.NA19204.GL samples.NA19204.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5               NULL                 NA               NULL              21.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19204.GT samples.NA19204.GD samples.NA19204.OG samples.NA19206.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA19206.DP samples.NA19206.GL samples.NA19206.GQ samples.NA19206.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                 NA               NULL              21.44                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19206.GD samples.NA19206.OG samples.NA19207.AD samples.NA19207.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA19207.GL samples.NA19207.GQ samples.NA19207.GT samples.NA19207.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 24.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19207.OG samples.NA19209.AD samples.NA19209.DP samples.NA19209.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19209.GQ samples.NA19209.GT samples.NA19209.GD samples.NA19209.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              24.44                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19210.AD samples.NA19210.DP samples.NA19210.GL samples.NA19210.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     1                                 14.32
#> 5                                     1                                 24.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19210.GT samples.NA19210.GD samples.NA19210.OG samples.NA19213.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19213.DP samples.NA19213.GL samples.NA19213.GQ samples.NA19213.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  2                                 17.33                   
#> 5                  5                                 36.38                   
#> 6                  1                                  8.14                   
#>   samples.NA19213.GD samples.NA19213.OG samples.NA19225.AD samples.NA19225.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        3
#> 6                 NA                                  NULL                 NA
#>   samples.NA19225.GL samples.NA19225.GQ samples.NA19225.GT samples.NA19225.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                 30.51                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19225.OG samples.NA19235.AD samples.NA19235.DP samples.NA19235.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        5                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19235.GQ samples.NA19235.GT samples.NA19235.GD samples.NA19235.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              17.24                                    NA                   
#> 5              36.58                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19236.AD samples.NA19236.DP samples.NA19236.GL samples.NA19236.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                    11                                 60.00
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19236.GT samples.NA19236.GD samples.NA19236.OG samples.NA19247.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19247.DP samples.NA19247.GL samples.NA19247.GQ samples.NA19247.GT
#> 1                  3                                 16.71                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  2                                 17.24                   
#> 5                  2                                 27.42                   
#> 6                  1                                  8.14                   
#>   samples.NA19247.GD samples.NA19247.OG samples.NA19248.AD samples.NA19248.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        7
#> 6                 NA                                                        2
#>   samples.NA19248.GL samples.NA19248.GQ samples.NA19248.GT samples.NA19248.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 12.10                                    NA
#> 5                                 42.22                                    NA
#> 6                                 10.89                                    NA
#>   samples.NA19248.OG samples.NA19256.AD samples.NA19256.DP samples.NA19256.GL
#> 1                                                        4                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                        9                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19256.GQ samples.NA19256.GT samples.NA19256.GD samples.NA19256.OG
#> 1              19.66                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              20.20                                    NA                   
#> 5              50.00                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19257.AD samples.NA19257.DP samples.NA19257.GL samples.NA19257.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                     6                                 39.59
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19257.GT samples.NA19257.GD samples.NA19257.OG samples.NA19311.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19311.DP samples.NA19311.GL samples.NA19311.GQ samples.NA19311.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  2                                 17.24                   
#> 5                  6                                 39.59                   
#> 6                  3                                 13.61                   
#>   samples.NA19311.GD samples.NA19311.OG samples.NA19312.AD samples.NA19312.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA19312.GL samples.NA19312.GQ samples.NA19312.GT samples.NA19312.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 24.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19312.OG samples.NA19313.AD samples.NA19313.DP samples.NA19313.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                       12                   
#> 5                                                       20                   
#> 6                                                        3                   
#>   samples.NA19313.GQ samples.NA19313.GT samples.NA19313.GD samples.NA19313.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              20.69                                    NA                   
#> 5              60.00                                    NA                   
#> 6              13.61                                    NA                   
#>   samples.NA19314.AD samples.NA19314.DP samples.NA19314.GL samples.NA19314.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     4                                 23.17
#> 5                                     1                                 24.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19314.GT samples.NA19314.GD samples.NA19314.OG samples.NA19332.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19332.DP samples.NA19332.GL samples.NA19332.GQ samples.NA19332.GT
#> 1                  2                                 18.03                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  9                                 50.00                   
#> 6                  2                                 10.89                   
#>   samples.NA19332.GD samples.NA19332.OG samples.NA19334.AD samples.NA19334.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        3
#> 6                 NA                                  NULL                 NA
#>   samples.NA19334.GL samples.NA19334.GQ samples.NA19334.GT samples.NA19334.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 30.51                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19334.OG samples.NA19338.AD samples.NA19338.DP samples.NA19338.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA19338.GQ samples.NA19338.GT samples.NA19338.GD samples.NA19338.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              21.44                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19346.AD samples.NA19346.DP samples.NA19346.GL samples.NA19346.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                     2                                 27.52
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19346.GT samples.NA19346.GD samples.NA19346.OG samples.NA19347.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19347.DP samples.NA19347.GL samples.NA19347.GQ samples.NA19347.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                  7                                 42.22                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19347.GD samples.NA19347.OG samples.NA19350.AD samples.NA19350.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        5
#> 6                 NA                                  NULL                 NA
#>   samples.NA19350.GL samples.NA19350.GQ samples.NA19350.GT samples.NA19350.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 17.24                                    NA
#> 5                                 36.58                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19350.OG samples.NA19355.AD samples.NA19355.DP samples.NA19355.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        9                   
#> 5                                                       13                   
#> 6                                                        8                   
#>   samples.NA19355.GQ samples.NA19355.GT samples.NA19355.GD samples.NA19355.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              12.98                                    NA                   
#> 5              60.00                                    NA                   
#> 6              14.53                                    NA                   
#>   samples.NA19359.AD samples.NA19359.DP samples.NA19359.GL samples.NA19359.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     5                                 25.83
#> 5                                     2                                 27.42
#> 6                                    11                                  6.56
#>   samples.NA19359.GT samples.NA19359.GD samples.NA19359.OG samples.NA19360.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19360.DP samples.NA19360.GL samples.NA19360.GQ samples.NA19360.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  4                                 23.27                   
#> 5                  8                                 45.23                   
#> 6                  5                                 19.57                   
#>   samples.NA19360.GD samples.NA19360.OG samples.NA19371.AD samples.NA19371.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        9
#> 5                 NA                                                       14
#> 6                 NA                                                        8
#>   samples.NA19371.GL samples.NA19371.GQ samples.NA19371.GT samples.NA19371.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 11.94                                    NA
#> 5                                 60.00                                    NA
#> 6                                 14.53                                    NA
#>   samples.NA19371.OG samples.NA19372.AD samples.NA19372.DP samples.NA19372.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                                        2                   
#>   samples.NA19372.GQ samples.NA19372.GT samples.NA19372.GD samples.NA19372.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              21.44                                    NA                   
#> 6              10.80                                    NA                   
#>   samples.NA19375.AD samples.NA19375.DP samples.NA19375.GL samples.NA19375.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                    10                                 40.97
#> 5                                     7                                 42.22
#> 6                                     5                                 60.00
#>   samples.NA19375.GT samples.NA19375.GD samples.NA19375.OG samples.NA19376.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19376.DP samples.NA19376.GL samples.NA19376.GQ samples.NA19376.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  6                                  5.21                   
#> 5                 12                                 60.00                   
#> 6                  3                                 13.61                   
#>   samples.NA19376.GD samples.NA19376.OG samples.NA19377.AD samples.NA19377.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                        5
#> 6                 NA                                                        7
#>   samples.NA19377.GL samples.NA19377.GQ samples.NA19377.GT samples.NA19377.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 20.20                                    NA
#> 5                                 36.58                                    NA
#> 6                                 25.42                                    NA
#>   samples.NA19377.OG samples.NA19379.AD samples.NA19379.DP samples.NA19379.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                        9                   
#> 6                                                        4                   
#>   samples.NA19379.GQ samples.NA19379.GT samples.NA19379.GD samples.NA19379.OG
#> 1              10.98                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              20.20                                    NA                   
#> 5              50.00                                    NA                   
#> 6              16.52                                    NA                   
#>   samples.NA19381.AD samples.NA19381.DP samples.NA19381.GL samples.NA19381.GQ
#> 1                                     1                                 10.98
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     2                                 17.24
#> 5                                     1                                 24.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19381.GT samples.NA19381.GD samples.NA19381.OG samples.NA19382.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19382.DP samples.NA19382.GL samples.NA19382.GQ samples.NA19382.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  3                                 10.74                   
#> 5                  5                                 36.58                   
#> 6                  5                                 19.46                   
#>   samples.NA19382.GD samples.NA19382.OG samples.NA19383.AD samples.NA19383.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        8
#> 5                 NA                                                        9
#> 6                 NA                                                        9
#>   samples.NA19383.GL samples.NA19383.GQ samples.NA19383.GT samples.NA19383.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 35.09                                    NA
#> 5                                 50.00                                    NA
#> 6                                 11.68                                    NA
#>   samples.NA19383.OG samples.NA19384.AD samples.NA19384.DP samples.NA19384.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        3                   
#> 6                                                        1                   
#>   samples.NA19384.GQ samples.NA19384.GT samples.NA19384.GD samples.NA19384.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              17.24                                    NA                   
#> 5              30.41                                    NA                   
#> 6               8.16                                    NA                   
#>   samples.NA19385.AD samples.NA19385.DP samples.NA19385.GL samples.NA19385.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     5                                 26.25
#> 5                                     6                                 39.59
#> 6                                     6                                 20.55
#>   samples.NA19385.GT samples.NA19385.GD samples.NA19385.OG samples.NA19390.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19390.DP samples.NA19390.GL samples.NA19390.GQ samples.NA19390.GT
#> 1                  2                                 13.80                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  4                                 23.27                   
#> 5                 10                                 50.00                   
#> 6                 11                                 37.45                   
#>   samples.NA19390.GD samples.NA19390.OG samples.NA19391.AD samples.NA19391.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        2
#> 6                 NA                                                        2
#>   samples.NA19391.GL samples.NA19391.GQ samples.NA19391.GT samples.NA19391.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                 27.42                                    NA
#> 6                                 27.50                                    NA
#>   samples.NA19391.OG samples.NA19393.AD samples.NA19393.DP samples.NA19393.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        4                   
#> 5                                                        3                   
#> 6                                                        4                   
#>   samples.NA19393.GQ samples.NA19393.GT samples.NA19393.GD samples.NA19393.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              23.17                                    NA                   
#> 5              30.41                                    NA                   
#> 6              36.78                                    NA                   
#>   samples.NA19394.AD samples.NA19394.DP samples.NA19394.GL samples.NA19394.GQ
#> 1                                     1                                 10.98
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     1                                 14.32
#> 5                                     1                                 24.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19394.GT samples.NA19394.GD samples.NA19394.OG samples.NA19395.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19395.DP samples.NA19395.GL samples.NA19395.GQ samples.NA19395.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                  3                                 30.51                   
#> 6                  2                                 10.80                   
#>   samples.NA19395.GD samples.NA19395.OG samples.NA19397.AD samples.NA19397.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        8
#> 5                 NA                                                        8
#> 6                 NA                                                        6
#>   samples.NA19397.GL samples.NA19397.GQ samples.NA19397.GT samples.NA19397.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 11.01                                    NA
#> 5                                 45.23                                    NA
#> 6                                 22.53                                    NA
#>   samples.NA19397.OG samples.NA19398.AD samples.NA19398.DP samples.NA19398.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                       10                   
#> 5                                                       15                   
#> 6                                                       10                   
#>   samples.NA19398.GQ samples.NA19398.GT samples.NA19398.GD samples.NA19398.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              40.97                                    NA                   
#> 5              60.00                                    NA                   
#> 6              34.44                                    NA                   
#>   samples.NA19399.AD samples.NA19399.DP samples.NA19399.GL samples.NA19399.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     3                                 20.20
#> 5                                     5                                 36.58
#> 6                                     2                                 10.80
#>   samples.NA19399.GT samples.NA19399.GD samples.NA19399.OG samples.NA19401.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19401.DP samples.NA19401.GL samples.NA19401.GQ samples.NA19401.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  2                                 17.24                   
#> 5                  9                                 50.00                   
#> 6                  7                                 25.42                   
#>   samples.NA19401.GD samples.NA19401.OG samples.NA19404.AD samples.NA19404.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        1
#>   samples.NA19404.GL samples.NA19404.GQ samples.NA19404.GT samples.NA19404.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5               NULL              21.44                                    NA
#> 6                                  8.16                                    NA
#>   samples.NA19404.OG samples.NA19428.AD samples.NA19428.DP samples.NA19428.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        7                   
#> 6                                                        6                   
#>   samples.NA19428.GQ samples.NA19428.GT samples.NA19428.GD samples.NA19428.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              17.24                                    NA                   
#> 5              42.22                                    NA                   
#> 6              22.44                                    NA                   
#>   samples.NA19429.AD samples.NA19429.DP samples.NA19429.GL samples.NA19429.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     5                                 26.16
#> 5                                    16                                 60.00
#> 6                                     4                                 16.52
#>   samples.NA19429.GT samples.NA19429.GD samples.NA19429.OG samples.NA19434.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA19434.DP samples.NA19434.GL samples.NA19434.GQ samples.NA19434.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                 NA               NULL              21.44                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19434.GD samples.NA19434.OG samples.NA19435.AD samples.NA19435.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        3
#> 6                 NA                                                        1
#>   samples.NA19435.GL samples.NA19435.GQ samples.NA19435.GT samples.NA19435.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                 30.41                                    NA
#> 6                                  8.14                                    NA
#>   samples.NA19435.OG samples.NA19436.AD samples.NA19436.DP samples.NA19436.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19436.GQ samples.NA19436.GT samples.NA19436.GD samples.NA19436.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              17.24                                    NA                   
#> 5              27.42                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19437.AD samples.NA19437.DP samples.NA19437.GL samples.NA19437.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                     1                                 24.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19437.GT samples.NA19437.GD samples.NA19437.OG samples.NA19438.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19438.DP samples.NA19438.GL samples.NA19438.GQ samples.NA19438.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  1                                 24.44                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19438.GD samples.NA19438.OG samples.NA19439.AD samples.NA19439.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        9
#> 6                 NA                                  NULL                 NA
#>   samples.NA19439.GL samples.NA19439.GQ samples.NA19439.GT samples.NA19439.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 17.24                                    NA
#> 5                                 50.00                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19439.OG samples.NA19440.AD samples.NA19440.DP samples.NA19440.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                       21                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19440.GQ samples.NA19440.GT samples.NA19440.GD samples.NA19440.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              20.30                                    NA                   
#> 5              60.00                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19443.AD samples.NA19443.DP samples.NA19443.GL samples.NA19443.GQ
#> 1                                     2                                 13.80
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                    11                                 43.98
#> 5                                    37                                 60.00
#> 6                                    13                                 27.12
#>   samples.NA19443.GT samples.NA19443.GD samples.NA19443.OG samples.NA19444.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19444.DP samples.NA19444.GL samples.NA19444.GQ samples.NA19444.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                  1                                 24.44                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19444.GD samples.NA19444.OG samples.NA19445.AD samples.NA19445.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        8
#> 5                 NA                                                       24
#> 6                 NA                                                        3
#>   samples.NA19445.GL samples.NA19445.GQ samples.NA19445.GT samples.NA19445.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                  7.42                                    NA
#> 5                                 60.00                                    NA
#> 6                                 13.61                                    NA
#>   samples.NA19445.OG samples.NA19446.AD samples.NA19446.DP samples.NA19446.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        9                   
#> 6                                                        1                   
#>   samples.NA19446.GQ samples.NA19446.GT samples.NA19446.GD samples.NA19446.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              17.24                                    NA                   
#> 5              50.00                                    NA                   
#> 6               8.14                                    NA                   
#>   samples.NA19448.AD samples.NA19448.DP samples.NA19448.GL samples.NA19448.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     2                                 17.24
#> 5                                     7                                 42.22
#> 6                                     4                                 16.52
#>   samples.NA19448.GT samples.NA19448.GD samples.NA19448.OG samples.NA19449.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19449.DP samples.NA19449.GL samples.NA19449.GQ samples.NA19449.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                  3                                 30.51                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19449.GD samples.NA19449.OG samples.NA19451.AD samples.NA19451.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                       11
#> 6                 NA                                                        2
#>   samples.NA19451.GL samples.NA19451.GQ samples.NA19451.GT samples.NA19451.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                 60.00                                    NA
#> 6                                  5.78                                    NA
#>   samples.NA19451.OG samples.NA19452.AD samples.NA19452.DP samples.NA19452.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        4                   
#> 5                                                       18                   
#> 6                                                        1                   
#>   samples.NA19452.GQ samples.NA19452.GT samples.NA19452.GD samples.NA19452.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              23.27                                    NA                   
#> 5              60.00                                    NA                   
#> 6               8.23                                    NA                   
#>   samples.NA19453.AD samples.NA19453.DP samples.NA19453.GL samples.NA19453.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5               NULL                 NA               NULL              21.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19453.GT samples.NA19453.GD samples.NA19453.OG samples.NA19455.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19455.DP samples.NA19455.GL samples.NA19455.GQ samples.NA19455.GT
#> 1                  4                                 19.76                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  8                                 35.23                   
#> 5                  8                                 45.23                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19455.GD samples.NA19455.OG samples.NA19456.AD samples.NA19456.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        1
#>   samples.NA19456.GL samples.NA19456.GQ samples.NA19456.GT samples.NA19456.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5               NULL              21.44                                    NA
#> 6                                  8.14                                    NA
#>   samples.NA19456.OG samples.NA19457.AD samples.NA19457.DP samples.NA19457.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        4                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19457.GQ samples.NA19457.GT samples.NA19457.GD samples.NA19457.OG
#> 1              10.98                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              33.57                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19461.AD samples.NA19461.DP samples.NA19461.GL samples.NA19461.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5               NULL                 NA               NULL              21.44
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19461.GT samples.NA19461.GD samples.NA19461.OG samples.NA19462.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19462.DP samples.NA19462.GL samples.NA19462.GQ samples.NA19462.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  9                                 50.00                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19462.GD samples.NA19462.OG samples.NA19463.AD samples.NA19463.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        4
#> 5                 NA                                                       14
#> 6                 NA                                                        4
#>   samples.NA19463.GL samples.NA19463.GQ samples.NA19463.GT samples.NA19463.GD
#> 1                                 10.98                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                  2.00                                    NA
#> 5                                 60.00                                    NA
#> 6                                 16.52                                    NA
#>   samples.NA19463.OG samples.NA19466.AD samples.NA19466.DP samples.NA19466.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        4                   
#> 5                                                        5                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19466.GQ samples.NA19466.GT samples.NA19466.GD samples.NA19466.OG
#> 1              10.98                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              23.17                                    NA                   
#> 5              36.58                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19467.AD samples.NA19467.DP samples.NA19467.GL samples.NA19467.GQ
#> 1                                     2                                 13.80
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                    11                                 11.94
#> 5                                    16                                 60.00
#> 6                                     1                                  8.23
#>   samples.NA19467.GT samples.NA19467.GD samples.NA19467.OG samples.NA19469.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19469.DP samples.NA19469.GL samples.NA19469.GQ samples.NA19469.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  3                                 20.20                   
#> 5                  6                                 39.59                   
#> 6                  1                                  8.14                   
#>   samples.NA19469.GD samples.NA19469.OG samples.NA19471.AD samples.NA19471.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                                        1
#>   samples.NA19471.GL samples.NA19471.GQ samples.NA19471.GT samples.NA19471.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 33.57                                    NA
#> 6                                  8.14                                    NA
#>   samples.NA19471.OG samples.NA19472.AD samples.NA19472.DP samples.NA19472.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                        9                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19472.GQ samples.NA19472.GT samples.NA19472.GD samples.NA19472.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              20.30                                    NA                   
#> 5              50.00                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19473.AD samples.NA19473.DP samples.NA19473.GL samples.NA19473.GQ
#> 1                                     1                                 10.98
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                     6                                 39.59
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19473.GT samples.NA19473.GD samples.NA19473.OG samples.NA19474.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19474.DP samples.NA19474.GL samples.NA19474.GQ samples.NA19474.GT
#> 1                  1                                 10.98                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                  1                                 24.44                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19474.GD samples.NA19474.OG samples.NA19625.AD samples.NA19625.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA19625.GL samples.NA19625.GQ samples.NA19625.GT samples.NA19625.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 14.32                                    NA
#> 5                                 27.42                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19625.OG samples.NA19648.AD samples.NA19648.DP samples.NA19648.GL
#> 1                                                        4                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        6                   
#> 6                                                        1                   
#>   samples.NA19648.GQ samples.NA19648.GT samples.NA19648.GD samples.NA19648.OG
#> 1              13.46                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              33.77                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.NA19649.AD samples.NA19649.DP samples.NA19649.GL samples.NA19649.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA19649.GT samples.NA19649.GD samples.NA19649.OG samples.NA19651.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                      
#>   samples.NA19651.DP samples.NA19651.GL samples.NA19651.GQ samples.NA19651.GT
#> 1                  1                                  5.66                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                  2                                 11.80                   
#>   samples.NA19651.GD samples.NA19651.OG samples.NA19652.AD samples.NA19652.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                                        1
#>   samples.NA19652.GL samples.NA19652.GQ samples.NA19652.GT samples.NA19652.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 27.83                                    NA
#> 6                                  9.00                                    NA
#>   samples.NA19652.OG samples.NA19654.AD samples.NA19654.DP samples.NA19654.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        5                   
#> 6                                                        1                   
#>   samples.NA19654.GQ samples.NA19654.GT samples.NA19654.GD samples.NA19654.OG
#> 1               5.66                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              14.88                                    NA                   
#> 5              30.81                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.NA19655.AD samples.NA19655.DP samples.NA19655.GL samples.NA19655.GQ
#> 1                                     2                                  8.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     3                                 17.81
#> 5                                     4                                 27.72
#> 6                                     2                                 11.80
#>   samples.NA19655.GT samples.NA19655.GD samples.NA19655.OG samples.NA19658.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA19658.DP samples.NA19658.GL samples.NA19658.GQ samples.NA19658.GT
#> 1                  1                                  5.65                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA19658.GD samples.NA19658.OG samples.NA19660.AD samples.NA19660.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA19660.GL samples.NA19660.GQ samples.NA19660.GT samples.NA19660.GD
#> 1                                  5.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 21.74                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA19660.OG samples.NA19661.AD samples.NA19661.DP samples.NA19661.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        3                   
#> 6                                                        1                   
#>   samples.NA19661.GQ samples.NA19661.GT samples.NA19661.GD samples.NA19661.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              24.72                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.NA19678.AD samples.NA19678.DP samples.NA19678.GL samples.NA19678.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA19678.GT samples.NA19678.GD samples.NA19678.OG samples.NA19684.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                      
#>   samples.NA19684.DP samples.NA19684.GL samples.NA19684.GQ samples.NA19684.GT
#> 1                  1                                  5.66                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                  2                                 11.80                   
#>   samples.NA19684.GD samples.NA19684.OG samples.NA19685.AD samples.NA19685.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                                        1
#>   samples.NA19685.GL samples.NA19685.GQ samples.NA19685.GT samples.NA19685.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6                                  9.00                                    NA
#>   samples.NA19685.OG samples.NA19700.AD samples.NA19700.DP samples.NA19700.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                       11                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19700.GQ samples.NA19700.GT samples.NA19700.GD samples.NA19700.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              17.24                                    NA                   
#> 5              60.00                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19701.AD samples.NA19701.DP samples.NA19701.GL samples.NA19701.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     2                                 17.24
#> 5                                     9                                 50.00
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19701.GT samples.NA19701.GD samples.NA19701.OG samples.NA19703.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19703.DP samples.NA19703.GL samples.NA19703.GQ samples.NA19703.GT
#> 1                  2                                 14.01                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  8                                 45.23                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19703.GD samples.NA19703.OG samples.NA19704.AD samples.NA19704.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA19704.GL samples.NA19704.GQ samples.NA19704.GT samples.NA19704.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 24.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19704.OG samples.NA19707.AD samples.NA19707.DP samples.NA19707.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        7                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19707.GQ samples.NA19707.GT samples.NA19707.GD samples.NA19707.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              14.32                                    NA                   
#> 5              42.22                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19712.AD samples.NA19712.DP samples.NA19712.GL samples.NA19712.GQ
#> 1                                     1                                 10.98
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     3                                 20.20
#> 5                                     3                                 30.51
#> 6                                     1                                  8.14
#>   samples.NA19712.GT samples.NA19712.GD samples.NA19712.OG samples.NA19713.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19713.DP samples.NA19713.GL samples.NA19713.GQ samples.NA19713.GT
#> 1                  5                                 60.00                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  7                                 32.15                   
#> 5                 22                                 60.00                   
#> 6                  1                                  8.14                   
#>   samples.NA19713.GD samples.NA19713.OG samples.NA19720.AD samples.NA19720.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA19720.GL samples.NA19720.GQ samples.NA19720.GT samples.NA19720.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 18.77                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA19720.OG samples.NA19722.AD samples.NA19722.DP samples.NA19722.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19722.GQ samples.NA19722.GT samples.NA19722.GD samples.NA19722.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              18.77                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA19723.AD samples.NA19723.DP samples.NA19723.GL samples.NA19723.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     1                                 18.77
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA19723.GT samples.NA19723.GD samples.NA19723.OG samples.NA19725.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA19725.DP samples.NA19725.GL samples.NA19725.GQ samples.NA19725.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA19725.GD samples.NA19725.OG samples.NA19726.AD samples.NA19726.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        3
#> 6                 NA                                  NULL                 NA
#>   samples.NA19726.GL samples.NA19726.GQ samples.NA19726.GT samples.NA19726.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 14.98                                    NA
#> 5                                 24.72                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA19726.OG samples.NA19818.AD samples.NA19818.DP samples.NA19818.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                       17                   
#> 6                                                        2                   
#>   samples.NA19818.GQ samples.NA19818.GT samples.NA19818.GD samples.NA19818.OG
#> 1              19.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              14.32                                    NA                   
#> 5              60.00                                    NA                   
#> 6              10.80                                    NA                   
#>   samples.NA19819.AD samples.NA19819.DP samples.NA19819.GL samples.NA19819.GQ
#> 1                                     3                                 16.71
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     1                                 14.32
#> 5                                     5                                 36.58
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19819.GT samples.NA19819.GD samples.NA19819.OG samples.NA19834.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA19834.DP samples.NA19834.GL samples.NA19834.GQ samples.NA19834.GT
#> 1                  9                                  4.21                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  7                                 32.15                   
#> 5                 29                                 60.00                   
#> 6                  1                                  8.14                   
#>   samples.NA19834.GD samples.NA19834.OG samples.NA19835.AD samples.NA19835.DP
#> 1                 NA                                                        4
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        4
#> 5                 NA                                                       14
#> 6                 NA                                  NULL                 NA
#>   samples.NA19835.GL samples.NA19835.GQ samples.NA19835.GT samples.NA19835.GD
#> 1                                 19.76                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4                                 23.27                                    NA
#> 5                                 60.00                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19835.OG samples.NA19900.AD samples.NA19900.DP samples.NA19900.GL
#> 1                                                       10                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        7                   
#> 5                                                       28                   
#> 6                                                        2                   
#>   samples.NA19900.GQ samples.NA19900.GT samples.NA19900.GD samples.NA19900.OG
#> 1              37.70                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              32.15                                    NA                   
#> 5              60.00                                    NA                   
#> 6              10.89                                    NA                   
#>   samples.NA19901.AD samples.NA19901.DP samples.NA19901.GL samples.NA19901.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     1                                 14.32
#> 5                                    10                                 50.00
#> 6                                     2                                 10.89
#>   samples.NA19901.GT samples.NA19901.GD samples.NA19901.OG samples.NA19904.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19904.DP samples.NA19904.GL samples.NA19904.GQ samples.NA19904.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  1                                  9.24                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19904.GD samples.NA19904.OG samples.NA19908.AD samples.NA19908.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        1
#> 6                 NA                                  NULL                 NA
#>   samples.NA19908.GL samples.NA19908.GQ samples.NA19908.GT samples.NA19908.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5                                 24.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19908.OG samples.NA19909.AD samples.NA19909.DP samples.NA19909.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        1                   
#> 6                                                        1                   
#>   samples.NA19909.GQ samples.NA19909.GT samples.NA19909.GD samples.NA19909.OG
#> 1               8.16                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4              11.40                                    NA                   
#> 5              24.44                                    NA                   
#> 6               8.14                                    NA                   
#>   samples.NA19914.AD samples.NA19914.DP samples.NA19914.GL samples.NA19914.GQ
#> 1               NULL                 NA               NULL               8.16
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4               NULL                 NA               NULL              11.40
#> 5                                     2                                 27.42
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19914.GT samples.NA19914.GD samples.NA19914.OG samples.NA19916.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19916.DP samples.NA19916.GL samples.NA19916.GQ samples.NA19916.GT
#> 1                  2                                 13.80                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                 NA               NULL              11.40                   
#> 5                  2                                 27.42                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19916.GD samples.NA19916.OG samples.NA19917.AD samples.NA19917.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA19917.GL samples.NA19917.GQ samples.NA19917.GT samples.NA19917.GD
#> 1               NULL               8.16                                    NA
#> 2               NULL               1.82                                    NA
#> 3               NULL               2.56                                    NA
#> 4               NULL              11.40                                    NA
#> 5               NULL              21.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA19917.OG samples.NA19920.AD samples.NA19920.DP samples.NA19920.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        4                   
#> 5                                                       11                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA19920.GQ samples.NA19920.GT samples.NA19920.GD samples.NA19920.OG
#> 1              10.98                                    NA                   
#> 2               1.82                                    NA                   
#> 3               2.56                                    NA                   
#> 4               3.14                                    NA                   
#> 5              60.00                                    NA                   
#> 6               5.49                                    NA                   
#>   samples.NA19921.AD samples.NA19921.DP samples.NA19921.GL samples.NA19921.GQ
#> 1                                     2                                 21.73
#> 2               NULL                 NA               NULL               1.82
#> 3               NULL                 NA               NULL               2.56
#> 4                                     1                                 14.32
#> 5                                     9                                 50.00
#> 6               NULL                 NA               NULL               5.49
#>   samples.NA19921.GT samples.NA19921.GD samples.NA19921.OG samples.NA19982.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA19982.DP samples.NA19982.GL samples.NA19982.GQ samples.NA19982.GT
#> 1                 NA               NULL               8.16                   
#> 2                 NA               NULL               1.82                   
#> 3                 NA               NULL               2.56                   
#> 4                  1                                 14.32                   
#> 5                 14                                 60.00                   
#> 6                 NA               NULL               5.49                   
#>   samples.NA19982.GD samples.NA19982.OG samples.NA20414.AD samples.NA20414.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                                        1
#> 3                 NA                                                        1
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA20414.GL samples.NA20414.GQ samples.NA20414.GT samples.NA20414.GD
#> 1               NULL               8.16                                    NA
#> 2                                  3.81                                    NA
#> 3                                  4.77                                    NA
#> 4               NULL              11.40                                    NA
#> 5               NULL              21.44                                    NA
#> 6               NULL               5.49                                    NA
#>   samples.NA20414.OG samples.NA20502.AD samples.NA20502.DP samples.NA20502.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA20502.GQ samples.NA20502.GT samples.NA20502.GD samples.NA20502.OG
#> 1              10.66                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20505.AD samples.NA20505.DP samples.NA20505.GL samples.NA20505.GQ
#> 1                                     4                                 21.26
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     5                                 30.81
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20505.GT samples.NA20505.GD samples.NA20505.OG samples.NA20508.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20508.DP samples.NA20508.GL samples.NA20508.GQ samples.NA20508.GT
#> 1                  2                                  8.01                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  3                                 24.72                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20508.GD samples.NA20508.OG samples.NA20509.AD samples.NA20509.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        8
#> 6                 NA                                  NULL                 NA
#>   samples.NA20509.GL samples.NA20509.GQ samples.NA20509.GT samples.NA20509.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 39.59                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20509.OG samples.NA20510.AD samples.NA20510.DP samples.NA20510.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA20510.GQ samples.NA20510.GT samples.NA20510.GD samples.NA20510.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20512.AD samples.NA20512.DP samples.NA20512.GL samples.NA20512.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     3                                 24.72
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20512.GT samples.NA20512.GD samples.NA20512.OG samples.NA20515.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20515.DP samples.NA20515.GL samples.NA20515.GQ samples.NA20515.GT
#> 1                  1                                  5.63                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  2                                 21.74                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20515.GD samples.NA20515.OG samples.NA20516.AD samples.NA20516.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                       11
#> 6                 NA                                                        1
#>   samples.NA20516.GL samples.NA20516.GQ samples.NA20516.GT samples.NA20516.GD
#> 1                                  5.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 14.88                                    NA
#> 5                                 50.00                                    NA
#> 6                                  9.00                                    NA
#>   samples.NA20516.OG samples.NA20517.AD samples.NA20517.DP samples.NA20517.GL
#> 1                                                        4                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA20517.GQ samples.NA20517.GT samples.NA20517.GD samples.NA20517.OG
#> 1              13.56                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20518.AD samples.NA20518.DP samples.NA20518.GL samples.NA20518.GQ
#> 1                                     2                                  8.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     2                                 21.74
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20518.GT samples.NA20518.GD samples.NA20518.OG samples.NA20519.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20519.DP samples.NA20519.GL samples.NA20519.GQ samples.NA20519.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  6                                 33.77                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20519.GD samples.NA20519.OG samples.NA20520.AD samples.NA20520.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        7
#> 6                 NA                                  NULL                 NA
#>   samples.NA20520.GL samples.NA20520.GQ samples.NA20520.GT samples.NA20520.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 36.78                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20520.OG samples.NA20521.AD samples.NA20521.DP samples.NA20521.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                       18                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20521.GQ samples.NA20521.GT samples.NA20521.GD samples.NA20521.OG
#> 1              10.66                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              60.00                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20522.AD samples.NA20522.DP samples.NA20522.GL samples.NA20522.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20522.GT samples.NA20522.GD samples.NA20522.OG samples.NA20524.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20524.DP samples.NA20524.GL samples.NA20524.GQ samples.NA20524.GT
#> 1                  3                                 10.66                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  7                                 36.78                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20524.GD samples.NA20524.OG samples.NA20525.AD samples.NA20525.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        2
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA20525.GL samples.NA20525.GQ samples.NA20525.GT samples.NA20525.GD
#> 1                                  5.64                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 14.88                                    NA
#> 5                                 27.83                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20525.OG samples.NA20526.AD samples.NA20526.DP samples.NA20526.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA20526.GQ samples.NA20526.GT samples.NA20526.GD samples.NA20526.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20527.AD samples.NA20527.DP samples.NA20527.GL samples.NA20527.GQ
#> 1                                     1                                  5.64
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20527.GT samples.NA20527.GD samples.NA20527.OG samples.NA20528.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20528.DP samples.NA20528.GL samples.NA20528.GQ samples.NA20528.GT
#> 1                  5                                 16.46                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  2                                 21.74                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20528.GD samples.NA20528.OG samples.NA20529.AD samples.NA20529.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA20529.GL samples.NA20529.GQ samples.NA20529.GT samples.NA20529.GD
#> 1                                 10.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20529.OG samples.NA20530.AD samples.NA20530.DP samples.NA20530.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        2                   
#> 6                                                        1                   
#>   samples.NA20530.GQ samples.NA20530.GT samples.NA20530.GD samples.NA20530.OG
#> 1              25.32                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              14.88                                    NA                   
#> 5              21.74                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.NA20531.AD samples.NA20531.DP samples.NA20531.GL samples.NA20531.GQ
#> 1                                     2                                  8.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     2                                 21.74
#> 6                                     1                                  9.00
#>   samples.NA20531.GT samples.NA20531.GD samples.NA20531.OG samples.NA20532.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20532.DP samples.NA20532.GL samples.NA20532.GQ samples.NA20532.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  3                                 24.72                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20532.GD samples.NA20532.OG samples.NA20533.AD samples.NA20533.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        8
#> 6                 NA                                  NULL                 NA
#>   samples.NA20533.GL samples.NA20533.GQ samples.NA20533.GT samples.NA20533.GD
#> 1                                 29.00                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 39.59                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20533.OG samples.NA20534.AD samples.NA20534.DP samples.NA20534.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        4                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20534.GQ samples.NA20534.GT samples.NA20534.GD samples.NA20534.OG
#> 1               5.64                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              27.83                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20535.AD samples.NA20535.DP samples.NA20535.GL samples.NA20535.GQ
#> 1                                     3                                 10.66
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     1                                 18.77
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20535.GT samples.NA20535.GD samples.NA20535.OG samples.NA20536.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20536.DP samples.NA20536.GL samples.NA20536.GQ samples.NA20536.GT
#> 1                  2                                 28.01                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  4                                 27.83                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20536.GD samples.NA20536.OG samples.NA20537.AD samples.NA20537.DP
#> 1                 NA                                                        6
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        7
#> 6                 NA                                  NULL                 NA
#>   samples.NA20537.GL samples.NA20537.GQ samples.NA20537.GT samples.NA20537.GD
#> 1                                 60.00                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 36.78                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20537.OG samples.NA20538.AD samples.NA20538.DP samples.NA20538.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        2                   
#> 6                                                        3                   
#>   samples.NA20538.GQ samples.NA20538.GT samples.NA20538.GD samples.NA20538.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              14.88                                    NA                   
#> 5              21.74                                    NA                   
#> 6              14.56                                    NA                   
#>   samples.NA20539.AD samples.NA20539.DP samples.NA20539.GL samples.NA20539.GQ
#> 1                                     2                                 27.33
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5                                     4                                 27.72
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20539.GT samples.NA20539.GD samples.NA20539.OG samples.NA20540.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA20540.DP samples.NA20540.GL samples.NA20540.GQ samples.NA20540.GT
#> 1                  5                                 20.29                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  2                                 14.88                   
#> 5                  8                                 39.59                   
#> 6                  2                                 11.80                   
#>   samples.NA20540.GD samples.NA20540.OG samples.NA20541.AD samples.NA20541.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA20541.GL samples.NA20541.GQ samples.NA20541.GT samples.NA20541.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 11.00                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20541.OG samples.NA20542.AD samples.NA20542.DP samples.NA20542.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20542.GQ samples.NA20542.GT samples.NA20542.GD samples.NA20542.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              24.72                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20543.AD samples.NA20543.DP samples.NA20543.GL samples.NA20543.GQ
#> 1                                     2                                 27.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     2                                 21.74
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20543.GT samples.NA20543.GD samples.NA20543.OG samples.NA20544.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20544.DP samples.NA20544.GL samples.NA20544.GQ samples.NA20544.GT
#> 1                  1                                  5.65                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  2                                 14.88                   
#> 5                  3                                 24.83                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20544.GD samples.NA20544.OG samples.NA20581.AD samples.NA20581.DP
#> 1                 NA                                                        5
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                       13
#> 6                 NA                                                        2
#>   samples.NA20581.GL samples.NA20581.GQ samples.NA20581.GT samples.NA20581.GD
#> 1                                 18.29                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 17.81                                    NA
#> 5                                 60.00                                    NA
#> 6                                 11.71                                    NA
#>   samples.NA20581.OG samples.NA20582.AD samples.NA20582.DP samples.NA20582.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        9                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20582.GQ samples.NA20582.GT samples.NA20582.GD samples.NA20582.OG
#> 1               5.64                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              14.88                                    NA                   
#> 5              43.01                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20585.AD samples.NA20585.DP samples.NA20585.GL samples.NA20585.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20585.GT samples.NA20585.GD samples.NA20585.OG samples.NA20586.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA20586.DP samples.NA20586.GL samples.NA20586.GQ samples.NA20586.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20586.GD samples.NA20586.OG samples.NA20588.AD samples.NA20588.DP
#> 1                 NA                                  NULL                 NA
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        4
#> 6                 NA                                  NULL                 NA
#>   samples.NA20588.GL samples.NA20588.GQ samples.NA20588.GT samples.NA20588.GD
#> 1               NULL               3.28                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 12.03                                    NA
#> 5                                 27.83                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20588.OG samples.NA20589.AD samples.NA20589.DP samples.NA20589.GL
#> 1                                  NULL                 NA               NULL
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20589.GQ samples.NA20589.GT samples.NA20589.GD samples.NA20589.OG
#> 1               3.28                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              24.72                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20752.AD samples.NA20752.DP samples.NA20752.GL samples.NA20752.GQ
#> 1                                     2                                 27.30
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5                                     4                                 27.83
#> 6                                     2                                 11.71
#>   samples.NA20752.GT samples.NA20752.GD samples.NA20752.OG samples.NA20753.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20753.DP samples.NA20753.GL samples.NA20753.GQ samples.NA20753.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  5                                 30.81                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20753.GD samples.NA20753.OG samples.NA20754.AD samples.NA20754.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA20754.GL samples.NA20754.GQ samples.NA20754.GT samples.NA20754.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20754.OG samples.NA20755.AD samples.NA20755.DP samples.NA20755.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                       11                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20755.GQ samples.NA20755.GT samples.NA20755.GD samples.NA20755.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              50.00                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20756.AD samples.NA20756.DP samples.NA20756.GL samples.NA20756.GQ
#> 1                                     2                                  8.01
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     5                                 30.81
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20756.GT samples.NA20756.GD samples.NA20756.OG samples.NA20757.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20757.DP samples.NA20757.GL samples.NA20757.GQ samples.NA20757.GT
#> 1                  7                                 60.00                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  6                                 33.77                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20757.GD samples.NA20757.OG samples.NA20758.AD samples.NA20758.DP
#> 1                 NA                                                        4
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA20758.GL samples.NA20758.GQ samples.NA20758.GT samples.NA20758.GD
#> 1                                 60.00                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20758.OG samples.NA20759.AD samples.NA20759.DP samples.NA20759.GL
#> 1                                                        7                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20759.GQ samples.NA20759.GT samples.NA20759.GD samples.NA20759.OG
#> 1              16.33                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              24.72                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20760.AD samples.NA20760.DP samples.NA20760.GL samples.NA20760.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     3                                 17.81
#> 5                                    16                                 60.00
#> 6                                     1                                  9.00
#>   samples.NA20760.GT samples.NA20760.GD samples.NA20760.OG samples.NA20761.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20761.DP samples.NA20761.GL samples.NA20761.GQ samples.NA20761.GT
#> 1                  4                                 60.00                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  7                                 36.78                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20761.GD samples.NA20761.OG samples.NA20765.AD samples.NA20765.DP
#> 1                 NA                                                        5
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                       11
#> 6                 NA                                  NULL                 NA
#>   samples.NA20765.GL samples.NA20765.GQ samples.NA20765.GT samples.NA20765.GD
#> 1                                 16.46                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 12.03                                    NA
#> 5                                 50.00                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20765.OG samples.NA20769.AD samples.NA20769.DP samples.NA20769.GL
#> 1                                                       11                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                                        1                   
#>   samples.NA20769.GQ samples.NA20769.GT samples.NA20769.GD samples.NA20769.OG
#> 1              27.93                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               9.00                                    NA                   
#>   samples.NA20770.AD samples.NA20770.DP samples.NA20770.GL samples.NA20770.GQ
#> 1               NULL                 NA               NULL               3.28
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     5                                 30.71
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20770.GT samples.NA20770.GD samples.NA20770.OG samples.NA20771.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20771.DP samples.NA20771.GL samples.NA20771.GQ samples.NA20771.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  3                                 17.81                   
#> 5                 20                                 60.00                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20771.GD samples.NA20771.OG samples.NA20772.AD samples.NA20772.DP
#> 1                 NA                                                        4
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        2
#> 6                 NA                                  NULL                 NA
#>   samples.NA20772.GL samples.NA20772.GQ samples.NA20772.GT samples.NA20772.GD
#> 1                                 13.46                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 21.74                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20772.OG samples.NA20773.AD samples.NA20773.DP samples.NA20773.GL
#> 1                                                       11                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        3                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20773.GQ samples.NA20773.GT samples.NA20773.GD samples.NA20773.OG
#> 1              60.00                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              24.83                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20774.AD samples.NA20774.DP samples.NA20774.GL samples.NA20774.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20774.GT samples.NA20774.GD samples.NA20774.OG samples.NA20775.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20775.DP samples.NA20775.GL samples.NA20775.GQ samples.NA20775.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  1                                 12.03                   
#> 5                  8                                  8.91                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20775.GD samples.NA20775.OG samples.NA20778.AD samples.NA20778.DP
#> 1                 NA                                                        4
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                        9
#> 6                 NA                                                        1
#>   samples.NA20778.GL samples.NA20778.GQ samples.NA20778.GT samples.NA20778.GD
#> 1                                 26.42                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 10.05                                    NA
#> 5                                 43.01                                    NA
#> 6                                  9.00                                    NA
#>   samples.NA20778.OG samples.NA20783.AD samples.NA20783.DP samples.NA20783.GL
#> 1                                                        4                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                        6                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20783.GQ samples.NA20783.GT samples.NA20783.GD samples.NA20783.OG
#> 1              18.29                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              13.76                                    NA                   
#> 5              33.67                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20785.AD samples.NA20785.DP samples.NA20785.GL samples.NA20785.GQ
#> 1                                     6                                 60.00
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20785.GT samples.NA20785.GD samples.NA20785.OG samples.NA20786.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA20786.DP samples.NA20786.GL samples.NA20786.GQ samples.NA20786.GT
#> 1                  4                                 13.56                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  3                                 17.91                   
#> 5                 10                                 45.23                   
#> 6                  2                                 11.71                   
#>   samples.NA20786.GD samples.NA20786.OG samples.NA20787.AD samples.NA20787.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                       16
#> 6                 NA                                  NULL                 NA
#>   samples.NA20787.GL samples.NA20787.GQ samples.NA20787.GT samples.NA20787.GD
#> 1                                 31.94                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 17.81                                    NA
#> 5                                 25.42                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20787.OG samples.NA20790.AD samples.NA20790.DP samples.NA20790.GL
#> 1                                                        7                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                  NULL                 NA               NULL
#> 6                                  NULL                 NA               NULL
#>   samples.NA20790.GQ samples.NA20790.GT samples.NA20790.GD samples.NA20790.OG
#> 1              60.00                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              15.80                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20792.AD samples.NA20792.DP samples.NA20792.GL samples.NA20792.GQ
#> 1                                     3                                 26.42
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     4                                 20.77
#> 5                                    12                                 50.00
#> 6                                     3                                 14.65
#>   samples.NA20792.GT samples.NA20792.GD samples.NA20792.OG samples.NA20795.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA20795.DP samples.NA20795.GL samples.NA20795.GQ samples.NA20795.GT
#> 1                  6                                 19.31                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  7                                 36.78                   
#> 6                  1                                  9.00                   
#>   samples.NA20795.GD samples.NA20795.OG samples.NA20796.AD samples.NA20796.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        4
#> 5                 NA                                                       13
#> 6                 NA                                                        3
#>   samples.NA20796.GL samples.NA20796.GQ samples.NA20796.GT samples.NA20796.GD
#> 1                                 10.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 20.87                                    NA
#> 5                                 60.00                                    NA
#> 6                                 14.56                                    NA
#>   samples.NA20796.OG samples.NA20797.AD samples.NA20797.DP samples.NA20797.GL
#> 1                                                        3                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        2                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20797.GQ samples.NA20797.GT samples.NA20797.GD samples.NA20797.OG
#> 1              10.66                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              21.74                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20798.AD samples.NA20798.DP samples.NA20798.GL samples.NA20798.GQ
#> 1                                     1                                  5.64
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     2                                 14.88
#> 5                                    12                                 50.00
#> 6                                     1                                  9.00
#>   samples.NA20798.GT samples.NA20798.GD samples.NA20798.OG samples.NA20799.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                  NULL
#> 6                                    NA                                  NULL
#>   samples.NA20799.DP samples.NA20799.GL samples.NA20799.GQ samples.NA20799.GT
#> 1                  6                                 43.98                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                 NA               NULL              15.80                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20799.GD samples.NA20799.OG samples.NA20800.AD samples.NA20800.DP
#> 1                 NA                                                        8
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        4
#> 5                 NA                                                        7
#> 6                 NA                                                        2
#>   samples.NA20800.GL samples.NA20800.GQ samples.NA20800.GT samples.NA20800.GD
#> 1                                 25.35                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 20.87                                    NA
#> 5                                 36.78                                    NA
#> 6                                 11.80                                    NA
#>   samples.NA20800.OG samples.NA20801.AD samples.NA20801.DP samples.NA20801.GL
#> 1                                                        1                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        3                   
#> 5                                                       17                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20801.GQ samples.NA20801.GT samples.NA20801.GD samples.NA20801.OG
#> 1               5.65                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              17.81                                    NA                   
#> 5              60.00                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20802.AD samples.NA20802.DP samples.NA20802.GL samples.NA20802.GQ
#> 1                                     4                                 23.30
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     2                                 14.88
#> 5                                    20                                 60.00
#> 6                                     1                                  9.00
#>   samples.NA20802.GT samples.NA20802.GD samples.NA20802.OG samples.NA20803.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20803.DP samples.NA20803.GL samples.NA20803.GQ samples.NA20803.GT
#> 1                  3                                 25.32                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  5                                 30.81                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20803.GD samples.NA20803.OG samples.NA20804.AD samples.NA20804.DP
#> 1                 NA                                                        3
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                       14
#> 6                 NA                                  NULL                 NA
#>   samples.NA20804.GL samples.NA20804.GQ samples.NA20804.GT samples.NA20804.GD
#> 1                                 10.66                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 17.91                                    NA
#> 5                                 60.00                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20804.OG samples.NA20805.AD samples.NA20805.DP samples.NA20805.GL
#> 1                                                        4                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        5                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20805.GQ samples.NA20805.GT samples.NA20805.GD samples.NA20805.OG
#> 1              13.46                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5               7.53                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20806.AD samples.NA20806.DP samples.NA20806.GL samples.NA20806.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4                                     1                                 12.03
#> 5                                     7                                  4.32
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20806.GT samples.NA20806.GD samples.NA20806.OG samples.NA20807.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20807.DP samples.NA20807.GL samples.NA20807.GQ samples.NA20807.GT
#> 1                  8                                 60.00                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  7                                 36.78                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20807.GD samples.NA20807.OG samples.NA20808.AD samples.NA20808.DP
#> 1                 NA                                                        1
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                                        6
#> 6                 NA                                  NULL                 NA
#>   samples.NA20808.GL samples.NA20808.GQ samples.NA20808.GT samples.NA20808.GD
#> 1                                  5.65                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5                                 33.77                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20808.OG samples.NA20809.AD samples.NA20809.DP samples.NA20809.GL
#> 1                                                        4                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                  NULL                 NA               NULL
#> 5                                                        6                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20809.GQ samples.NA20809.GT samples.NA20809.GD samples.NA20809.OG
#> 1              13.56                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4               9.17                                    NA                   
#> 5              33.67                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20810.AD samples.NA20810.DP samples.NA20810.GL samples.NA20810.GQ
#> 1                                     3                                 10.75
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     3                                 24.83
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20810.GT samples.NA20810.GD samples.NA20810.OG samples.NA20811.AD
#> 1                                    NA                                  NULL
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                      
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20811.DP samples.NA20811.GL samples.NA20811.GQ samples.NA20811.GT
#> 1                 NA               NULL               3.28                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                  4                                 20.77                   
#> 5                 16                                 60.00                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20811.GD samples.NA20811.OG samples.NA20812.AD samples.NA20812.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                  NULL                 NA
#> 5                 NA                                  NULL                 NA
#> 6                 NA                                  NULL                 NA
#>   samples.NA20812.GL samples.NA20812.GQ samples.NA20812.GT samples.NA20812.GD
#> 1                                 19.75                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4               NULL               9.17                                    NA
#> 5               NULL              15.80                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20812.OG samples.NA20813.AD samples.NA20813.DP samples.NA20813.GL
#> 1                                                        5                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        2                   
#> 5                                                       12                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20813.GQ samples.NA20813.GT samples.NA20813.GD samples.NA20813.OG
#> 1              19.30                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              14.88                                    NA                   
#> 5              50.00                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20814.AD samples.NA20814.DP samples.NA20814.GL samples.NA20814.GQ
#> 1                                     1                                  5.66
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5               NULL                 NA               NULL              15.80
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20814.GT samples.NA20814.GD samples.NA20814.OG samples.NA20815.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                      
#>   samples.NA20815.DP samples.NA20815.GL samples.NA20815.GQ samples.NA20815.GT
#> 1                  2                                  2.46                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  2                                 21.74                   
#> 6                  1                                  9.00                   
#>   samples.NA20815.GD samples.NA20815.OG samples.NA20816.AD samples.NA20816.DP
#> 1                 NA                                                        4
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        3
#> 5                 NA                                                       11
#> 6                 NA                                  NULL                 NA
#>   samples.NA20816.GL samples.NA20816.GQ samples.NA20816.GT samples.NA20816.GD
#> 1                                 13.46                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 17.81                                    NA
#> 5                                 50.00                                    NA
#> 6               NULL               6.29                                    NA
#>   samples.NA20816.OG samples.NA20818.AD samples.NA20818.DP samples.NA20818.GL
#> 1                                                        4                   
#> 2                                  NULL                 NA               NULL
#> 3                                  NULL                 NA               NULL
#> 4                                                        1                   
#> 5                                                        1                   
#> 6                                  NULL                 NA               NULL
#>   samples.NA20818.GQ samples.NA20818.GT samples.NA20818.GD samples.NA20818.OG
#> 1              24.26                                    NA                   
#> 2               2.22                                    NA                   
#> 3               1.48                                    NA                   
#> 4              12.03                                    NA                   
#> 5              18.77                                    NA                   
#> 6               6.29                                    NA                   
#>   samples.NA20819.AD samples.NA20819.DP samples.NA20819.GL samples.NA20819.GQ
#> 1                                     1                                  5.65
#> 2               NULL                 NA               NULL               2.22
#> 3               NULL                 NA               NULL               1.48
#> 4               NULL                 NA               NULL               9.17
#> 5                                     5                                 30.81
#> 6               NULL                 NA               NULL               6.29
#>   samples.NA20819.GT samples.NA20819.GD samples.NA20819.OG samples.NA20826.AD
#> 1                                    NA                                      
#> 2                                    NA                                  NULL
#> 3                                    NA                                  NULL
#> 4                                    NA                                  NULL
#> 5                                    NA                                      
#> 6                                    NA                                  NULL
#>   samples.NA20826.DP samples.NA20826.GL samples.NA20826.GQ samples.NA20826.GT
#> 1                  4                                 13.56                   
#> 2                 NA               NULL               2.22                   
#> 3                 NA               NULL               1.48                   
#> 4                 NA               NULL               9.17                   
#> 5                  7                                 36.78                   
#> 6                 NA               NULL               6.29                   
#>   samples.NA20826.GD samples.NA20826.OG samples.NA20828.AD samples.NA20828.DP
#> 1                 NA                                                        2
#> 2                 NA                                  NULL                 NA
#> 3                 NA                                  NULL                 NA
#> 4                 NA                                                        1
#> 5                 NA                                                       12
#> 6                 NA                                                        1
#>   samples.NA20828.GL samples.NA20828.GQ samples.NA20828.GT samples.NA20828.GD
#> 1                                  8.01                                    NA
#> 2               NULL               2.22                                    NA
#> 3               NULL               1.48                                    NA
#> 4                                 12.03                                    NA
#> 5                                 50.00                                    NA
#> 6                                  9.00                                    NA
#>   samples.NA20828.OG
#> 1                   
#> 2                   
#> 3                   
#> 4                   
#> 5                   
#> 6
```

### Query with DuckDB

``` r
# SQL queries on BCF (requires arrow and duckdb packages)
vcf_query(bcf_file, "SELECT CHROM, COUNT(*) as n FROM vcf GROUP BY CHROM")
#>   CHROM  n
#> 1     1 11

# Filter variants by position
vcf_query(bcf_file, "SELECT CHROM, POS, REF, ALT FROM vcf WHERE POS > 1105400 LIMIT 5")
#> [1] CHROM POS   REF   ALT  
#> <0 rows> (or 0-length row.names)
```

## References

- [bcftools documentation](https://samtools.github.io/bcftools/)
- [bcftools GitHub](https://github.com/samtools/bcftools)
- [htslib GitHub](https://github.com/samtools/htslib)
- [VCF specification](https://samtools.github.io/hts-specs/VCFv4.3.pdf)
