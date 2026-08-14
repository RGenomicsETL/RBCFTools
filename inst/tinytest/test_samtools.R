library(RBCFTools)
library(tinytest)

expect_true(
  is.character(samtools_path()) && length(samtools_path()) == 1L,
  info = "samtools_path() should return one character string"
)
expect_true(
  is.character(samtools_bin_dir()) && length(samtools_bin_dir()) == 1L,
  info = "samtools_bin_dir() should return one character string"
)
expect_true(
  is.character(samtools_tools()),
  info = "samtools_tools() should return a character vector"
)

samtools <- samtools_path()
if (nchar(samtools) > 0L) {
  expect_true(
    file.exists(samtools) && file.access(samtools, mode = 1L) == 0L,
    info = "the bundled Samtools executable should exist and be executable"
  )
  expect_true(
    "samtools" %in% samtools_tools(),
    info = "samtools_tools() should list the Samtools executable"
  )
  expect_identical(
    samtools_version(),
    "1.24",
    info = "the bundled Samtools version should match the vendored release"
  )

  version_output <- system2(
    samtools,
    "--version",
    stdout = TRUE,
    stderr = TRUE
  )
  expect_true(
    any(version_output == paste("Using htslib", htslib_version())),
    info = "Samtools should report the package's canonical HTSlib version"
  )
} else {
  expect_true(
    is.na(samtools_version()),
    info = "samtools_version() should be NA when the executable is unavailable"
  )
}
