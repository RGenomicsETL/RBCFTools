library(RBCFTools)
library(tinytest)

required <- Sys.which(c("printf", "grep", "cat", "tr", "false"))
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
