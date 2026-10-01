library(RBCFTools)
library(tinytest)

if (!requireNamespace("Rduckhts", quietly = TRUE)) {
  exit_file("Rduckhts is not installed")
}
if (!requireNamespace("processx", quietly = TRUE)) {
  exit_file("processx is not installed")
}

work_dir <- tempfile("htslib-coexistence-")
dir.create(work_dir)
script <- file.path(work_dir, "read-vcf.R")
script_code <- substitute({
  .libPaths(library_paths)
  args <- commandArgs(trailingOnly = TRUE)
  order <- args[[1L]]
  vcf <- args[[2L]]
  con <- NULL
  if (order %in% c("rbcftools", "rbcftools-first")) library(RBCFTools)
  if (order != "rbcftools") {
    library(Rduckhts)
    con <- rduckhts_connect()
  }
  if (order == "duckhts-first") library(RBCFTools)
  result <- list()
  if (order != "duckhts") {
    result$rbcftools <- list(
      version = htslib_version(),
      rows = nrow(vcf_to_arrow(vcf, as = "data.frame")),
      capabilities = htslib_capabilities()
    )
  }
  if (!is.null(con)) {
    result$duckhts <- list(
      version = rduckhts_htslib_version(con),
      rows = DBI::dbGetQuery(con, paste0(
        "SELECT count(*) AS n FROM read_bcf(", DBI::dbQuoteString(con, vcf), ")"
      ))$n
    )
    DBI::dbDisconnect(con, shutdown = TRUE)
  }
  saveRDS(result, args[[3L]])
}, list(library_paths = .libPaths()))
writeLines(deparse(script_code), script)

vcf <- system.file("extdata", "1000G_3samples.vcf.gz", package = "RBCFTools")
orders <- c("rbcftools", "duckhts", "rbcftools-first", "duckhts-first")
results <- setNames(vector("list", length(orders)), orders)
for (order in orders) {
  output <- file.path(work_dir, paste0(order, ".rds"))
  run <- processx::run(
    file.path(R.home("bin"), "Rscript"),
    c("--vanilla", script, order, vcf, output),
    timeout = 120000,
    error_on_status = FALSE
  )
  expect_equal(run$status, 0L, info = paste(order, run$stderr))
  if (run$status == 0L) {
    results[[order]] <- readRDS(output)
    for (reader in names(results[[order]])) {
      expect_true(results[[order]][[reader]]$rows == 11L, info = paste(order, reader))
      expect_true(nzchar(results[[order]][[reader]]$version), info = paste(order, reader))
    }
  }
}

for (order in c("rbcftools-first", "duckhts-first")) {
  if (!is.null(results[[order]])) {
    expect_equal(results[[order]]$rbcftools, results$rbcftools$rbcftools, info = order)
    expect_equal(results[[order]]$duckhts, results$duckhts$duckhts, info = order)
  }
}
unlink(work_dir, recursive = TRUE)
