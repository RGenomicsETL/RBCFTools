# Test using extdata BCF file

# Get path to test BCF file
bcf_file <- system.file(
  "extdata",
  "gnomad.exomes.r2.0.1.sites.bcf",
  package = "RBCFTools"
)

# Test that the file exists
expect_true(
  file.exists(bcf_file),
  info = "Test BCF file should exist in inst/extdata"
)

# Test htsfile can identify the BCF format
htsfile_exe <- htsfile_path()
if (nchar(htsfile_exe) > 0 && file.exists(htsfile_exe)) {
  result <- system2(htsfile_exe, args = bcf_file, stdout = TRUE, stderr = TRUE)
  expect_true(
    any(grepl("BCF|VCF", result, ignore.case = TRUE)),
    info = "htsfile should identify file as BCF/VCF format"
  )
}

# Test bcftools can read the BCF file header
bcftools_exe <- bcftools_path()
if (nchar(bcftools_exe) > 0 && file.exists(bcftools_exe)) {
  # Test view -h (header only)
  result <- system2(
    bcftools_exe,
    args = c("view", "-h", bcf_file),
    stdout = TRUE,
    stderr = TRUE
  )
  expect_true(
    length(result) > 0,
    info = "bcftools view -h should return header lines"
  )
  expect_true(
    any(grepl("^##fileformat=VCF", result)),
    info = "BCF header should contain VCF fileformat line"
  )

  # Test query to extract basic info
  result <- system2(
    bcftools_exe,
    args = c("query", "-l", bcf_file),
    stdout = TRUE,
    stderr = TRUE
  )
  expect_true(
    is.character(result),
    info = "bcftools query -l should return sample names"
  )

  # Test stats command
  result <- system2(
    bcftools_exe,
    args = c("stats", bcf_file),
    stdout = TRUE,
    stderr = TRUE
  )
  expect_true(
    any(grepl("^SN", result)),
    info = "bcftools stats should return summary numbers"
  )
}
