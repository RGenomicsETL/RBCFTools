
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
#> [1] "1.19"
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
#> [1] "build=configure libcurl=yes S3=yes GCS=yes libdeflate=yes lzma=yes bzip2=yes plugins=yes plugin-path=/usr/local/lib/htslib:/usr/local/libexec/htslib:/usr/lib/x86_64-linux-gnu/htslib: htscodecs=1.6.0"
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
#> Warning in system2(bcftools_path(), args = c("view", "-H", "-r",
#> "chr22:20000000-20100000", : running command
#> ''/usr/local/lib/R/site-library/RBCFTools/bcftools/bin/bcftools' view -H -r
#> chr22:20000000-20100000
#> s3://1000genomes-dragen-v3.7.6/data/cohorts/gvcf-genotyper-dragen-3.7.6/hg19/3202-samples-cohort/3202_samples_cohort_gg_chr22.vcf.gz
#> 2>/dev/null' had status 255
length(result)  
#> [1] 0
```

## References

- [bcftools documentation](https://samtools.github.io/bcftools/)
- [bcftools GitHub](https://github.com/samtools/bcftools)
- [htslib GitHub](https://github.com/samtools/htslib)
- [VCF specification](https://samtools.github.io/hts-specs/VCFv4.3.pdf)
