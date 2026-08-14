library(RBCFTools)
library(tinytest)

expect_true(is.character(fastdup_path()) && length(fastdup_path()) == 1L)
expect_true(is.character(fastdup_bin_dir()) && length(fastdup_bin_dir()) == 1L)
expect_true(is.character(fastdup_tools()))
expect_true(file.exists(system.file("ERRATA.md", package = "RBCFTools")))

fastdup <- fastdup_path()
samtools <- samtools_path()
if (!nzchar(fastdup) || !nzchar(samtools)) {
  expect_true(is.na(fastdup_version()))
  exit_file("Bundled executables are unavailable on this build")
}

expect_true(file.exists(fastdup) && file.access(fastdup, mode = 1L) == 0L)
expect_true("fastdup" %in% fastdup_tools())
expect_identical(fastdup_version(), "1.0.0")

test_dir <- tempfile("fastdup-overlay-")
dir.create(test_dir)

no_rg_sam <- file.path(test_dir, "no-rg.sam")
no_rg_bam <- file.path(test_dir, "no-rg.bam")
no_rg_out <- file.path(test_dir, "no-rg.out.bam")
writeLines(
  c(
    "@HD\tVN:1.6\tSO:coordinate",
    "@SQ\tSN:chr1\tLN:1000",
    "A:1:FC:1:1:10:10\t0\tchr1\t101\t60\t10M\t*\t0\t0\tAAAAAAAAAA\tIIIIIIIIII"
  ),
  no_rg_sam
)
run_pipeline(pipeline_stage(samtools, c("view", "-bo", no_rg_bam, no_rg_sam)))
run_pipeline(
  pipeline_stage(
    fastdup,
    c(
      "--input", no_rg_bam,
      "--output", no_rg_out,
      "--metrics", file.path(test_dir, "no-rg.metrics"),
      "--none-duplex-io"
    )
  ),
  stderr = file.path(test_dir, "no-rg.log")
)
expect_identical(system2(samtools, c("view", "-c", no_rg_out), stdout = TRUE), "1")

library_sam <- file.path(test_dir, "libraries.sam")
library_bam <- file.path(test_dir, "libraries.bam")
library_out <- file.path(test_dir, "libraries.out.bam")
writeLines(
  c(
    "@HD\tVN:1.6\tSO:coordinate",
    "@SQ\tSN:chr1\tLN:1000",
    "@RG\tID:rgA\tLB:libA\tSM:sample",
    "@RG\tID:rgB\tLB:libB\tSM:sample",
    "A:1:FC:1:1:10:10\t99\tchr1\t101\t60\t10M\t=\t151\t60\tAAAAAAAAAA\tIIIIIIIIII\tRG:Z:rgA",
    "B:1:FC:1:1:20:20\t99\tchr1\t101\t60\t10M\t=\t151\t60\tAAAAAAAAAA\tIIIIIIIIII\tRG:Z:rgB",
    "A:1:FC:1:1:10:10\t147\tchr1\t151\t60\t10M\t=\t101\t-60\tTTTTTTTTTT\tIIIIIIIIII\tRG:Z:rgA",
    "B:1:FC:1:1:20:20\t147\tchr1\t151\t60\t10M\t=\t101\t-60\tTTTTTTTTTT\tIIIIIIIIII\tRG:Z:rgB"
  ),
  library_sam
)
run_pipeline(
  list(
    pipeline_stage("cat", library_sam, name = "SAM producer"),
    pipeline_stage(samtools, c("sort", "-o", library_bam, "-"), name = "samtools sort")
  ),
  stderr = file.path(test_dir, "sort.log")
)
run_pipeline(
  pipeline_stage(
    fastdup,
    c(
      "--input", library_bam,
      "--output", library_out,
      "--metrics", file.path(test_dir, "libraries.metrics"),
      "--none-duplex-io"
    )
  ),
  stderr = file.path(test_dir, "libraries.log")
)
library_records <- system2(samtools, c("view", library_out), stdout = TRUE)
library_flags <- as.integer(vapply(strsplit(library_records, "\t", fixed = TRUE), `[[`, "", 2L))
expect_identical(sum(bitwAnd(library_flags, 1024L) != 0L), 0L,
                 info = "records from different LB values must not mark one another")

optical_sam <- file.path(test_dir, "optical.sam")
optical_bam <- file.path(test_dir, "optical.bam")
writeLines(
  c(
    "@HD\tVN:1.6\tSO:coordinate",
    "@SQ\tSN:chr1\tLN:1000",
    "@RG\tID:rgA\tLB:libA\tSM:sample",
    "A:1:FC:1:1:32767:32767\t99\tchr1\t101\t60\t10M\t=\t151\t60\tAAAAAAAAAA\tIIIIIIIIII\tRG:Z:rgA",
    "B:1:FC:1:1:32768:32768\t99\tchr1\t101\t60\t10M\t=\t151\t60\tAAAAAAAAAA\t!!!!!!!!!!\tRG:Z:rgA",
    "A:1:FC:1:1:32767:32767\t147\tchr1\t151\t60\t10M\t=\t101\t-60\tTTTTTTTTTT\tIIIIIIIIII\tRG:Z:rgA",
    "B:1:FC:1:1:32768:32768\t147\tchr1\t151\t60\t10M\t=\t101\t-60\tTTTTTTTTTT\t!!!!!!!!!!\tRG:Z:rgA"
  ),
  optical_sam
)
run_pipeline(pipeline_stage(samtools, c("view", "-bo", optical_bam, optical_sam)))

dont_tag_out <- file.path(test_dir, "dont-tag.bam")
run_pipeline(
  pipeline_stage(
    fastdup,
    c(
      "--input", optical_bam,
      "--output", dont_tag_out,
      "--metrics", file.path(test_dir, "dont-tag.metrics"),
      "--none-duplex-io"
    )
  ),
  stderr = file.path(test_dir, "dont-tag.log")
)
dont_tag_records <- system2(samtools, c("view", dont_tag_out), stdout = TRUE)
dont_tag_fields <- strsplit(dont_tag_records, "\t", fixed = TRUE)
dont_tag_flags <- as.integer(vapply(dont_tag_fields, `[[`, "", 2L))
dont_tag_duplicates <- bitwAnd(dont_tag_flags, 1024L) != 0L
expect_identical(sum(dont_tag_duplicates), 2L)
expect_false(any(grepl("\tDT:Z:", dont_tag_records[dont_tag_duplicates])),
             info = "DontTag must not add DT to duplicates")

all_tag_out <- file.path(test_dir, "all-tag.bam")
run_pipeline(
  pipeline_stage(
    fastdup,
    c(
      "--input", optical_bam,
      "--output", all_tag_out,
      "--metrics", file.path(test_dir, "all-tag.metrics"),
      "--none-duplex-io",
      "--tagging-policy", "All"
    )
  ),
  stderr = file.path(test_dir, "all-tag.log")
)
all_tag_records <- system2(samtools, c("view", all_tag_out), stdout = TRUE)
all_tag_fields <- strsplit(all_tag_records, "\t", fixed = TRUE)
all_tag_flags <- as.integer(vapply(all_tag_fields, `[[`, "", 2L))
all_tag_duplicates <- bitwAnd(all_tag_flags, 1024L) != 0L
expect_identical(sum(all_tag_duplicates), 2L)
expect_true(all(grepl("\tDT:Z:SQ", all_tag_records[all_tag_duplicates])),
            info = "32-bit boundary neighbors must remain optical duplicates")
