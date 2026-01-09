BCF Reader Benchmarks
================

## Overview

Quick, reproducible timing comparisons between:

  - `bcftools view` streamed to `/dev/null`
  - DuckDB `bcf_read()` via the packaged extension

The large input (`test_very_large.bcf`) is expected to live locally
(never committed); generated from GLIMPSE-imputed 1000 Genomes data.
Each command is run twice by default to surface “cold-ish” vs “warm-ish”
cache timing (adjust `n_runs` below).

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
  t <- system.time({
    system(cmd, intern = TRUE, ignore.stdout = TRUE, ignore.stderr = FALSE)
  })
  c(elapsed = unname(t["elapsed"]),
    user = unname(t["user.self"]),
    system = unname(t["sys.self"]))
}

n_runs <- 2  # adjust to change cold/warm repetition

time_runs <- function(cmd, runs = n_runs) {
  if (!can_run) return(NULL)
  times <- t(vapply(seq_len(runs), function(i) run_cmd(cmd), numeric(3)))
  data.frame(
    run = seq_len(runs),
    elapsed = times[, "elapsed"],
    user = times[, "user"],
    system = times[, "system"],
    cache_state = ifelse(seq_len(runs) == 1, "cold-ish", "warm-ish")
  )
}
```

### bcftools view (full file)

``` r
cmd_bcftools_full <- sprintf("bcftools view %s > /dev/null", shQuote(bcf_path))
res_bcftools_full <- time_runs(cmd_bcftools_full)
res_bcftools_full
#>   run elapsed  user system cache_state
#> 1   1  67.079 0.002  0.005    cold-ish
#> 2   2  69.107 0.003  0.007    warm-ish
```

### bcftools view (region)

``` r
cmd_bcftools_region <- sprintf("bcftools view -r %s %s > /dev/null", shQuote(region), shQuote(bcf_path))
res_bcftools_region <- time_runs(cmd_bcftools_region)
res_bcftools_region
#>   run elapsed  user system cache_state
#> 1   1   0.087 0.001  0.004    cold-ish
#> 2   2   0.081 0.000  0.003    warm-ish
```

### DuckDB bcf\_read (full file)

``` r
cmd_duckdb_full <- sprintf(
  "duckdb -unsigned -c \"LOAD %s; SELECT COUNT(*) FROM bcf_read(%s);\"",
  shQuote(duckdb_ext),
  shQuote(bcf_path)
)
res_duckdb_full <- time_runs(cmd_duckdb_full)
res_duckdb_full
#>   run elapsed  user system cache_state
#> 1   1   3.316 0.001  0.003    cold-ish
#> 2   2   3.813 0.000  0.004    warm-ish
```

### DuckDB bcf\_read (region)

``` r
cmd_duckdb_region <- sprintf(
  "duckdb -unsigned -c \"LOAD %s; SELECT COUNT(*) FROM bcf_read(%s, region := %s);\"",
  shQuote(duckdb_ext),
  shQuote(bcf_path),
  shQuote(region)
)
res_duckdb_region <- time_runs(cmd_duckdb_region)
res_duckdb_region
#>   run elapsed  user system cache_state
#> 1   1   0.101 0.001  0.003    cold-ish
#> 2   2   0.098 0.001  0.003    warm-ish
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
