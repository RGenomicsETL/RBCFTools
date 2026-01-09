# DuckLake helper tests
library(RBCFTools)
library(tinytest)

if (tolower(Sys.info()[["sysname"]]) != "linux") {
  exit_file("DuckLake integration test runs on Linux only")
}
if (!requireNamespace("duckdb", quietly = TRUE)) {
  exit_file("duckdb package not available")
}
if (!requireNamespace("DBI", quietly = TRUE)) {
  exit_file("DBI package not available")
}

# ensure download helpers set exec bit using dummy file
tmp_dir_dl <- tempfile("ducklake_dl_")
dir.create(tmp_dir_dl, recursive = TRUE, showWarnings = FALSE)
dummy <- file.path(tmp_dir_dl, "dummy.bin")
writeBin(as.raw(1:10), dummy)
dummy_url <- paste0("file://", dummy)
minio_dummy <- ducklake_download_minio(dest_dir = tmp_dir_dl, url = dummy_url, filename = "minio_test")
mc_dummy <- ducklake_download_mc(dest_dir = tmp_dir_dl, url = dummy_url, filename = "mc_test")
expect_true(file.exists(minio_dummy))
expect_true(file.exists(mc_dummy))
expect_true(unname(file.access(minio_dummy, mode = 1)) == 0)
expect_true(unname(file.access(mc_dummy, mode = 1)) == 0)

# prefer system binaries if available, else attempt real download
bin_dir <- tempfile("ducklake_bins_")
dir.create(bin_dir, recursive = TRUE, showWarnings = FALSE)
minio_bin <- Sys.which("minio")
if (!nzchar(minio_bin)) {
  minio_bin <- tryCatch(ducklake_download_minio(dest_dir = bin_dir), error = function(e) "")
}
mc_bin <- Sys.which("mc")
if (!nzchar(mc_bin)) {
  mc_bin <- tryCatch(ducklake_download_mc(dest_dir = bin_dir), error = function(e) "")
}

if (!nzchar(minio_bin) || !nzchar(mc_bin)) {
  exit_file("minio/mc binaries not available")
}

data_dir <- tempfile("ducklake_minio_data_")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
port <- sample(19000:19999, 1)
endpoint <- sprintf("127.0.0.1:%d", port)
log_file <- tempfile("ducklake_minio_log_", fileext = ".log")

minio_pid <- system2(
  minio_bin,
  args = c("server", data_dir, "--address", endpoint),
  stdout = log_file,
  stderr = log_file,
  wait = FALSE
)
on.exit({
  if (!is.null(minio_pid) && minio_pid > 0) {
    try(system2("kill", as.character(minio_pid)))
  }
}, add = TRUE)

# give server time to start
Sys.sleep(3)

alias_status <- system2(
  mc_bin,
  args = c("alias", "set", "ducklake_local", paste0("http://", endpoint), "minioadmin", "minioadmin"),
  stdout = TRUE,
  stderr = TRUE
)
if (!is.null(attr(alias_status, "status")) && attr(alias_status, "status") != 0) {
  exit_file("failed to configure mc alias")
}

bucket_status <- system2(
  mc_bin,
  args = c("mb", "ducklake_local/ducklake-test"),
  stdout = TRUE,
  stderr = TRUE
)
if (!is.null(attr(bucket_status, "status")) && attr(bucket_status, "status") != 0) {
  exit_file("failed to create minio bucket")
}

con <- duckdb::dbConnect(duckdb::duckdb(config = list(
  allow_unsigned_extensions = "true",
  enable_external_access = "true"
)))
on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)
try(DBI::dbExecute(con, "INSTALL httpfs"), silent = TRUE)
try(DBI::dbExecute(con, "LOAD httpfs"), silent = TRUE)

# Try local build first, then official install; skip if unavailable
loaded_ducklake <- FALSE
local_ducklake <- file.path(
  normalizePath(file.path("ducklake"), mustWork = FALSE),
  "build/release/extension/ducklake/ducklake.duckdb_extension"
)
if (file.exists(local_ducklake)) {
  res <- try(DBI::dbExecute(con, sprintf("LOAD %s", DBI::dbQuoteString(con, local_ducklake))), silent = TRUE)
  loaded_ducklake <- !inherits(res, "try-error")
}
if (!loaded_ducklake) {
  res <- try(DBI::dbExecute(con, "INSTALL ducklake FROM core_nightly"), silent = TRUE)
  res_load <- try(DBI::dbExecute(con, "LOAD ducklake"), silent = TRUE)
  loaded_ducklake <- !inherits(res_load, "try-error")
}
if (!loaded_ducklake) {
  exit_file("ducklake extension not available; install or provide local build")
}

ducklake_create_s3_secret(
  con = con,
  name = "ducklake_minio",
  key_id = "minioadmin",
  secret = "minioadmin",
  endpoint = endpoint,
  region = "us-east-1",
  use_ssl = FALSE
)

meta_path <- file.path(tempfile("ducklake_meta_"))
data_path <- "s3://ducklake-test"
ducklake_attach(
  con,
  metadata_path = meta_path,
  data_path = data_path,
  alias = "lake",
  extra_options = list(SECRET = "ducklake_minio")
)

vcf_file <- system.file("extdata", "1000G_3samples.vcf.gz", package = "RBCFTools")
if (!file.exists(vcf_file)) {
  exit_file("fixture VCF not found")
}

ducklake_write_variants(
  con,
  table = "lake.variants",
  vcf_path = vcf_file,
  threads = 2
)

variant_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM lake.variants")$n[1]
expect_true(is.numeric(variant_count) && variant_count > 0)
