files <- Sys.glob(paste0("*", SHLIB_EXT))
dest <- file.path(R_PACKAGE_DIR, paste0("libs", R_ARCH))
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
file.copy(files, dest, overwrite = TRUE)

# Copy bcftools header files to R_PACKAGE_DIR/bcftools/include (recursive)
headers <- list.files(
  "bcftools-1.23/",
  pattern = "\\.h$",
  full.names = TRUE,
  recursive = TRUE
)

headers <- headers[!grepl("htslib-1.23/", headers)] # Exclude htslib headers
headers_dest <- file.path(R_PACKAGE_DIR, "bcftools/include")
for (h in headers) {
  # Get relative path from bcftools-1.23/
  rel_path <- sub("^bcftools-1.23/", "", h)
  dest_file <- file.path(headers_dest, rel_path)
  dir.create(dirname(dest_file), recursive = TRUE, showWarnings = FALSE)
  file.copy(h, dest_file, overwrite = TRUE)
}
