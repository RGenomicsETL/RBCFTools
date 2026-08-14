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
  error_on_status = TRUE
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

## Value

A data frame with one row per stage and columns `stage`, `command`,
`status`, and `signal`.

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
#>    stage         command status signal
#> 1 printf /usr/bin/printf      0      0
#> 2   grep   /usr/bin/grep      0      0
```
