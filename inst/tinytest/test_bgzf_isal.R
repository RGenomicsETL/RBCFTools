library(RBCFTools)
library(tinytest)

# HTSlib reports ISA-L in its feature string exactly when its configure
# recorded -lisal for static linking.
uses_isal <- grepl("-lisal", RBCFTools:::htslib_static_deps(), fixed = TRUE)
expect_equal(
  grepl("isal=yes", htslib_feature_string(), fixed = TRUE),
  uses_isal,
  info = "isal=yes in the feature string should match -lisal in htslib.pc"
)

# BGZF round trips at the ISA-L levels (1 and 2) and a libdeflate level (6).
# The input spans several BGZF blocks and ends with incompressible bytes.
bgzip <- bgzip_path()
if (nzchar(bgzip)) {
  set.seed(1908L)
  input <- tempfile(fileext = ".txt")
  n <- 20000L
  writeLines(
    sprintf("chr1\t%d\t.\tA\tG\t%d\tPASS\tDP=%d", seq_len(n), seq_len(n) %% 60L, seq_len(n) %% 97L),
    input
  )
  con <- file(input, "ab")
  writeBin(as.raw(sample(0:255, 70000L, replace = TRUE)), con)
  close(con)
  original <- readBin(input, "raw", file.size(input))

  for (level in c("1", "2", "6")) {
    compressed <- tempfile(fileext = ".gz")
    restored <- tempfile()
    expect_equal(
      system2(bgzip, c("-l", level, "-c", shQuote(input)), stdout = compressed),
      0L,
      info = paste("bgzip -l", level)
    )
    expect_equal(
      system2(bgzip, c("-d", "-c", shQuote(compressed)), stdout = restored),
      0L,
      info = paste("bgzip -d after -l", level)
    )
    expect_identical(
      readBin(restored, "raw", file.size(restored)),
      original,
      info = paste("BGZF round trip at level", level)
    )
    unlink(c(compressed, restored))
  }
  unlink(input)
}
