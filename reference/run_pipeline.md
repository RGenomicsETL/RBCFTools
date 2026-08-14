# Run an External Executable Pipeline

Connects the standard output of each stage directly to the standard
input of the next stage using operating-system pipes. Arguments are
passed directly to each executable; no shell command is constructed or
evaluated.

## Usage

``` r
run_pipeline(
  stages,
  stdin = NULL,
  stdout = NULL,
  stderr = NULL,
  error_on_status = TRUE,
  cpu_affinity = NULL
)
```

## Arguments

- stages:

  A pipeline stage or a non-empty list of objects created by
  [`pipeline_stage()`](https://rgenomicsetl.github.io/RBCFTools/reference/pipeline_stage.md).

- stdin:

  Optional input file for the first stage. `NULL` inherits the R
  process's standard input.

- stdout:

  Optional output file for the last stage. `NULL` inherits the R
  process's standard output. Binary output should always be directed to
  a file or handled by the final executable itself.

- stderr:

  Optional shared error-log file. `NULL` inherits the R process's
  standard error.

- error_on_status:

  Whether to raise an error when any stage exits with a non-zero status.

- cpu_affinity:

  Optional integer vector of logical CPU IDs. On Linux, every stage is
  started through `taskset` with this same allowed CPU set. Select one
  logical CPU per physical core when comparing thread budgets; do not
  count SMT siblings as separate physical cores.

## Value

A data frame with one row per stage and columns `stage`, `command`,
`status`, `signal`, `peak_rss_kib`, and `peak_threads`. The
`wall_seconds`, `pipeline_peak_rss_kib`, `pipeline_peak_threads`, and
`cpu_affinity` attributes describe the whole pipeline. On Linux, memory
and thread counts are sampled every 10 ms from each live stage. Pipeline
peak RSS is the largest simultaneous sum of stage resident sets; it is
aggregate RSS, not unique proportional set size. Unsupported platforms
return `NA` for sampled metrics.

## Details

This function is intended for streaming groups such as an aligner
writing SAM to standard output followed by `samtools sort`.
File-dependent steps, including FastDup and `samtools index`, should be
run as subsequent one-stage pipelines.

## Examples

``` r
output <- tempfile(fileext = ".txt")
result <- run_pipeline(
  list(
    pipeline_stage("printf", c("alpha\\nbeta\\n")),
    pipeline_stage("grep", "beta")
  ),
  stdout = output
)
readLines(output)
#> [1] "beta"
result
#>    stage         command status signal peak_rss_kib peak_threads
#> 1 printf /usr/bin/printf      0      0          204            1
#> 2   grep   /usr/bin/grep      0      0           96            1
```
