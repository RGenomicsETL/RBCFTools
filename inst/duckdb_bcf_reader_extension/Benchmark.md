BCF Reader Benchmarks
================

## Overview

Quick, reproducible timing comparisons between:

  - `bcftools view` streamed to `/dev/null` in two modes:
      - **Text emit** (`-Ov`): forces VCF string formatting (slow path)
      - **Binary emit** (`-Ou`): skips VCF formatting (fairer vs DuckDB)
  - DuckDB `bcf_read()` via the packaged extension (projection-pushed
    `COUNT(*)`)

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

time_expr <- function(expr, runs = 1L, enabled = can_run) {
  if (!enabled) return(NULL)
  times <- t(vapply(seq_len(runs), function(i) {
    t <- system.time(force(expr))
    c(elapsed = unname(t["elapsed"]),
      user = unname(t["user.self"]),
      system = unname(t["sys.self"]))
  }, numeric(3)))
  data.frame(
    run = seq_len(nrow(times)),
    elapsed = times[, "elapsed"],
    user = times[, "user"],
    system = times[, "system"],
    cache_state = ifelse(seq_len(nrow(times)) == 1, "cold-ish", "warm-ish")
  )
}
```

### bcftools view — text VCF emit (full file)

``` r
cmd_bcftools_full_text <- sprintf("bcftools view -Ov %s > /dev/null", shQuote(bcf_path))
res_bcftools_full_text <- time_runs(cmd_bcftools_full_text)
res_bcftools_full_text
#>   run elapsed  user system cache_state
#> 1   1  65.785 0.004  0.004    cold-ish
#> 2   2  66.061 0.003  0.007    warm-ish
```

### bcftools view — binary BCF emit (full file, fairer)

``` r
cmd_bcftools_full_bin <- sprintf("bcftools view -Ou %s > /dev/null", shQuote(bcf_path))
res_bcftools_full_bin <- time_runs(cmd_bcftools_full_bin)
res_bcftools_full_bin
#>   run elapsed  user system cache_state
#> 1   1  36.653 0.003  0.003    cold-ish
#> 2   2  35.357 0.001  0.006    warm-ish
```

### bcftools view — text VCF emit (region)

``` r
cmd_bcftools_region_text <- sprintf("bcftools view -Ov -r %s %s > /dev/null", shQuote(region), shQuote(bcf_path))
res_bcftools_region_text <- time_runs(cmd_bcftools_region_text)
res_bcftools_region_text
#>   run elapsed  user system cache_state
#> 1   1   0.079 0.001  0.003    cold-ish
#> 2   2   0.075 0.000  0.003    warm-ish
```

### bcftools view — binary BCF emit (region, fairer)

``` r
cmd_bcftools_region_bin <- sprintf("bcftools view -Ou -r %s %s > /dev/null", shQuote(region), shQuote(bcf_path))
res_bcftools_region_bin <- time_runs(cmd_bcftools_region_bin)
res_bcftools_region_bin
#>   run elapsed  user system cache_state
#> 1   1   0.069 0.001  0.004    cold-ish
#> 2   2   0.071 0.000  0.004    warm-ish
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
#>   run elapsed user system cache_state
#> 1   1   3.780    0  0.004    cold-ish
#> 2   2   4.135    0  0.004    warm-ish
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
#>   run elapsed user system cache_state
#> 1   1   0.094    0  0.004    cold-ish
#> 2   2   0.093    0  0.003    warm-ish
```

### Parquet conversion: 4 threads vs 10 threads (DuckDB extension)

Compares `vcf_to_parquet_duckdb()` (via the bcf\_reader extension) with
different thread counts. Skips if prerequisites are
missing.

``` r
parquet_can_run <- has_bcf && has_ext && requireNamespace("RBCFTools", quietly = TRUE)

parquet_4threads <- tempfile(fileext = ".parquet")
parquet_10threads <- tempfile(fileext = ".parquet")
```

``` r

# 10-thread conversion via DuckDB bcf_reader extension (requires index)
res_parquet_10threads <- if (RBCFTools::vcf_has_index(bcf_path)) {
  time_expr({
    RBCFTools::vcf_to_parquet_duckdb(
      input_file = bcf_path,
      output_file = parquet_10threads,
      extension_path = duckdb_ext,
      compression = "zstd",
      row_group_size = 100000L,
      threads = 10L
    )
  }, enabled = parquet_can_run)
} else {
  NULL
}
#> Processing 23 contigs (out of 23 in header) using 10 threads (DuckDB mode)
#> Merging temporary Parquet files... to /tmp/RtmpqNtsD2/file21ff541cb57a93.parquet
#> Merged 23 parquet files -> file21ff541cb57a93.parquet (81554892 rows)
```

``` r
# 4-thread conversion via DuckDB bcf_reader extension
res_parquet_4threads <- time_expr({
  RBCFTools::vcf_to_parquet_duckdb(
    input_file = bcf_path,
    output_file = parquet_4threads,
    extension_path = duckdb_ext,
    compression = "zstd",
    row_group_size = 100000L,
    threads = 4L
  )
}, enabled = parquet_can_run)
#> Processing 23 contigs (out of 23 in header) using 4 threads (DuckDB mode)
#> Merging temporary Parquet files... to /tmp/RtmpqNtsD2/file21ff544a37098c.parquet
#> Merged 23 parquet files -> file21ff544a37098c.parquet (81554892 rows)

res_parquet_4threads
#>         run elapsed    user system cache_state
#> elapsed   1 115.531 240.805 39.078    cold-ish
res_parquet_10threads
#>         run elapsed    user system cache_state
#> elapsed   1  88.663 260.914 40.434    cold-ish

unlink(c(parquet_4threads, parquet_10threads))
```

## Notes

  - These timings are single passes; rerun and average for more stable
    numbers.
  - DuckDB `COUNT(*)` benefits from projection pushdown (no INFO/FORMAT
    decoding). The bcftools binary runs (`-Ou`) avoid text formatting
    and are the fairest comparison; `-Ov` reflects worst-case text emit.
  - Ensure the file and its index are co-located with fast storage
    (local SSD preferred).
  - Adjust `region` to match indexed contigs present in
    `test_very_large.bcf`.
  - If required resources are missing, chunks are skipped and a status
    table is shown above.
