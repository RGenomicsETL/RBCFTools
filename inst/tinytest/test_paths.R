# Test path functions

# Test bcftools_path returns a string
expect_true(
    is.character(bcftools_path()),
    info = "bcftools_path() should return a character"
)

# Test bcftools_bin_dir returns a string
expect_true(
    is.character(bcftools_bin_dir()),
    info = "bcftools_bin_dir() should return a character"
)

# Test bcftools_plugins_dir returns a string
expect_true(
    is.character(bcftools_plugins_dir()),
    info = "bcftools_plugins_dir() should return a character"
)

# Test htslib_bin_dir returns a string
expect_true(
    is.character(htslib_bin_dir()),
    info = "htslib_bin_dir() should return a character"
)

# Test individual htslib tool paths
expect_true(
    is.character(bgzip_path()),
    info = "bgzip_path() should return a character"
)

expect_true(
    is.character(tabix_path()),
    info = "tabix_path() should return a character"
)

expect_true(
    is.character(htsfile_path()),
    info = "htsfile_path() should return a character"
)

expect_true(
    is.character(annot_tsv_path()),
    info = "annot_tsv_path() should return a character"
)

expect_true(
    is.character(ref_cache_path()),
    info = "ref_cache_path() should return a character"
)

# Test tool listing functions return character vectors
expect_true(
    is.character(bcftools_tools()),
    info = "bcftools_tools() should return a character vector"
)

expect_true(
    is.character(htslib_tools()),
    info = "htslib_tools() should return a character vector"
)

# If package is properly installed, paths should exist
if (nchar(bcftools_path()) > 0) {
    expect_true(
        file.exists(bcftools_path()),
        info = "bcftools executable should exist when path is non-empty"
    )
}

if (nchar(bgzip_path()) > 0) {
    expect_true(
        file.exists(bgzip_path()),
        info = "bgzip executable should exist when path is non-empty"
    )
}

if (nchar(tabix_path()) > 0) {
    expect_true(
        file.exists(tabix_path()),
        info = "tabix executable should exist when path is non-empty"
    )
}

# Test that bcftools_tools contains expected tools when available
tools <- bcftools_tools()
if (length(tools) > 0) {
    expect_true(
        "bcftools" %in% tools,
        info = "bcftools should be in bcftools_tools()"
    )
}

# Test that htslib_tools contains expected tools when available
hts_tools <- htslib_tools()
if (length(hts_tools) > 0) {
    expected_hts_tools <- c("bgzip", "tabix", "htsfile")
    expect_true(
        all(expected_hts_tools %in% hts_tools),
        info = "Expected htslib tools should be in htslib_tools()"
    )
}
