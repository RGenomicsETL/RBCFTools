library(RBCFTools)
library(tinytest)

rbcftools_dll <- getLoadedDLLs()[["RBCFTools"]][["path"]]
expect_true(file.exists(rbcftools_dll))
expect_equal(htslib_version(), "1.24")

if (identical(Sys.info()[["sysname"]], "Linux")) {
  readelf <- Sys.which("readelf")
  if (nzchar(readelf)) {
    dependencies <- system2(
      readelf,
      c("-d", shQuote(rbcftools_dll)),
      stdout = TRUE,
      stderr = TRUE
    )
    expect_true(any(grepl("Shared library: [libhts.so.RBCFTools.1.24]", dependencies, fixed = TRUE)))
    expect_false(any(grepl("Shared library: [libhts.so.3]", dependencies, fixed = TRUE)))

    versions <- system2(
      readelf,
      c("--version-info", shQuote(rbcftools_dll)),
      stdout = TRUE,
      stderr = TRUE
    )
    expect_true(any(grepl("Name: RBCFTOOLS_HTSLIB_", versions, fixed = TRUE)))
    expect_false(any(grepl("Name: HTSLIB_", versions, fixed = TRUE)))

    plugins <- list.files(htslib_plugins_dir(), pattern = "[.]so$", full.names = TRUE)
    for (plugin in plugins) {
      dependencies <- system2(
        readelf,
        c("-d", shQuote(plugin)),
        stdout = TRUE,
        stderr = TRUE
      )
      expect_true(any(grepl("Shared library: [libhts.so.RBCFTools.1.24]", dependencies, fixed = TRUE)))
      expect_false(any(grepl("Shared library: [libhts.so.3]", dependencies, fixed = TRUE)))
    }
  }
}

if (identical(Sys.info()[["sysname"]], "Darwin")) {
  otool <- Sys.which("otool")
  if (nzchar(otool)) {
    dependencies <- system2(
      otool,
      c("-L", shQuote(rbcftools_dll)),
      stdout = TRUE,
      stderr = TRUE
    )
    expect_true(any(grepl("libhts.RBCFTools.1.24.dylib", dependencies, fixed = TRUE)))
    expect_false(any(grepl("libhts.3.dylib", dependencies, fixed = TRUE)))
  }
}
