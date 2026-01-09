BCF Reader Benchmarks
================

## Overview

Quick, reproducible timing comparisons between:

  - `bcftools view` streamed to `/dev/null`
  - DuckDB `bcf_read()` via the packaged extension

The large input (`test_very_large.bcf`) is expected to live locally
(never committed); generated from GLIMPSE-imputed 1000 Genomes data.

## Prerequisites

  - `bcftools` available on `PATH`
  - DuckDB CLI installed and `duckdb` R package (for rendering)
  - Built extension at `params$duckdb_ext` (`make` in this folder)
  - Large BCF at `params$bcf_path` (defaults to `test_very_large.bcf` in
    this directory)

<!-- end list -->

``` r
bcf_path <- params$bcf_path
region <- params$region
duckdb_ext <- params$duckdb_ext

has_bcf <- file.exists(bcf_path)
has_ext <- file.exists(duckdb_ext)
can_run <- has_bcf && has_ext

if (!has_bcf) message("BCF not found: ", bcf_path, ". Benchmarks will be skipped.")
if (!has_ext) message("DuckDB extension not found: ", duckdb_ext, ". Build with `make` first; benchmarks will be skipped.")

data.frame(
  resource = c("bcf_path", "duckdb_ext"),
  path = c(bcf_path, duckdb_ext),
  exists = c(has_bcf, has_ext)
)
#>     resource                              path exists
#> 1   bcf_path         ../../test_very_large.bcf   TRUE
#> 2 duckdb_ext build/bcf_reader.duckdb_extension   TRUE
```

## Benchmarks

Timings are single runs using `system.time()` for wall-clock
comparisons; adjust or repeat as needed. Region queries mirror full-file
timings but with `-r` / `region :=`.

``` r
run_cmd <- function(cmd) {
  system.time({
    out <- system(cmd, intern = TRUE, ignore.stdout = TRUE, ignore.stderr = FALSE)
    attr(out, "status") <- attr(out, "status")
    out
  })
}
```

### bcftools view (full file)

``` r
cmd_bcftools_full <- sprintf("bcftools view %s > /dev/null", shQuote(bcf_path))
time_bcftools_full <- run_cmd(cmd_bcftools_full)
time_bcftools_full
#>    user  system elapsed 
#>  63.957   1.058  65.699
```

### bcftools view (region)

``` r
cmd_bcftools_region <- sprintf("bcftools view -r %s %s > /dev/null", shQuote(region), shQuote(bcf_path))
time_bcftools_region <- run_cmd(cmd_bcftools_region)
time_bcftools_region
#>    user  system elapsed 
#>   0.064   0.019   0.086
```

### DuckDB bcf\_read (full file)

``` r
cmd_duckdb_full <- sprintf(
  "duckdb -unsigned -c \"LOAD %s; SELECT COUNT(*) FROM bcf_read(%s);\"",
  shQuote(duckdb_ext),
  shQuote(bcf_path)
)
time_duckdb_full <- run_cmd(cmd_duckdb_full)
time_duckdb_full
#>    user  system elapsed 
#>  37.649   0.746   3.513
```

### DuckDB bcf\_read (region)

``` r
cmd_duckdb_region <- sprintf(
  "duckdb -unsigned -c \"LOAD %s; SELECT COUNT(*) FROM bcf_read(%s, region := %s);\"",
  shQuote(duckdb_ext),
  shQuote(bcf_path),
  shQuote(region)
)
time_duckdb_region <- run_cmd(cmd_duckdb_region)
time_duckdb_region
#>    user  system elapsed 
#>   0.088   0.024   0.097
```

## Notes

  - These timings are single passes; rerun and average for more stable
    numbers.
  - Ensure the file and its index are co-located with fast storage
    (local SSD preferred).
  - Adjust `region` to match indexed contigs present in
    `test_very_large.bcf`.
  - If required resources are missing, chunks are skipped and a status
    table is shown above.
