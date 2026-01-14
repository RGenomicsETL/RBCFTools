VCF to Parquet Tidy Format Benchmark
================
2026-01-14

## Overview

This benchmark compares the performance of VCF to Parquet conversion in:

1.  **Wide format** (`vcf_to_parquet_duckdb`): One row per variant,
    FORMAT columns as `FORMAT_<field>_<sample>`
2.  **Tidy format** (`vcf_to_parquet_tidy`): One row per variant-sample,
    with `SAMPLE_ID` column

## Setup

``` r
library(RBCFTools)
library(DBI)
library(duckdb)

# Build extension once
ext_path <- bcf_reader_build(tempdir(), verbose = FALSE)

# Helper function to format file sizes (vectorized)
format_size <- function(bytes) {
  sapply(bytes, function(b) {
    if (is.na(b)) return(NA_character_)
    if (b < 1024) return(paste(b, "B"))
    if (b < 1024^2) return(sprintf("%.1f KB", b / 1024))
    if (b < 1024^3) return(sprintf("%.1f MB", b / 1024^2))
    sprintf("%.2f GB", b / 1024^3)
  })
}

# Benchmark function
benchmark_conversion <- function(input_file, name, threads = 1, n_runs = 3) {
  wide_out <- tempfile(fileext = ".parquet")
  tidy_out <- tempfile(fileext = ".parquet")
  
  # Get input info
  con <- vcf_duckdb_connect(ext_path)
  n_variants <- vcf_count_duckdb(input_file, con = con)
  samples <- vcf_samples_duckdb(input_file, con = con)
  n_samples <- length(samples)
  DBI::dbDisconnect(con, shutdown = TRUE)
  
  # Benchmark wide format
  wide_times <- sapply(seq_len(n_runs), function(i) {
    unlink(wide_out)
    system.time({
      suppressMessages(vcf_to_parquet_duckdb(
        input_file, wide_out, 
        extension_path = ext_path, 
        threads = threads
      ))
    })["elapsed"]
  })
  
  # Benchmark tidy format
  tidy_times <- sapply(seq_len(n_runs), function(i) {
    unlink(tidy_out)
    system.time({
      suppressMessages(vcf_to_parquet_tidy(
        input_file, tidy_out, 
        extension_path = ext_path, 
        threads = threads
      ))
    })["elapsed"]
  })
  
  # Get output sizes
  wide_size <- file.info(wide_out)$size
  tidy_size <- file.info(tidy_out)$size
  
  # Get row counts
  con <- duckdb::dbConnect(duckdb::duckdb())
  wide_rows <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) FROM '%s'", wide_out))[[1]]
  tidy_rows <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) FROM '%s'", tidy_out))[[1]]
  DBI::dbDisconnect(con, shutdown = TRUE)
  
  # Cleanup
  unlink(c(wide_out, tidy_out))
  
  data.frame(
    name = name,
    n_variants = n_variants,
    n_samples = n_samples,
    threads = threads,
    wide_time_mean = mean(wide_times),
    wide_time_sd = sd(wide_times),
    tidy_time_mean = mean(tidy_times),
    tidy_time_sd = sd(tidy_times),
    wide_size = wide_size,
    tidy_size = tidy_size,
    wide_rows = wide_rows,
    tidy_rows = tidy_rows,
    tidy_overhead = tidy_times / wide_times
  )
}
```

## Test Files

``` r
# Package test files
vcf_3samples <- system.file("extdata", "1000G_3samples.vcf.gz", package = "RBCFTools")
vcf_deepvar <- system.file("extdata", "test_deep_variant.vcf.gz", package = "RBCFTools")

# List available test files
test_files <- data.frame(
  name = c("1000G_3samples", "DeepVariant"),
  path = c(vcf_3samples, vcf_deepvar),
  stringsAsFactors = FALSE
)

# Add file sizes
test_files$size <- sapply(test_files$path, function(p) format_size(file.info(p)$size))

knitr::kable(test_files, caption = "Test VCF Files")
```

| name           | path                                                                     | size   |
|:---------------|:-------------------------------------------------------------------------|:-------|
| 1000G_3samples | /usr/local/lib/R/site-library/RBCFTools/extdata/1000G_3samples.vcf.gz    | 1.5 KB |
| DeepVariant    | /usr/local/lib/R/site-library/RBCFTools/extdata/test_deep_variant.vcf.gz | 5.5 MB |

Test VCF Files

## Benchmark: Small Multi-Sample VCF (1000G 3 samples)

``` r
results_3s <- benchmark_conversion(vcf_3samples, "1000G_3samples", threads = 1)
knitr::kable(results_3s[, c("name", "n_variants", "n_samples", 
                             "wide_time_mean", "tidy_time_mean",
                             "wide_rows", "tidy_rows")],
             digits = 3,
             caption = "3-sample VCF Benchmark")
```

| name           | n_variants | n_samples | wide_time_mean | tidy_time_mean | wide_rows | tidy_rows |
|:---------------|-----------:|----------:|---------------:|---------------:|----------:|----------:|
| 1000G_3samples |         11 |         3 |          0.014 |          0.015 |        11 |        33 |
| 1000G_3samples |         11 |         3 |          0.014 |          0.015 |        11 |        33 |
| 1000G_3samples |         11 |         3 |          0.014 |          0.015 |        11 |        33 |

3-sample VCF Benchmark

### Output Size Comparison

``` r
cat("Wide format:\n")
```

    ## Wide format:

``` r
cat("  Rows:", results_3s$wide_rows, "\n")
```

    ##   Rows: 11 11 11

``` r
cat("  Size:", format_size(results_3s$wide_size), "\n")
```

    ##   Size: 6.3 KB 6.3 KB 6.3 KB

``` r
cat("\nTidy format:\n")
```

    ## 
    ## Tidy format:

``` r
cat("  Rows:", results_3s$tidy_rows, "(", results_3s$n_samples, "x expansion)\n")
```

    ##   Rows: 33 33 33 ( 3 3 3 x expansion)

``` r
cat("  Size:", format_size(results_3s$tidy_size), "\n")
```

    ##   Size: 4.7 KB 4.7 KB 4.7 KB

``` r
cat("\nSize ratio (tidy/wide):", sprintf("%.2fx", results_3s$tidy_size / results_3s$wide_size), "\n")
```

    ## 
    ## Size ratio (tidy/wide): 0.74x 0.74x 0.74x

## Benchmark: Single-Sample VCF (DeepVariant)

``` r
results_dv <- benchmark_conversion(vcf_deepvar, "DeepVariant", threads = 1)
knitr::kable(results_dv[, c("name", "n_variants", "n_samples", 
                             "wide_time_mean", "tidy_time_mean",
                             "wide_rows", "tidy_rows")],
             digits = 3,
             caption = "Single-sample VCF Benchmark")
```

| name        | n_variants | n_samples | wide_time_mean | tidy_time_mean | wide_rows | tidy_rows |
|:------------|-----------:|----------:|---------------:|---------------:|----------:|----------:|
| DeepVariant |     368319 |         1 |          0.535 |          0.548 |    368319 |    368319 |
| DeepVariant |     368319 |         1 |          0.535 |          0.548 |    368319 |    368319 |
| DeepVariant |     368319 |         1 |          0.535 |          0.548 |    368319 |    368319 |

Single-sample VCF Benchmark

### Output Size Comparison

``` r
cat("Wide format:\n")
```

    ## Wide format:

``` r
cat("  Rows:", results_dv$wide_rows, "\n")
```

    ##   Rows: 368319 368319 368319

``` r
cat("  Size:", format_size(results_dv$wide_size), "\n")
```

    ##   Size: 3.8 MB 3.8 MB 3.8 MB

``` r
cat("\nTidy format:\n")
```

    ## 
    ## Tidy format:

``` r
cat("  Rows:", results_dv$tidy_rows, "(single sample - no expansion)\n")
```

    ##   Rows: 368319 368319 368319 (single sample - no expansion)

``` r
cat("  Size:", format_size(results_dv$tidy_size), "\n")
```

    ##   Size: 3.8 MB 3.8 MB 3.8 MB

``` r
cat("\nSize ratio (tidy/wide):", sprintf("%.2fx", results_dv$tidy_size / results_dv$wide_size), "\n")
```

    ## 
    ## Size ratio (tidy/wide): 1.00x 1.00x 1.00x

## Summary Results

``` r
all_results <- rbind(results_3s, results_dv)

summary_df <- data.frame(
  File = all_results$name,
  Variants = all_results$n_variants,
  Samples = all_results$n_samples,
  `Wide Time (s)` = sprintf("%.3f", all_results$wide_time_mean),
  `Tidy Time (s)` = sprintf("%.3f", all_results$tidy_time_mean),
  `Time Overhead` = sprintf("%.2fx", all_results$tidy_time_mean / all_results$wide_time_mean),
  `Wide Size` = sapply(all_results$wide_size, format_size),
  `Tidy Size` = sapply(all_results$tidy_size, format_size),
  `Size Ratio` = sprintf("%.2fx", all_results$tidy_size / all_results$wide_size),
  check.names = FALSE
)

knitr::kable(summary_df, caption = "Conversion Benchmark Summary")
```

| File           | Variants | Samples | Wide Time (s) | Tidy Time (s) | Time Overhead | Wide Size | Tidy Size | Size Ratio |
|:---------------|---------:|--------:|:--------------|:--------------|:--------------|:----------|:----------|:-----------|
| 1000G_3samples |       11 |       3 | 0.014         | 0.015         | 1.02x         | 6.3 KB    | 4.7 KB    | 0.74x      |
| 1000G_3samples |       11 |       3 | 0.014         | 0.015         | 1.02x         | 6.3 KB    | 4.7 KB    | 0.74x      |
| 1000G_3samples |       11 |       3 | 0.014         | 0.015         | 1.02x         | 6.3 KB    | 4.7 KB    | 0.74x      |
| DeepVariant    |   368319 |       1 | 0.535         | 0.548         | 1.02x         | 3.8 MB    | 3.8 MB    | 1.00x      |
| DeepVariant    |   368319 |       1 | 0.535         | 0.548         | 1.02x         | 3.8 MB    | 3.8 MB    | 1.00x      |
| DeepVariant    |   368319 |       1 | 0.535         | 0.548         | 1.02x         | 3.8 MB    | 3.8 MB    | 1.00x      |

Conversion Benchmark Summary

## Query Performance Comparison

Compare query performance on wide vs tidy format for common operations.

``` r
# Create test files
wide_file <- tempfile(fileext = ".parquet")
tidy_file <- tempfile(fileext = ".parquet")

suppressMessages({
  vcf_to_parquet_duckdb(vcf_3samples, wide_file, extension_path = ext_path)
  vcf_to_parquet_tidy(vcf_3samples, tidy_file, extension_path = ext_path)
})

con <- duckdb::dbConnect(duckdb::duckdb())

# Query 1: Count variants per chromosome
query_count <- function(file) {
  system.time({
    DBI::dbGetQuery(con, sprintf(
      "SELECT CHROM, COUNT(*) as n FROM '%s' GROUP BY CHROM", file
    ))
  })["elapsed"]
}

# Query 2: Filter by genotype (different for wide vs tidy)
query_gt_wide <- function() {
  system.time({
    DBI::dbGetQuery(con, sprintf(
      "SELECT CHROM, POS FROM '%s' WHERE FORMAT_GT_HG00098 = '1|1'", wide_file
    ))
  })["elapsed"]
}

query_gt_tidy <- function() {
  system.time({
    DBI::dbGetQuery(con, sprintf(
      "SELECT CHROM, POS FROM '%s' WHERE SAMPLE_ID = 'HG00098' AND FORMAT_GT = '1|1'", tidy_file
    ))
  })["elapsed"]
}

# Query 3: Aggregate across samples (tidy is more natural)
query_sample_agg_tidy <- function() {
  system.time({
    DBI::dbGetQuery(con, sprintf(
      "SELECT SAMPLE_ID, COUNT(*) as het_count 
       FROM '%s' 
       WHERE FORMAT_GT LIKE '%%|1' OR FORMAT_GT LIKE '1|%%'
       GROUP BY SAMPLE_ID", tidy_file
    ))
  })["elapsed"]
}

# Run benchmarks
query_results <- data.frame(
  Query = c("Count by CHROM (wide)", "Count by CHROM (tidy)",
            "Filter GT (wide)", "Filter GT (tidy)",
            "Sample aggregation (tidy)"),
  Time_ms = c(
    query_count(wide_file) * 1000,
    query_count(tidy_file) * 1000,
    query_gt_wide() * 1000,
    query_gt_tidy() * 1000,
    query_sample_agg_tidy() * 1000
  )
)

DBI::dbDisconnect(con, shutdown = TRUE)
unlink(c(wide_file, tidy_file))

knitr::kable(query_results, digits = 2, caption = "Query Performance (ms)")
```

| Query                     | Time_ms |
|:--------------------------|--------:|
| Count by CHROM (wide)     |       2 |
| Count by CHROM (tidy)     |       1 |
| Filter GT (wide)          |       1 |
| Filter GT (tidy)          |       2 |
| Sample aggregation (tidy) |       2 |

Query Performance (ms)

## Conclusions

### When to use Tidy Format

**Advantages:** - Natural for sample-level analysis and aggregation -
Easier to join/merge samples from different VCFs - Compatible with
DuckLake MERGE/UPSERT operations - Better for cohort building from
single-sample VCFs

**Disadvantages:** - Row expansion (N samples × M variants rows) -
Larger file size for multi-sample VCFs - Slightly slower conversion

### Recommendations

| Use Case                      | Recommended Format |
|-------------------------------|--------------------|
| Archive/storage               | Wide               |
| Single-sample VCFs for cohort | Tidy               |
| Sample-level QC/analysis      | Tidy               |
| Variant-centric analysis      | Wide               |
| DuckLake incremental loading  | Tidy               |

## Session Info

``` r
sessionInfo()
```

    ## R version 4.5.2 (2025-10-31)
    ## Platform: x86_64-pc-linux-gnu
    ## Running under: Ubuntu 24.04.3 LTS
    ## 
    ## Matrix products: default
    ## BLAS:   /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3 
    ## LAPACK: /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.26.so;  LAPACK version 3.12.0
    ## 
    ## locale:
    ##  [1] LC_CTYPE=en_US.UTF-8       LC_NUMERIC=C              
    ##  [3] LC_TIME=en_US.UTF-8        LC_COLLATE=en_US.UTF-8    
    ##  [5] LC_MONETARY=en_US.UTF-8    LC_MESSAGES=en_US.UTF-8   
    ##  [7] LC_PAPER=en_US.UTF-8       LC_NAME=C                 
    ##  [9] LC_ADDRESS=C               LC_TELEPHONE=C            
    ## [11] LC_MEASUREMENT=en_US.UTF-8 LC_IDENTIFICATION=C       
    ## 
    ## time zone: Europe/Berlin
    ## tzcode source: system (glibc)
    ## 
    ## attached base packages:
    ## [1] parallel  stats     graphics  grDevices datasets  utils     methods  
    ## [8] base     
    ## 
    ## other attached packages:
    ## [1] duckdb_1.4.3              DBI_1.2.3                
    ## [3] RBCFTools_1.23-0.0.2.9000
    ## 
    ## loaded via a namespace (and not attached):
    ##  [1] digest_0.6.39     codetools_0.2-20  fastmap_1.2.0     xfun_0.54        
    ##  [5] bspm_0.5.7        knitr_1.50        htmltools_0.5.9   rmarkdown_2.30   
    ##  [9] nanoarrow_0.7.0-2 cli_3.6.5         vctrs_0.6.5       compiler_4.5.2   
    ## [13] tools_4.5.2       evaluate_1.0.5    yaml_2.3.11       rlang_1.1.7
