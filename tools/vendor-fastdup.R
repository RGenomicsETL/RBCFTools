#!/usr/bin/env Rscript

all_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", all_args, value = TRUE)
if (length(file_arg) != 1L) stop("Run this script with Rscript", call. = FALSE)
script <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
root <- normalizePath(file.path(dirname(script), ".."), mustWork = TRUE)
lock <- read.dcf(file.path(root, "tools", "fastdup-upstream.dcf"))[1L, ]

sha256_file <- function(path) {
  sha256sum <- Sys.which("sha256sum")
  if (nzchar(sha256sum)) {
    return(strsplit(system2(sha256sum, path, stdout = TRUE), "[[:space:]]+")[[1L]][1L])
  }
  shasum <- Sys.which("shasum")
  if (!nzchar(shasum)) stop("sha256sum or shasum is required", call. = FALSE)
  strsplit(system2(shasum, c("-a", "256", path), stdout = TRUE), "[[:space:]]+")[[1L]][1L]
}

archive <- tempfile(fileext = ".tar.gz")
extract_dir <- tempfile("fastdup-source-")
on.exit(unlink(c(archive, extract_dir), recursive = TRUE, force = TRUE), add = TRUE)
dir.create(extract_dir)
download.file(lock[["ArchiveURL"]], archive, mode = "wb", quiet = TRUE)
actual_sha <- sha256_file(archive)
if (!identical(actual_sha, lock[["ArchiveSHA256"]])) {
  stop(sprintf("FastDup archive SHA-256 mismatch: expected %s, got %s",
               lock[["ArchiveSHA256"]], actual_sha), call. = FALSE)
}

utils::untar(archive, exdir = extract_dir)
roots <- list.dirs(extract_dir, full.names = TRUE, recursive = FALSE)
if (length(roots) != 1L) stop("FastDup archive must contain one root directory", call. = FALSE)
source_dir <- roots[[1L]]
unlink(
  file.path(
    source_dir,
    c("ext/htslib", "test", "ext/klib/test", "ext/klib/lua", "ext/klib/cpp")
  ),
  recursive = TRUE,
  force = TRUE
)

patcher <- file.path(root, "tools", "apply-fastdup-patches.sh")
status <- system2(patcher, source_dir)
if (status != 0L) stop("Unable to apply the FastDup overlay", call. = FALSE)

target <- file.path(root, lock[["VendoredSource"]])
stage <- paste0(target, ".stage-", Sys.getpid())
backup <- paste0(target, ".backup-", Sys.getpid())
on.exit(unlink(c(stage, backup), recursive = TRUE, force = TRUE), add = TRUE)
dir.create(stage, recursive = TRUE)
source_files <- list.files(source_dir, all.files = TRUE, no.. = TRUE, full.names = TRUE)
if (!all(file.copy(source_files, stage, recursive = TRUE, copy.mode = TRUE))) {
  stop("Unable to stage FastDup sources", call. = FALSE)
}

receipt <- c(
  sprintf("Component: %s", lock[["Component"]]),
  sprintf("Version: %s", lock[["Version"]]),
  sprintf("Repository: %s", lock[["Repository"]]),
  sprintf("Commit: %s", lock[["Commit"]]),
  sprintf("Date: %s", lock[["Date"]]),
  sprintf("ArchiveURL: %s", lock[["ArchiveURL"]]),
  sprintf("ArchiveSHA256: %s", lock[["ArchiveSHA256"]]),
  sprintf("PatchDirectory: %s", lock[["PatchDirectory"]]),
  sprintf("Patches: %s", lock[["Patches"]]),
  "VendoredScope: FastDup sources and required bundled header libraries; upstream HTSlib and test data omitted",
  "HTSlib: src/bcftools-1.24/htslib-1.24 (configured once by RBCFTools)",
  sprintf("VendoredAtUTC: %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  sprintf("License: %s", lock[["License"]])
)
writeLines(receipt, file.path(stage, "RBCFTOOLS_VENDOR.dcf"))

if (dir.exists(target) && !file.rename(target, backup)) {
  stop("Unable to move the previous FastDup source aside", call. = FALSE)
}
if (!file.rename(stage, target)) {
  if (dir.exists(backup)) file.rename(backup, target)
  stop("Unable to install the staged FastDup source", call. = FALSE)
}
unlink(backup, recursive = TRUE, force = TRUE)
cat(sprintf("Vendored FastDup %s at %s\n", lock[["Version"]], target))
