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
if (!requireNamespace("processx", quietly = TRUE)) {
  exit_file("processx package not available")
}

# ensure download helpers set exec bit using dummy file
tmp_dir_dl <- tempfile("ducklake_dl_")
dir.create(tmp_dir_dl, recursive = TRUE, showWarnings = FALSE)
dummy <- file.path(tmp_dir_dl, "dummy.bin")
writeBin(as.raw(1:10), dummy)
dummy_url <- paste0("file://", dummy)
minio_dummy <- ducklake_download_minio(
  dest_dir = tmp_dir_dl,
  url = dummy_url,
  filename = "minio_test"
)
mc_dummy <- ducklake_download_mc(
  dest_dir = tmp_dir_dl,
  url = dummy_url,
  filename = "mc_test"
)
expect_true(file.exists(minio_dummy))
expect_true(file.exists(mc_dummy))
expect_true(unname(file.access(minio_dummy, mode = 1)) == 0)
expect_true(unname(file.access(mc_dummy, mode = 1)) == 0)

# prefer system binaries if available, else attempt real download
bin_dir <- tempfile("ducklake_bins_")
dir.create(bin_dir, recursive = TRUE, showWarnings = FALSE)
minio_bin <- Sys.which("minio")
if (!nzchar(minio_bin)) {
  minio_bin <- tryCatch(
    ducklake_download_minio(dest_dir = bin_dir),
    error = function(e) ""
  )
}
mc_bin <- Sys.which("mc")
if (!nzchar(mc_bin)) {
  mc_bin <- tryCatch(
    ducklake_download_mc(dest_dir = bin_dir),
    error = function(e) ""
  )
}

if (!nzchar(minio_bin) || !nzchar(mc_bin)) {
  exit_file("minio/mc binaries not available")
}

data_dir <- tempfile("ducklake_minio_data_")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
port <- sample(19000:19999, 1)
endpoint <- sprintf("127.0.0.1:%d", port)
log_file <- tempfile("ducklake_minio_log_", fileext = ".log")

minio_proc <- processx::process$new(
  minio_bin,
  c("server", data_dir, "--address", endpoint),
  stdout = log_file,
  stderr = log_file,
  supervise = TRUE
)
minio_pid <- minio_proc$get_pid()
on.exit(
  {
    if (!is.null(minio_proc) && minio_proc$is_alive()) {
      minio_proc$kill()
    }
  },
  add = TRUE
)

# Wait for MinIO server to be ready
max_retries <- 10
for (i in 1:max_retries) {
  Sys.sleep(2)

  # Try to remove existing alias first
  tryCatch(
    processx::run(
      mc_bin,
      c("alias", "remove", "ducklake_local"),
      error_on_status = FALSE
    ),
    error = function(e) NULL
  )

  alias_res <- tryCatch(
    processx::run(
      mc_bin,
      c(
        "alias",
        "set",
        "ducklake_local",
        paste0("http://", endpoint),
        "minioadmin",
        "minioadmin"
      ),
      error_on_status = FALSE
    ),
    error = function(e) list(exit_code = -1, stderr = conditionMessage(e))
  )

  # Check if alias was set successfully
  if (
    !is.null(alias_res) &&
      is.list(alias_res) &&
      !is.null(alias_res$exit_code) &&
      is.numeric(alias_res$exit_code) &&
      alias_res$exit_code == 0
  ) {
    break
  }

  if (i == max_retries) {
    error_msg <- if (!is.null(alias_res) && !is.null(alias_res$stderr)) {
      alias_res$stderr
    } else {
      "Max retries reached"
    }
    exit_file(sprintf(
      "failed to configure mc alias after %d attempts: %s",
      max_retries,
      error_msg
    ))
  }
}

bucket_res <- tryCatch(
  processx::run(
    mc_bin,
    c("mb", "ducklake_local/ducklake-test"),
    error_on_status = FALSE
  ),
  error = function(e) list(exit_code = -1, stderr = conditionMessage(e))
)

# Check result safely
if (
  is.null(bucket_res) ||
    !is.list(bucket_res) ||
    is.null(bucket_res$exit_code) ||
    !is.numeric(bucket_res$exit_code) ||
    bucket_res$exit_code != 0
) {
  error_msg <- if (!is.null(bucket_res) && !is.null(bucket_res$stderr)) {
    bucket_res$stderr
  } else {
    "unknown error"
  }
  exit_file(sprintf("failed to create minio bucket: %s", error_msg))
}
# temporary duckdb file
tmp_duckdb_file <- tempfile(fileext = ".duckdb")

con <- DBI::dbConnect(duckdb::duckdb(tmp_duckdb_file),
  allow_unsigned_extensions = "true",
  enable_external_access = "true"
)
on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)
try(DBI::dbExecute(con, "INSTALL httpfs"), silent = TRUE)
try(DBI::dbExecute(con, "LOAD httpfs"), silent = TRUE)

# Install and load DuckLake from official extensions
DBI::dbExecute(con, "INSTALL ducklake FROM core_nightly")
DBI::dbExecute(con, "LOAD ducklake")

message("Creating secret for MinIO access")
ducklake_create_s3_secret(
  con = con,
  name = "ducklake_minio",
  key_id = "minioadmin",
  secret = "minioadmin",
  endpoint = endpoint,
  region = "us-east-1",
  use_ssl = FALSE
)

# Test the new abstracted catalog connection system
meta_path <- file.path(tempfile("ducklake_meta_"))
data_path <- "s3://ducklake-test"

# Test 1: Direct DuckDB backend connection
ducklake_connect_catalog(
  con,
  backend = "duckdb",
  connection_string = meta_path,
  data_path = data_path,
  alias = "lake"
)

# Test 2: Create and use a secret
meta_path2 <- file.path(tempfile("ducklake_meta2_"))
ducklake_create_catalog_secret(
  con,
  name = "test_ducklake_secret",
  backend = "duckdb",
  connection_string = meta_path2,
  data_path = data_path,
  metadata_parameters = list()
)

# Test 3: Connect using secret
ducklake_connect_catalog(
  con,
  secret_name = "test_ducklake_secret",
  alias = "lake_secret"
)

# Test 4: List secrets
secrets <- ducklake_list_secrets(con)
expect_true("test_ducklake_secret" %in% secrets$name)

vcf_file <- system.file(
  "extdata",
  "1000G_3samples.vcf.gz",
  package = "RBCFTools"
)
if (!file.exists(vcf_file)) {
  exit_file("fixture VCF not found")
}

# Build bcf_reader extension for VCF loading
ext_path <- bcf_reader_build(tempdir())
ducklake_load_vcf(
  con,
  table = "lake.variants",
  vcf_path = vcf_file,
  extension_path = ext_path,
  threads = 2
)

variant_count <- DBI::dbGetQuery(
  con,
  "SELECT COUNT(*) AS n FROM lake.variants"
)$n[1]
expect_true(is.numeric(variant_count) && variant_count > 0)

# Test 5: Clean up secret
ducklake_drop_secret(con, "test_ducklake_secret")
secrets_after <- ducklake_list_secrets(con)
expect_true(!"test_ducklake_secret" %in% secrets_after$name)
