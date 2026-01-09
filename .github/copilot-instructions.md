# RBCFTools Copilot Instructions

## Project Overview

RBCFTools is an R package that bundles [bcftools](https://samtools.github.io/bcftools/) and [htslib](https://github.com/samtools/htslib) for reading/manipulating VCF/BCF genomic variant files. It provides:
- **Bundled native tools**: bcftools (v1.23), htslib (v1.23), bgzip, tabix—no external installation needed
- **Arrow streaming**: VCF→Arrow conversion via [nanoarrow](https://arrow.apache.org/nanoarrow/) with structured VEP/CSQ/BCSQ/ANN parsing
- **DuckDB integration**: Custom `bcf_reader` extension for direct SQL queries on VCF/BCF files + Parquet export (all VEP/CSQ/BCSQ/ANN fields parsed)
- **Cloud support**: When built with libcurl, reads from S3, GCS, HTTP directly

**Platform**: Unix-like only (Linux, macOS). Windows is NOT supported.

## Versioning

Package version follows `{htslib_version}-{semver}` format:
- **1.23** = bundled htslib/bcftools version (track upstream releases)
- **0.0.0.9000** = package semver (development); increment per standard R conventions

Example: `1.23-0.0.0.9000` means htslib 1.23, package dev version.

When bumping versions:
- Update `DESCRIPTION` Version field
- Add entry to `NEWS.md` (GNU ChangeLog style, see below)

## Code Style & Philosophy

**Keep things simple and robust.** Prefer straightforward solutions over clever ones.

### R Code
- **Never use `cat()`** for output—use `message()` for user feedback, `warning()` for issues
- Use `stop()` with `call. = FALSE` for clean error messages
- Prefer base R over tidyverse dependencies (package is low-dependency)
- Use `sprintf()` for string formatting, not `paste0()` chains

### README.Rmd
- **Sober, professional prose**—this is Rmd that renders to GitHub markdown
- Use proper paragraphs, not bullet-heavy lists
- Code chunks should be minimal and illustrative
- Avoid emoji, excessive formatting, or marketing language
- Output is suppressed warnings where appropriate (`options(warn = -1)`)

### NEWS.md (GNU ChangeLog Style)
- One `# RBCFTools {version}` header per release
- Terse, factual bullet points—no marketing prose
- Group related changes; mention function names
- Development versions use `(development version)` suffix

Example:
```markdown
# RBCFTools 1.23-0.0.1.9000 (development version)

- Add `vcf_count_duckdb()` for fast variant counting via SQL.
- Fix region query parsing for BCF files with CSI index.
- Parallel Parquet export now respects `threads` parameter.
```

## Architecture & Key Components

### 1. Native C Layer (`src/`)
- **R↔C interface**: Standard R `.Call()` interface with `SEXP` types. See [RC_BCFTools.c](../src/RC_BCFTools.c) for version/feature queries.
- **Arrow streaming**: [vcf_arrow_stream.c](../src/vcf_arrow_stream.c) implements VCF→nanoarrow conversion with **VCF spec conformance checks** (mimics htslib's `bcf_hdr_check_sanity()`)—emits R warnings when correcting non-conformant headers (e.g., FORMAT/GQ should be Integer not Float). VEP/CSQ/BCSQ/ANN annotations are parsed into typed list columns using header-declared subfields (all transcripts preserved; first-transcript helper columns exposed in R).
- **Index utilities**: [vcf_index_utils.c](../src/vcf_index_utils.c) checks for .tbi/.csi indexes (works with remote files, custom index paths).

### 2. R API (`R/`)
- **[vcf_arrow.R](../R/vcf_arrow.R)**: `vcf_open_arrow()`, `vcf_to_arrow()`, `vcf_to_parquet()`—streaming VCF reads with nanoarrow integration
- **[vcf_duckdb.R](../R/vcf_duckdb.R)**: Functions to build/load the `bcf_reader` extension, query VCFs via SQL (`vcf_duckdb_connect()`, `vcf_query_duckdb()`)
- **[vcf_parallel.R](../R/vcf_parallel.R)**: Parallel processing utilities using per-chromosome chunking with the `parallel` package
- **[paths.R](../R/paths.R)**: Locate bundled tools (`bcftools_path()`, `bgzip_path()`, `tabix_path()`)

### 3. DuckDB Extension (`inst/duckdb_bcf_reader_extension/`)
- **Standalone C extension**: [bcf_reader.c](../inst/duckdb_bcf_reader_extension/bcf_reader.c) plus [vep_parser.c](../inst/duckdb_bcf_reader_extension/vep_parser.c) provide `bcf_read()` SQL function; sources are self-contained (do not include package `src/` files).
- **Build modes**: Uses package htslib (`make RBCFTOOLS_HTSLIB=1`) or system htslib via pkg-config.
- **Spec compliance**: Matches nanoarrow's VCF validation, logs header corrections. Parses VEP/CSQ/BCSQ/ANN fields into typed list columns named after the header key; all transcripts retained by default.
- **Features**: Region filtering with .tbi/.csi indexes, projection pushdown (e.g., `SELECT COUNT(*)`), Parquet export, optional benchmark rendering (`make -C inst/duckdb_bcf_reader_extension benchmark`).

### 4. Bundled Native Tools (`inst/bcftools/`, `inst/htslib/`)
Built during package installation by [configure](../configure) script. Libraries live in `inst/{bcftools,htslib}/lib/` with RPATH set for runtime linking.



## Build System

### Installation Flow
1. **[configure](../configure)**: Auto-detects dependencies (GSL, libcurl, libdeflate, pkg-config), compiles htslib + bcftools from `src/bcftools-1.23/`
2. **[src/Makevars.in](../src/Makevars.in)**: Template expanded by configure. Sets RPATH (`@loader_path` on macOS, `$ORIGIN` on Linux) for bundled libs
3. **[src/install.libs.R](../src/install.libs.R)**: Copies compiled libs to `inst/{bcftools,htslib}/` after build

### Key Make Targets ([Makefile](../Makefile))
```bash
make build        # Build package tarball
make check        # R CMD check --as-cran
make install      # Full configure + install
make install2     # Skip configure (fast iterative dev)
make test-dev     # Run tinytest suite after install2

# Docker
make docker-build-release  # Install from R-universe
make docker-build-dev      # Install from local source (COPY .)
```

### Quick Iteration Workflow
```bash
# After C changes (requires full configure)
make install

# After R changes only (faster, skips configure)
make install2
make test-dev
```

## Testing Strategy (`inst/tinytest/`)

Uses [tinytest](https://github.com/markvanderloo/tinytest) (lightweight, no heavy dependencies). Key files:
- **[test_vcf_arrow.R](../inst/tinytest/test_vcf_arrow.R)**: Arrow stream conversion, nanoarrow integration
- **[test_vcf_duckdb.R](../inst/tinytest/test_vcf_duckdb.R)**: DuckDB extension build, SQL queries, Parquet export
- **[test_parallel.R](../inst/tinytest/test_parallel.R)**: Parallel processing with per-chromosome chunks
- **[test_bcftools_comparison.R](../inst/tinytest/test_bcftools_comparison.R)**: Validate Arrow output against bcftools CLI

**Run tests**:
```bash
R -e 'tinytest::test_package("RBCFTools")'       # All tests
R -e 'library(RBCFTools); tinytest::run_test_dir("inst/tinytest")'  # After install2
```

**Test files** in `inst/extdata/`:
- `1000G_3samples.vcf.gz` (small multi-sample file)
- `test_format_simple.vcf` (uncompressed, for basic parsing tests)

## Critical Conventions

### VCF Spec Conformance
Both nanoarrow and DuckDB implementations **auto-correct** non-conformant headers (e.g., FORMAT/AD should be Number=R, FORMAT/GQ should be Type=Integer) and emit warnings/logs. This mimics htslib's `bcf_hdr_check_sanity()`. **Never silently fail** on spec violations—log and correct.

### Remote File Access
**Always call `setup_hts_env()`** before reading S3/GCS/HTTP files—it sets `HTS_PATH` for htslib's remote file plugin. Example in [vcf_arrow.R#L73-74](../R/vcf_arrow.R#L73-L74).

### Index Detection
- **VCF.GZ**: Try .tbi first, then .csi
- **BCF**: Use .csi only
- **Custom indexes**: Use `index=` parameter or htslib `##idx##` syntax (`file.vcf.gz##idx##custom.tbi`)

### RPATH Setup
C code must find bundled shared libs at runtime. [Makevars.in](../src/Makevars.in#L8-L15) uses platform-specific RPATH:
- **macOS**: `-Wl,-rpath,@loader_path/../{bcftools,htslib}/lib`
- **Linux**: `-Wl,--disable-new-dtags -Wl,-rpath,'$$ORIGIN/../{bcftools,htslib}/lib'`

Post-install, `install_name_tool` fixes macOS dylib references ([Makevars.in#L34-L37](../src/Makevars.in#L34-L37)).

### Parallel Processing Pattern
See [vcf_parallel.R](../R/vcf_parallel.R). Typical flow:
1. Check index with `vcf_has_index()`
2. Get contigs via `vcf_get_contigs()`
3. Use `parallel::mclapply()` or `parallel::parLapply()` to process per-chromosome
4. Combine results (e.g., `do.call(rbind, ...)` for data frames)

### VEP/SnpEff/ANNOVAR Annotations

- **Status**: INFO/CSQ (VEP), INFO/ANN (SnpEff), and INFO/BCSQ (bcftools/csq) are parsed by default in Arrow streams and DuckDB. Column names match the header key (no `VEP_` prefix). All transcripts are retained as list-typed columns; Arrow exposes first-transcript helper columns for convenience.
- **Type mapping**: Header-declared subfields drive schema; common AF/AC/AL* fields become float/int lists. Unknown fields fall back to VARCHAR.
- **Test files**: `inst/extdata/test_vep.vcf`, `test_vep_types.vcf`, `test_vep_snpeff.vcf` cover multiple formats. Tinytests assert schema and multi-transcript preservation.

## Common Tasks

### Adding a New C Function
1. Declare in `src/*.c` (e.g., `SEXP RC_my_function(SEXP arg)`)
2. Register in [src/init.c](../src/init.c) via `R_CallMethodDef`
3. Add R wrapper in `R/*.R` using `.Call(RC_my_function, arg, PACKAGE = "RBCFTools")`
4. Rebuild: `make install2` (if no new C files) or `make install` (if new files)

### Building DuckDB Extension
```R
# From R session
library(RBCFTools)
build_dir <- tempdir()
bcf_reader_copy_source(build_dir)  # Copy sources (installed pkg is read-only)
ext_path <- bcf_reader_build(build_dir)

# Or use Makefile directly
cd inst/duckdb_bcf_reader_extension
make RBCFTOOLS_HTSLIB=1  # Use package htslib (self-contained build)
```

### Debugging Remote File Access
Set `HTS_DEBUG=1` environment variable to see htslib's remote file plugin activity:
```R
Sys.setenv(HTS_DEBUG = "1")
setup_hts_env()
vcf_open_arrow("s3://bucket/file.vcf.gz")
```

### Docker Testing
```bash
# Build and run tests in container
docker build -f Dockerfile .

# Interactive dev container
docker build --build-arg BUILD_MODE=develop -f Dockerfile -t rbcftools:dev .
docker run -it rbcftools:dev R
```

## Documentation & Resources

- **README**: [README.md](../README.md) (generated from [README.Rmd](../README.Rmd) via `make rdm`)
- **VCF Specification**: https://samtools.github.io/hts-specs/VCFv4.3.pdf
- **bcftools manual**: https://samtools.github.io/bcftools/bcftools.html
- **DuckDB extension API**: https://duckdb.org/docs/extensions/overview.html
- **nanoarrow docs**: https://arrow.apache.org/nanoarrow/latest/

## Anti-Patterns

❌ **Don't** use `cat()` in R code—use `message()` or `warning()`  
❌ **Don't** use sequential `.Call()` for batch operations—prefer vectorized C code  
❌ **Don't** assume Windows support—scripts must check `OS_type: unix`  
❌ **Don't** link DuckDB extension against package `src/` objects—keep it self-contained and point only to htslib  
❌ **Don't** forget to add test coverage for new features in `inst/tinytest/`  
❌ **Don't** modify generated files (README.md, man/*.Rd)—edit sources (README.Rmd, roxygen2 comments)  
❌ **Don't** add heavy dependencies—nanoarrow is the exception; avoid the arrow R package in core paths

## Known Limitations

- **Memory copies**: Arrow streaming involves C-level copies; Parquet export adds IPC serialization overhead
- **No Windows support**: htslib build system is Unix-only
- **DuckDB extension unsigned**: Requires `allow_unsigned_extensions` config
