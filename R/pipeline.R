# Generic external executable pipelines.

#' Define an Executable Pipeline Stage
#'
#' Defines one executable and its argument vector without invoking a shell.
#' Stages can reference executables bundled by RBCFTools, executables exported
#' by another package, or programs available on `PATH`.
#'
#' @param command A length-one character string naming an executable or giving
#'   its path.
#' @param args A character vector of arguments passed directly to the
#'   executable.
#' @param name A label used in pipeline results. Defaults to the executable's
#'   basename.
#'
#' @return An object of class `rbcftools_pipeline_stage`.
#'
#' @examples
#' pipeline_stage(samtools_path(), c("view", "--help"))
#'
#' @export
pipeline_stage <- function(command, args = character(), name = NULL) {
  if (!is.character(command) || length(command) != 1L) {
    stop("command must be one non-empty character string", call. = FALSE)
  }
  if (is.na(command) || !nzchar(command)) {
    stop("command must be one non-empty character string", call. = FALSE)
  }
  if (!is.character(args) || anyNA(args)) {
    stop("args must be a character vector without missing values", call. = FALSE)
  }

  resolved <- if (grepl(.Platform$file.sep, command, fixed = TRUE)) {
    normalizePath(command, mustWork = TRUE)
  } else {
    unname(Sys.which(command))
  }
  if (!nzchar(resolved) || file.access(resolved, mode = 1L) != 0L) {
    stop(sprintf("Executable is unavailable: %s", command), call. = FALSE)
  }

  if (is.null(name)) {
    name <- basename(resolved)
  }
  if (!is.character(name) || length(name) != 1L) {
    stop("name must be one non-empty character string", call. = FALSE)
  }
  if (is.na(name) || !nzchar(name)) {
    stop("name must be one non-empty character string", call. = FALSE)
  }

  structure(
    list(command = resolved, args = args, name = name),
    class = "rbcftools_pipeline_stage"
  )
}

#' Run an External Executable Pipeline
#'
#' Connects the standard output of each stage directly to the standard input
#' of the next stage using operating-system pipes. Arguments are passed
#' directly to each executable; no shell command is constructed or evaluated.
#'
#' This function is intended for streaming groups such as an aligner writing
#' SAM to standard output followed by `samtools sort`. File-dependent steps,
#' including FastDup and `samtools index`, should be run as subsequent
#' one-stage pipelines.
#'
#' @param stages A pipeline stage or a non-empty list of objects created by
#'   [pipeline_stage()].
#' @param stdin Optional input file for the first stage. `NULL` inherits the R
#'   process's standard input.
#' @param stdout Optional output file for the last stage. `NULL` inherits the R
#'   process's standard output. Binary output should always be directed to a
#'   file or handled by the final executable itself.
#' @param stderr Optional shared error-log file. `NULL` inherits the R
#'   process's standard error.
#' @param error_on_status Whether to raise an error when any stage exits with a
#'   non-zero status.
#' @param cpu_affinity Optional integer vector of logical CPU IDs. On Linux,
#'   every stage is started through `taskset` with this same allowed CPU set.
#'   Select one logical CPU per physical core when comparing thread budgets;
#'   do not count SMT siblings as separate physical cores.
#'
#' @return A data frame with one row per stage and columns `stage`, `command`,
#'   `status`, `signal`, `peak_rss_kib`, and `peak_threads`. The
#'   `wall_seconds`, `pipeline_peak_rss_kib`, `pipeline_peak_threads`, and
#'   `cpu_affinity` attributes describe the whole pipeline. On Linux, memory
#'   and thread counts are sampled every 10 ms from each live stage. Pipeline
#'   peak RSS is the largest simultaneous sum of stage resident sets; it is
#'   aggregate RSS, not unique proportional set size. Unsupported platforms
#'   return `NA` for sampled metrics.
#'
#' @examples
#' output <- tempfile(fileext = ".txt")
#' result <- run_pipeline(
#'   list(
#'     pipeline_stage("printf", c("alpha\\nbeta\\n")),
#'     pipeline_stage("grep", "beta")
#'   ),
#'   stdout = output
#' )
#' readLines(output)
#' result
#'
#' @export
run_pipeline <- function(stages, stdin = NULL, stdout = NULL, stderr = NULL,
                         error_on_status = TRUE, cpu_affinity = NULL) {
  if (inherits(stages, "rbcftools_pipeline_stage")) {
    stages <- list(stages)
  }
  if (!is.list(stages) || length(stages) == 0L ||
      !all(vapply(stages, inherits, logical(1L), "rbcftools_pipeline_stage"))) {
    stop("stages must contain one or more pipeline_stage() objects", call. = FALSE)
  }
  if (!is.logical(error_on_status) || length(error_on_status) != 1L ||
      is.na(error_on_status)) {
    stop("error_on_status must be TRUE or FALSE", call. = FALSE)
  }

  redirections <- list(stdin = stdin, stdout = stdout, stderr = stderr)
  for (field in names(redirections)) {
    value <- redirections[[field]]
    if (is.null(value)) next
    if (!is.character(value) || length(value) != 1L) {
      stop(sprintf("%s must be NULL or one non-empty path", field), call. = FALSE)
    }
    if (is.na(value) || !nzchar(value)) {
      stop(sprintf("%s must be NULL or one non-empty path", field), call. = FALSE)
    }
    value <- path.expand(value)
    if (identical(field, "stdin")) {
      if (!file.exists(value)) {
        stop(sprintf("Pipeline input does not exist: %s", value), call. = FALSE)
      }
      redirections[[field]] <- normalizePath(value, mustWork = TRUE)
    } else {
      parent <- normalizePath(dirname(value), mustWork = TRUE)
      redirections[[field]] <- file.path(parent, basename(value))
    }
  }
  used_paths <- unlist(redirections, use.names = FALSE)
  if (anyDuplicated(used_paths)) {
    stop("stdin, stdout, and stderr must use different files", call. = FALSE)
  }

  commands <- vapply(stages, `[[`, character(1L), "command")
  arguments <- lapply(stages, `[[`, "args")
  native_commands <- commands
  native_arguments <- arguments
  if (!is.null(cpu_affinity)) {
    if (!is.numeric(cpu_affinity) || length(cpu_affinity) == 0L || anyNA(cpu_affinity)) {
      stop("cpu_affinity must be NULL or a non-empty integer vector", call. = FALSE)
    }
    if (any(cpu_affinity < 0) || any(cpu_affinity != as.integer(cpu_affinity))) {
      stop("cpu_affinity values must be non-negative CPU IDs", call. = FALSE)
    }
    cpu_affinity <- unique(as.integer(cpu_affinity))
    taskset <- unname(Sys.which("taskset"))
    if (!nzchar(taskset)) {
      stop("cpu_affinity requires the Linux taskset executable", call. = FALSE)
    }
    cpu_list <- paste(cpu_affinity, collapse = ",")
    native_commands[] <- taskset
    native_arguments <- Map(
      function(command, args) c("--cpu-list", cpu_list, command, args),
      commands,
      arguments
    )
  }
  native <- .Call(
    RC_exec_pipeline,
    unname(native_commands),
    native_arguments,
    redirections$stdin,
    redirections$stdout,
    redirections$stderr
  )
  result <- data.frame(
    stage = vapply(stages, `[[`, character(1L), "name"),
    command = unname(commands),
    status = native$status,
    signal = native$signal,
    peak_rss_kib = native$stage_peak_rss_kib,
    peak_threads = native$stage_peak_threads,
    stringsAsFactors = FALSE
  )
  attr(result, "wall_seconds") <- native$wall_seconds
  attr(result, "pipeline_peak_rss_kib") <- native$pipeline_peak_rss_kib
  attr(result, "pipeline_peak_threads") <- native$pipeline_peak_threads
  attr(result, "cpu_affinity") <- cpu_affinity

  failed <- which(result$status != 0L)
  if (error_on_status && length(failed) > 0L) {
    summary <- paste0(
      result$stage[failed], " (status ", result$status[failed], ")",
      collapse = ", "
    )
    log_hint <- if (is.null(redirections$stderr)) "" else
      sprintf("; see %s", redirections$stderr)
    stop(sprintf("Pipeline failed: %s%s", summary, log_hint), call. = FALSE)
  }
  result
}
