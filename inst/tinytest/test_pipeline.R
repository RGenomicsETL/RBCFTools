library(RBCFTools)
library(tinytest)

required <- Sys.which(c("printf", "grep", "cat", "tr", "false", "sleep"))
if (any(!nzchar(required))) {
  exit_file("Pipeline test executables are unavailable")
}

stage <- pipeline_stage("printf", c("alpha\nbeta\n"), name = "producer")
expect_inherits(stage, "rbcftools_pipeline_stage")
expect_identical(stage$name, "producer")
expect_error(pipeline_stage(""), "non-empty")
expect_error(pipeline_stage("definitely-not-an-rbcftools-executable"), "unavailable")
expect_error(pipeline_stage("printf", NA_character_), "missing")

output <- tempfile()
status <- run_pipeline(
  list(stage, pipeline_stage("grep", "beta", name = "filter")),
  stdout = output
)
expect_identical(readLines(output), "beta")
expect_identical(status$stage, c("producer", "filter"))
expect_identical(status$status, c(0L, 0L))
expect_identical(status$signal, c(0L, 0L))
expect_true(attr(status, "wall_seconds") > 0)

measured <- run_pipeline(pipeline_stage("sleep", "0.05", name = "measured sleep"))
if (identical(Sys.info()[["sysname"]], "Linux")) {
  expect_true(measured$peak_rss_kib[[1L]] > 0)
  expect_true(attr(measured, "pipeline_peak_rss_kib") > 0)
  expect_true(measured$peak_threads[[1L]] >= 1L)
  expect_true(attr(measured, "pipeline_peak_threads") >= 1L)
} else {
  expect_true(is.na(measured$peak_rss_kib[[1L]]))
  expect_true(is.na(attr(measured, "pipeline_peak_rss_kib")))
  expect_true(is.na(measured$peak_threads[[1L]]))
  expect_true(is.na(attr(measured, "pipeline_peak_threads")))
}
expect_true(attr(measured, "wall_seconds") >= 0.04)

input <- tempfile()
translated <- tempfile()
writeLines(c("abc", "def"), input)
status <- run_pipeline(
  list(pipeline_stage("cat"), pipeline_stage("tr", c("a-z", "A-Z"))),
  stdin = input,
  stdout = translated
)
expect_identical(readLines(translated), c("ABC", "DEF"))
expect_true(all(status$status == 0L))

binary_input <- tempfile()
binary_output <- tempfile()
binary_payload <- as.raw(rep(0:255, 4096L))
writeBin(binary_payload, binary_input)
run_pipeline(
  list(pipeline_stage("cat"), pipeline_stage("cat")),
  stdin = binary_input,
  stdout = binary_output
)
expect_identical(
  readBin(binary_output, what = "raw", n = length(binary_payload)),
  binary_payload,
  info = "binary streams must pass through OS pipes without R text conversion"
)

injection_marker <- tempfile()
literal_output <- tempfile()
literal_argument <- paste0("$(touch ", injection_marker, ")")
run_pipeline(
  pipeline_stage("printf", c("%s", literal_argument)),
  stdout = literal_output
)
expect_identical(readChar(literal_output, file.info(literal_output)$size), literal_argument)
expect_false(file.exists(injection_marker), info = "pipeline arguments must never be shell-evaluated")

failed <- run_pipeline(pipeline_stage("false", name = "expected failure"), error_on_status = FALSE)
expect_identical(failed$status, 1L)
expect_error(
  run_pipeline(pipeline_stage("false", name = "expected failure")),
  "expected failure.*status 1"
)

same_path <- tempfile()
writeLines("input", same_path)
expect_error(
  run_pipeline(pipeline_stage("cat"), stdin = same_path, stdout = same_path),
  "different files"
)
expect_error(run_pipeline(list()), "one or more")
expect_error(run_pipeline(stage, error_on_status = NA), "TRUE or FALSE")
expect_error(run_pipeline(stage, cpu_affinity = -1L), "non-negative")

if (identical(Sys.info()[["sysname"]], "Linux") && nzchar(Sys.which("taskset"))) {
  affinity_output <- system2("taskset", c("-pc", Sys.getpid()), stdout = TRUE)
  affinity_list <- sub("^.*: ", "", affinity_output[[1L]])
  first_range <- strsplit(affinity_list, ",", fixed = TRUE)[[1L]][[1L]]
  first_cpu <- as.integer(sub("-.*$", "", first_range))
  pinned_output <- tempfile()
  pinned <- run_pipeline(
    pipeline_stage("grep", c("Cpus_allowed_list", "/proc/self/status")),
    stdout = pinned_output,
    cpu_affinity = first_cpu
  )
  expect_true(grepl(sprintf("[[:space:]]%d$", first_cpu), readLines(pinned_output)))
  expect_identical(attr(pinned, "cpu_affinity"), first_cpu)
  expect_identical(pinned$command, unname(Sys.which("grep")))
}
