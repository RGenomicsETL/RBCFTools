#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
if (length(file_arg) != 1L) stop("Run this benchmark with Rscript", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
runner_dir <- dirname(script_path)
repo_root <- normalizePath(file.path(runner_dir, ".."), mustWork = TRUE)
default_benchmark_dir <- file.path(runner_dir, "hg02088-exome-pipelines")
benchmark_dir <- Sys.getenv("RBCFTOOLS_BENCH_OUTPUT_DIR", default_benchmark_dir)

extra_lib <- Sys.getenv("RBCFTOOLS_BENCH_LIB", unset = "")
if (nzchar(extra_lib)) .libPaths(c(extra_lib, .libPaths()))
suppressPackageStartupMessages(library(RBCFTools))
if (!requireNamespace("Rminibwa", quietly = TRUE)) {
  stop("The full benchmark requires the Rminibwa package", call. = FALSE)
}

reference <- Sys.getenv(
  "RBCFTOOLS_BENCH_REFERENCE",
  "/root/Rdragmap/.checks/real-human/input/hs37d5.fa"
)
reads_1 <- Sys.getenv(
  "RBCFTOOLS_BENCH_READ1",
  "/root/Rdragmap/.checks/real-human/input/SRR716421_1.filt.fastq.gz"
)
reads_2 <- Sys.getenv(
  "RBCFTOOLS_BENCH_READ2",
  "/root/Rdragmap/.checks/real-human/input/SRR716421_2.filt.fastq.gz"
)
work_dir <- Sys.getenv(
  "RBCFTOOLS_BENCH_WORK",
  file.path(repo_root, ".benchmarks", basename(benchmark_dir))
)
workload_name <- Sys.getenv("RBCFTOOLS_BENCH_WORKLOAD", "HG02088_SRR716421_complete_exome")
threads <- Sys.getenv("RBCFTOOLS_BENCH_THREADS", "6")
sort_threads <- Sys.getenv("RBCFTOOLS_BENCH_SORT_THREADS", "2")
fixmate_threads <- Sys.getenv("RBCFTOOLS_BENCH_FIXMATE_THREADS", "1")
cpu_spec <- Sys.getenv("RBCFTOOLS_BENCH_CPUS", "")
if (!nzchar(cpu_spec)) {
  stop("Set RBCFTOOLS_BENCH_CPUS to one logical CPU ID per physical core", call. = FALSE)
}
cpu_affinity <- as.integer(strsplit(cpu_spec, ",", fixed = TRUE)[[1L]])
if (anyNA(cpu_affinity) || anyDuplicated(cpu_affinity)) {
  stop("RBCFTOOLS_BENCH_CPUS must contain distinct integer CPU IDs", call. = FALSE)
}
sibling_keys <- vapply(
  cpu_affinity,
  function(cpu) {
    path <- sprintf("/sys/devices/system/cpu/cpu%d/topology/thread_siblings_list", cpu)
    if (!file.exists(path)) stop(sprintf("CPU %d is unavailable", cpu), call. = FALSE)
    readLines(path, warn = FALSE)[[1L]]
  },
  character(1L)
)
if (anyDuplicated(sibling_keys)) {
  stop("RBCFTOOLS_BENCH_CPUS includes SMT siblings from the same physical core", call. = FALSE)
}
cpu_max_frequency_khz <- vapply(
  cpu_affinity,
  function(cpu) {
    path <- sprintf("/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_max_freq", cpu)
    if (file.exists(path)) readLines(path, warn = FALSE)[[1L]] else "unknown"
  },
  character(1L)
)
affinity_probe <- system2("taskset", c("--cpu-list", paste(cpu_affinity, collapse = ","), "true"))
if (!identical(affinity_probe, 0L)) {
  stop("The requested CPU set is outside this process's allowed cpuset", call. = FALSE)
}
if (as.integer(threads) > length(cpu_affinity)) {
  stop("The mapper/marker thread count exceeds the pinned physical-core budget", call. = FALSE)
}
marker_repetitions <- as.integer(Sys.getenv("RBCFTOOLS_BENCH_MARKER_REPS", "3"))
if (is.na(marker_repetitions) || marker_repetitions < 1L) {
  stop("RBCFTOOLS_BENCH_MARKER_REPS must be a positive integer", call. = FALSE)
}
drop_caches <- identical(Sys.getenv("RBCFTOOLS_BENCH_DROP_CACHES", "1"), "1")
user_id <- as.integer(system2("id", "-u", stdout = TRUE))
if (drop_caches && (user_id != 0L || file.access("/proc/sys/vm/drop_caches", 2L) != 0L)) {
  stop("Cold-cache benchmarking requires root access to /proc/sys/vm/drop_caches", call. = FALSE)
}
keep_outputs <- identical(Sys.getenv("RBCFTOOLS_BENCH_KEEP_OUTPUTS", "0"), "1")
bwa_index_cache <- Sys.getenv("RBCFTOOLS_BENCH_BWA_INDEX_CACHE", "")
minibwa_index_cache <- Sys.getenv("RBCFTOOLS_BENCH_MINIBWA_INDEX_CACHE", "")

inputs <- c(reference = reference, reads_1 = reads_1, reads_2 = reads_2)
missing_inputs <- names(inputs)[!file.exists(inputs)]
if (length(missing_inputs) > 0L) {
  stop(sprintf("Missing benchmark inputs: %s", paste(missing_inputs, collapse = ", ")), call. = FALSE)
}
executables <- c(
  bwa = unname(Sys.which("bwa")),
  minibwa = Rminibwa::minibwa_path(),
  samtools = samtools_path(),
  fastdup = fastdup_path()
)
if (any(!nzchar(executables))) stop("One or more benchmark executables are unavailable", call. = FALSE)

dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(benchmark_dir, recursive = TRUE, showWarnings = FALSE)
results_path <- file.path(benchmark_dir, "performance.csv")
validation_path <- file.path(benchmark_dir, "validation.csv")
environment_path <- file.path(benchmark_dir, "environment.txt")
logs_dir <- file.path(benchmark_dir, "logs")
unlink(logs_dir, recursive = TRUE, force = TRUE)
dir.create(logs_dir, showWarnings = FALSE)
lscpu_output <- system2("lscpu", stdout = TRUE)
cpu_line <- grep("^Model name:", lscpu_output, value = TRUE)
cpu_model <- if (length(cpu_line) == 1L) trimws(sub("^[^:]*:", "", cpu_line)) else "unknown"
memtotal_line <- grep("^MemTotal:", readLines("/proc/meminfo"), value = TRUE)
memory_bytes <- as.numeric(strsplit(trimws(memtotal_line), "[[:space:]]+")[[1L]][2L]) * 1024
repo_commit <- system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)
repo_status <- system2("git", c("-C", repo_root, "status", "--porcelain"), stdout = TRUE)
repo_tree_state <- if (length(repo_status) == 0L) "clean" else "modified"

writeLines(
  c(
    sprintf("run_utc=%s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    sprintf("workload=%s", workload_name),
    sprintf("host=%s", Sys.info()[["nodename"]]),
    sprintf("platform=%s", R.version$platform),
    sprintf("cpu_model=%s", cpu_model),
    sprintf("logical_cpus=%s", parallel::detectCores()),
    sprintf("memory_bytes=%.0f", memory_bytes),
    sprintf("kernel=%s", paste(Sys.info()[c("sysname", "release", "machine")], collapse = " ")),
    sprintf("r_version=%s", getRversion()),
    sprintf("rbcftools_version=%s", as.character(packageVersion("RBCFTools"))),
    sprintf("rbcftools_commit=%s", repo_commit[[1L]]),
    sprintf("rbcftools_tree_state=%s", repo_tree_state),
    sprintf("fastdup_version=%s", fastdup_version()),
    sprintf("samtools_version=%s", samtools_version()),
    sprintf("minibwa_version=%s", Rminibwa::minibwa_version()),
    sprintf("bwa_path=%s", executables[["bwa"]]),
    sprintf("threads=%s", threads),
    sprintf("sort_threads=%s", sort_threads),
    sprintf("fixmate_threads=%s", fixmate_threads),
    sprintf("cpu_affinity=%s", paste(cpu_affinity, collapse = ",")),
    sprintf("cpu_thread_siblings=%s", paste(sibling_keys, collapse = ";")),
    sprintf("cpu_max_frequency_khz=%s", paste(cpu_max_frequency_khz, collapse = ",")),
    sprintf("marker_repetitions=%d", marker_repetitions),
    sprintf("cache_policy=%s", if (drop_caches) "cold: sync + drop_caches=3 before timed phase" else "uncontrolled"),
    sprintf("bwa_index_cache=%s", bwa_index_cache),
    sprintf("minibwa_index_cache=%s", minibwa_index_cache),
    sprintf("reference=%s", normalizePath(reference)),
    sprintf("read1=%s", normalizePath(reads_1)),
    sprintf("read2=%s", normalizePath(reads_2)),
    sprintf("reference_bytes=%.0f", file.info(reference)$size),
    sprintf("read1_bytes=%.0f", file.info(reads_1)$size),
    sprintf("read2_bytes=%.0f", file.info(reads_2)$size)
  ),
  environment_path
)

results <- data.frame(
  mapper = character(),
  phase = character(),
  tool = character(),
  repetition = integer(),
  cache_state = character(),
  wall_seconds = numeric(),
  peak_rss_kib = numeric(),
  peak_threads = integer(),
  cpu_affinity = character(),
  thread_configuration = character(),
  stage_status = character(),
  output_bytes = numeric(),
  stringsAsFactors = FALSE
)
write_results <- function() write.csv(results, results_path, row.names = FALSE)
write_results()
run_timed <- function(mapper, phase, tool, thread_configuration, repetition = 1L,
                      output = NULL, action) {
  message(sprintf("[%s] %s / %s / rep %d", format(Sys.time()), mapper, phase, repetition))
  if (drop_caches) {
    system2("sync")
    writeLines("3", "/proc/sys/vm/drop_caches")
  }
  started <- proc.time()[["elapsed"]]
  value <- action()
  observed_wall <- attr(value, "wall_seconds", exact = TRUE)
  elapsed <- if (length(observed_wall) == 1L && is.finite(observed_wall)) {
    observed_wall
  } else {
    proc.time()[["elapsed"]] - started
  }
  peak_rss_kib <- attr(value, "pipeline_peak_rss_kib", exact = TRUE)
  if (length(peak_rss_kib) != 1L) peak_rss_kib <- NA_real_
  peak_threads <- attr(value, "pipeline_peak_threads", exact = TRUE)
  if (length(peak_threads) != 1L) peak_threads <- NA_integer_
  stage_status <- if (is.data.frame(value) && all(c("stage", "status") %in% names(value))) {
    paste0(value$stage, "=", value$status, collapse = ";")
  } else {
    "0"
  }
  output_bytes <- if (!is.null(output) && file.exists(output)) file.info(output)$size else NA_real_
  results <<- rbind(
    results,
    data.frame(
      mapper = mapper,
      phase = phase,
      tool = tool,
      repetition = repetition,
      cache_state = if (drop_caches) "cold" else "uncontrolled",
      wall_seconds = elapsed,
      peak_rss_kib = peak_rss_kib,
      peak_threads = peak_threads,
      cpu_affinity = paste(cpu_affinity, collapse = ","),
      thread_configuration = thread_configuration,
      stage_status = stage_status,
      output_bytes = output_bytes,
      stringsAsFactors = FALSE
    )
  )
  write_results()
  value
}
run_pinned <- function(stages, ...) {
  run_pipeline(stages, ..., cpu_affinity = cpu_affinity)
}
reuse_index <- function(mapper, tool, cache, prefix) {
  files <- list.files(cache, full.names = TRUE)
  if (length(files) == 0L) stop(sprintf("Index cache is empty: %s", cache), call. = FALSE)
  suffix <- sub("^[^.]+", "", basename(files))
  destinations <- paste0(prefix, suffix)
  if (!all(file.link(files, destinations))) {
    stop(sprintf("Unable to link the %s index cache", mapper), call. = FALSE)
  }
  results <<- rbind(
    results,
    data.frame(
      mapper = mapper,
      phase = "reference index",
      tool = tool,
      repetition = 1L,
      cache_state = "prebuilt index",
      wall_seconds = NA_real_,
      peak_rss_kib = NA_real_,
      peak_threads = NA_integer_,
      cpu_affinity = paste(cpu_affinity, collapse = ","),
      thread_configuration = "prebuilt",
      stage_status = "reused=0",
      output_bytes = sum(file.info(files)$size),
      stringsAsFactors = FALSE
    )
  )
  write_results()
}

count_records <- function(path, extra_args = character()) {
  as.numeric(system2(executables[["samtools"]], c("view", "-c", extra_args, path), stdout = TRUE))
}
digest_duplicate_names <- function(path, label) {
  names_path <- file.path(work_dir, paste0(label, ".duplicate-names.txt"))
  run_pinned(
    list(
      pipeline_stage(executables[["samtools"]], c("view", "-f", "1024", path), name = "samtools view"),
      pipeline_stage("cut", "-f1", name = "cut qname"),
      pipeline_stage("sort", "-u", name = "unique qname sort")
    ),
    stdout = names_path,
    stderr = file.path(work_dir, paste0(label, ".digest.log"))
  )
  sha <- strsplit(system2("sha256sum", names_path, stdout = TRUE), "[[:space:]]+")[[1L]][1L]
  unique_names <- length(readLines(names_path, warn = FALSE))
  unlink(names_path)
  c(sha256 = sha, unique_names = unique_names)
}

validation <- data.frame(
  mapper = character(),
  marker = character(),
  repetition = integer(),
  records = numeric(),
  duplicate_records = numeric(),
  duplicate_qnames = numeric(),
  duplicate_qname_sha256 = character(),
  bam_bytes = numeric(),
  bai_bytes = numeric(),
  quickcheck = logical(),
  stringsAsFactors = FALSE
)
write.csv(validation, validation_path, row.names = FALSE)

for (mapper in c("rminibwa", "bwa")) {
  prefix <- file.path(work_dir, paste0(mapper, "-reference"))
  baseline <- file.path(work_dir, paste0(mapper, ".fixmate-coordinate.bam"))
  mapper_log <- file.path(work_dir, paste0(mapper, ".pipeline.log"))

  if (mapper == "rminibwa") {
    if (nzchar(minibwa_index_cache)) {
      reuse_index(mapper, "minibwa index", minibwa_index_cache, prefix)
    } else {
      run_timed(
        mapper, "reference index", "minibwa index",
        thread_configuration = sprintf("minibwa_index=%s", threads),
        action = function() {
          run_pinned(
            pipeline_stage(
              executables[["minibwa"]],
              c("index", "-t", threads, reference, prefix),
              name = "minibwa index"
            ),
            stderr = mapper_log
          )
        }
      )
    }
    mapper_stage <- pipeline_stage(
      executables[["minibwa"]],
      c("map", "-t", threads, prefix, reads_1, reads_2),
      name = "minibwa map"
    )
  } else {
    if (nzchar(bwa_index_cache)) {
      reuse_index(mapper, "bwa index", bwa_index_cache, prefix)
    } else {
      run_timed(
        mapper, "reference index", "bwa index",
        thread_configuration = "bwa_index=1",
        action = function() {
          run_pinned(
            pipeline_stage(
              executables[["bwa"]],
              c("index", "-p", prefix, reference),
              name = "bwa index"
            ),
            stderr = mapper_log
          )
        }
      )
    }
    mapper_stage <- pipeline_stage(
      executables[["bwa"]],
      c("mem", "-t", threads, prefix, reads_1, reads_2),
      name = "bwa mem"
    )
  }

  run_timed(
    mapper, "map and prepare", "mapper + samtools",
    thread_configuration = sprintf(
      "mapper=%s;name_sort=%s;fixmate=%s;coordinate_sort=%s",
      threads, sort_threads, fixmate_threads, sort_threads
    ),
    output = baseline,
    action = function() {
    run_pinned(
      list(
        mapper_stage,
        pipeline_stage(
          executables[["samtools"]],
          c("sort", "-n", "-@", sort_threads, "-m", "1G", "-O", "BAM", "-o", "-", "-"),
          name = "name sort"
        ),
        pipeline_stage(
          executables[["samtools"]],
          c("fixmate", "-m", "-@", fixmate_threads, "-", "-"),
          name = "fixmate"
        ),
        pipeline_stage(
          executables[["samtools"]],
          c("sort", "-@", sort_threads, "-m", "1G", "-O", "BAM", "-o", baseline, "-"),
          name = "coordinate sort"
        )
      ),
      stderr = mapper_log
    )
  })
  run_pinned(pipeline_stage(executables[["samtools"]], c("quickcheck", baseline)))
  unlink(Sys.glob(paste0(prefix, "*")), recursive = TRUE, force = TRUE)

  for (repetition in seq_len(marker_repetitions)) {
    marker_order <- if (repetition %% 2L == 0L) c("fastdup", "samtools") else c("samtools", "fastdup")
    for (marker in marker_order) {
      output <- file.path(work_dir, paste0(mapper, ".", marker, ".bam"))
      marker_log <- file.path(work_dir, sprintf("%s.%s.rep%d.log", mapper, marker, repetition))
      index_log <- file.path(work_dir, sprintf("%s.%s.rep%d.index.log", mapper, marker, repetition))
      unlink(c(output, paste0(output, ".bai"), paste0(output, ".metrics")), force = TRUE)
      if (marker == "samtools") {
        run_timed(
          mapper, "duplicate marking", "samtools markdup",
          thread_configuration = sprintf("markdup=%s", threads),
          repetition = repetition,
          output = output,
          action = function() {
            run_pinned(
              pipeline_stage(
                executables[["samtools"]],
                c("markdup", "-@", threads, "-s", baseline, output),
                name = "samtools markdup"
              ),
              stderr = marker_log
            )
          }
        )
      } else {
        run_timed(
          mapper, "duplicate marking", "FastDup",
          thread_configuration = sprintf("fastdup=%s", threads),
          repetition = repetition,
          output = output,
          action = function() {
            run_pinned(
              pipeline_stage(
                executables[["fastdup"]],
                c(
                  "--input", baseline,
                  "--output", output,
                  "--metrics", paste0(output, ".metrics"),
                  "--num-threads", threads,
                  "--tagging-policy", "DontTag"
                ),
                name = "fastdup"
              ),
              stderr = marker_log
            )
          }
        )
      }
      run_timed(
        mapper, "index", "samtools index",
        thread_configuration = sprintf("samtools_index=%s", threads),
        repetition = repetition,
        output = paste0(output, ".bai"),
        action = function() {
          run_pinned(
            pipeline_stage(
              executables[["samtools"]],
              c("index", "-@", threads, output),
              name = "samtools index"
            ),
            stderr = index_log
          )
        }
      )
      quickcheck_status <- system2(executables[["samtools"]], c("quickcheck", output))
      duplicate_digest <- digest_duplicate_names(output, sprintf("%s.%s.rep%d", mapper, marker, repetition))
      validation <- rbind(
        validation,
        data.frame(
          mapper = mapper,
          marker = marker,
          repetition = repetition,
          records = count_records(output),
          duplicate_records = count_records(output, c("-f", "1024")),
          duplicate_qnames = as.numeric(duplicate_digest[["unique_names"]]),
          duplicate_qname_sha256 = duplicate_digest[["sha256"]],
          bam_bytes = file.info(output)$size,
          bai_bytes = file.info(paste0(output, ".bai"))$size,
          quickcheck = identical(quickcheck_status, 0L),
          stringsAsFactors = FALSE
        )
      )
      write.csv(validation, validation_path, row.names = FALSE)
      evidence <- c(marker_log, index_log, paste0(output, ".metrics"))
      evidence <- evidence[file.exists(evidence)]
      evidence <- evidence[file.info(evidence)$size > 0]
      if (length(evidence) > 0L) {
        evidence_names <- paste0(mapper, ".", marker, ".rep", repetition, ".", basename(evidence))
        file.copy(evidence, file.path(logs_dir, evidence_names), overwrite = TRUE)
      }
    }
  }
  if (file.exists(mapper_log)) {
    file.copy(mapper_log, file.path(logs_dir, paste0(mapper, ".pipeline.log")), overwrite = TRUE)
  }
  if (!keep_outputs) {
    unlink(
      c(
        baseline,
        file.path(work_dir, paste0(mapper, ".samtools.bam")),
        file.path(work_dir, paste0(mapper, ".samtools.bam.bai")),
        file.path(work_dir, paste0(mapper, ".fastdup.bam")),
        file.path(work_dir, paste0(mapper, ".fastdup.bam.bai")),
        file.path(work_dir, paste0(mapper, ".fastdup.bam.metrics"))
      ),
      recursive = TRUE,
      force = TRUE
    )
  }
}

message("Benchmark complete: ", results_path)
