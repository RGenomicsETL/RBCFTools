# RBCFTools Copilot Instructions

## Project Overview

RBCFTools is an R package that bundles
[bcftools](https://samtools.github.io/bcftools/) and
[htslib](https://github.com/samtools/htslib) for reading/manipulating
VCF/BCF genomic variant files. It provides: - **Bundled native tools**:
bcftools (v1.23), htslib (v1.23), bgzip, tabix—no external installation
needed - **Arrow streaming**: Experimental VCF→Arrow conversion via
[nanoarrow](https://arrow.apache.org/nanoarrow/) (zero-copy, no heavy
arrow dependency) - **DuckDB integration**: Custom `bcf_reader`
extension for direct SQL queries on VCF files + Parquet export - **Cloud
support**: When built with libcurl, reads from S3, GCS, HTTP directly

**Platform**: Unix-like only (Linux, macOS). Windows is NOT supported.

## Versioning

Package version follows `{htslib_version}-{semver}` format: - **1.23** =
bundled htslib/bcftools version (track upstream releases) -
**0.0.0.9000** = package semver (development); increment per standard R
conventions

Example: `1.23-0.0.0.9000` means htslib 1.23, package dev version.

When bumping versions: - Update `DESCRIPTION` Version field - Add entry
to `NEWS.md` (GNU ChangeLog style, see below)

## Code Style & Philosophy

**Keep things simple and robust.** Prefer straightforward solutions over
clever ones.

### R Code

- **Never use [`cat()`](https://rdrr.io/r/base/cat.html)** for
  output—use [`message()`](https://rdrr.io/r/base/message.html) for user
  feedback, [`warning()`](https://rdrr.io/r/base/warning.html) for
  issues
- Use [`stop()`](https://rdrr.io/r/base/stop.html) with `call. = FALSE`
  for clean error messages
- Prefer base R over tidyverse dependencies (package is low-dependency)
- Use [`sprintf()`](https://rdrr.io/r/base/sprintf.html) for string
  formatting, not [`paste0()`](https://rdrr.io/r/base/paste.html) chains

### README.Rmd

- **Sober, professional prose**—this is Rmd that renders to GitHub
  markdown
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

``` markdown
# RBCFTools 1.23-0.0.1.9000 (development version)

- Add `vcf_count_duckdb()` for fast variant counting via SQL.
- Fix region query parsing for BCF files with CSI index.
- Parallel Parquet export now respects `threads` parameter.
```

## Architecture & Key Components

### 1. Native C Layer (`src/`)

- **R↔︎C interface**: Standard R
  [`.Call()`](https://rdrr.io/r/base/CallExternal.html) interface with
  `SEXP` types. See
  [RC_BCFTools.c](https://rgenomicsetl.github.io/src/RC_BCFTools.c) for
  version/feature queries
- **Arrow streaming**:
  [vcf_arrow_stream.c](https://rgenomicsetl.github.io/src/vcf_arrow_stream.c)
  implements VCF→nanoarrow conversion with **VCF spec conformance
  checks** (mimics htslib’s `bcf_hdr_check_sanity()`)—emits R warnings
  when correcting non-conformant headers (e.g., FORMAT/GQ should be
  Integer not Float)
- **Index utilities**:
  [vcf_index_utils.c](https://rgenomicsetl.github.io/src/vcf_index_utils.c)
  checks for .tbi/.csi indexes (works with remote files, custom index
  paths)

### 2. R API (`R/`)

- **[vcf_arrow.R](https://rgenomicsetl.github.io/R/vcf_arrow.R)**:
  [`vcf_open_arrow()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_open_arrow.md),
  [`vcf_to_arrow()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_arrow.md),
  [`vcf_to_parquet()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_parquet.md)—streaming
  VCF reads with nanoarrow integration
- **[vcf_duckdb.R](https://rgenomicsetl.github.io/R/vcf_duckdb.R)**:
  Functions to build/load the `bcf_reader` extension, query VCFs via SQL
  ([`vcf_duckdb_connect()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_duckdb_connect.md),
  [`vcf_query_duckdb()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_query_duckdb.md))
- **[vcf_parallel.R](https://rgenomicsetl.github.io/R/vcf_parallel.R)**:
  Parallel processing utilities using per-chromosome chunking with the
  `parallel` package
- **[paths.R](https://rgenomicsetl.github.io/R/paths.R)**: Locate
  bundled tools
  ([`bcftools_path()`](https://rgenomicsetl.github.io/RBCFTools/reference/bcftools_path.md),
  [`bgzip_path()`](https://rgenomicsetl.github.io/RBCFTools/reference/bgzip_path.md),
  [`tabix_path()`](https://rgenomicsetl.github.io/RBCFTools/reference/tabix_path.md))

### 3. DuckDB Extension (`inst/duckdb_bcf_reader_extension/`)

- **Standalone C extension**:
  [bcf_reader.c](https://rgenomicsetl.github.io/inst/duckdb_bcf_reader_extension/bcf_reader.c)
  provides `bcf_read()` SQL function
- **Build modes**: Uses RBCFTools’ htslib (`make RBCFTOOLS_HTSLIB=1`) or
  system htslib via pkg-config
- **Spec compliance**: Matches nanoarrow’s VCF validation, logs warnings
  for non-conformant headers
- **Features**: Region filtering with .tbi/.csi indexes, projection
  pushdown (e.g., `SELECT COUNT(*)` is fast), parallel scanning by
  contig

### 4. Bundled Native Tools (`inst/bcftools/`, `inst/htslib/`)

Built during package installation by
[configure](https://rgenomicsetl.github.io/configure) script. Libraries
live in `inst/{bcftools,htslib}/lib/` with RPATH set for runtime
linking.

## Build System

### Installation Flow

1.  **[configure](https://rgenomicsetl.github.io/configure)**:
    Auto-detects dependencies (GSL, libcurl, libdeflate, pkg-config),
    compiles htslib + bcftools from `src/bcftools-1.23/`
2.  **[src/Makevars.in](https://rgenomicsetl.github.io/src/Makevars.in)**:
    Template expanded by configure. Sets RPATH (`@loader_path` on macOS,
    `$ORIGIN` on Linux) for bundled libs
3.  **[src/install.libs.R](https://rgenomicsetl.github.io/src/install.libs.R)**:
    Copies compiled libs to `inst/{bcftools,htslib}/` after build

### Key Make Targets ([Makefile](https://rgenomicsetl.github.io/Makefile))

``` bash
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

``` bash
# After C changes (requires full configure)
make install

# After R changes only (faster, skips configure)
make install2
make test-dev
```

## Testing Strategy (`inst/tinytest/`)

Uses [tinytest](https://github.com/markvanderloo/tinytest) (lightweight,
no heavy dependencies). Key files: -
**[test_vcf_arrow.R](https://rgenomicsetl.github.io/inst/tinytest/test_vcf_arrow.R)**:
Arrow stream conversion, nanoarrow integration -
**[test_vcf_duckdb.R](https://rgenomicsetl.github.io/inst/tinytest/test_vcf_duckdb.R)**:
DuckDB extension build, SQL queries, Parquet export -
**[test_parallel.R](https://rgenomicsetl.github.io/inst/tinytest/test_parallel.R)**:
Parallel processing with per-chromosome chunks -
**[test_bcftools_comparison.R](https://rgenomicsetl.github.io/inst/tinytest/test_bcftools_comparison.R)**:
Validate Arrow output against bcftools CLI

**Run tests**:

``` bash
R -e 'tinytest::test_package("RBCFTools")'       # All tests
R -e 'library(RBCFTools); tinytest::run_test_dir("inst/tinytest")'  # After install2
```

**Test files** in `inst/extdata/`: - `1000G_3samples.vcf.gz` (small
multi-sample file) - `test_format_simple.vcf` (uncompressed, for basic
parsing tests)

## Critical Conventions

### VCF Spec Conformance

Both nanoarrow and DuckDB implementations **auto-correct**
non-conformant headers (e.g., FORMAT/AD should be Number=R, FORMAT/GQ
should be Type=Integer) and emit warnings/logs. This mimics htslib’s
`bcf_hdr_check_sanity()`. **Never silently fail** on spec violations—log
and correct.

### Remote File Access

**Always call
[`setup_hts_env()`](https://rgenomicsetl.github.io/RBCFTools/reference/setup_hts_env.md)**
before reading S3/GCS/HTTP files—it sets `HTS_PATH` for htslib’s remote
file plugin. Example in
[vcf_arrow.R#L73-74](https://rgenomicsetl.github.io/R/vcf_arrow.R#L73-L74).

### Index Detection

- **VCF.GZ**: Try .tbi first, then .csi
- **BCF**: Use .csi only
- **Custom indexes**: Use `index=` parameter or htslib `##idx##` syntax
  (`file.vcf.gz##idx##custom.tbi`)

### RPATH Setup

C code must find bundled shared libs at runtime.
[Makevars.in](https://rgenomicsetl.github.io/src/Makevars.in#L8-L15)
uses platform-specific RPATH: - **macOS**:
`-Wl,-rpath,@loader_path/../{bcftools,htslib}/lib` - **Linux**:
`-Wl,--disable-new-dtags -Wl,-rpath,'$$ORIGIN/../{bcftools,htslib}/lib'`

Post-install, `install_name_tool` fixes macOS dylib references
([Makevars.in#L34-L37](https://rgenomicsetl.github.io/src/Makevars.in#L34-L37)).

### Parallel Processing Pattern

See [vcf_parallel.R](https://rgenomicsetl.github.io/R/vcf_parallel.R).
Typical flow: 1. Check index with
[`vcf_has_index()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_has_index.md)
2. Get contigs via
[`vcf_get_contigs()`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_get_contigs.md)
3. Use
[`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html) or
[`parallel::parLapply()`](https://rdrr.io/r/parallel/clusterApply.html)
to process per-chromosome 4. Combine results (e.g.,
`do.call(rbind, ...)` for data frames)

### VEP/SnpEff/ANNOVAR Annotations

**Current status**: Structured annotation fields (INFO/CSQ from VEP,
INFO/ANN from SnpEff, INFO/BCSQ from bcftools/csq) are **not specially
parsed**—they remain as pipe-delimited strings.

**Known Issues**: 1. String post-processing in SQL is inefficient and
loses type information 2. No schema extraction from VCF header
Description field

**Test Files** (in `inst/extdata/`): - `test_vep.vcf` - Full VEP
annotations with 80+ fields - `test_vep_types.vcf` - VEP with typed
fields (SpliceAI, gnomAD, etc.) - `test_vep_snpeff.vcf` - bcftools/csq
BCSQ format

**Implementation Plan**: See
[docs/VEP_ANNOTATION_PARSING_PLAN.md](https://rgenomicsetl.github.io/docs/VEP_ANNOTATION_PARSING_PLAN.md)
for detailed plan including: - Core parser library (`vep_parser.c/h`)
inspired by bcftools `+split-vep` - Type inference from field names
(e.g., `*_AF` → Float) - DuckDB extension with `vep_mode` parameter for
exploded columns - Arrow stream with `parse_vep` option

**Workarounds** (current): - Use bcftools `+split-vep` plugin via
`system2(bcftools_path(), ...)` upstream - Post-process with DuckDB SQL:
`SELECT unnest(string_split(INFO_CSQ, '|')) ...`

## Common Tasks

### Adding a New C Function

1.  Declare in `src/*.c` (e.g., `SEXP RC_my_function(SEXP arg)`)
2.  Register in [src/init.c](https://rgenomicsetl.github.io/src/init.c)
    via `R_CallMethodDef`
3.  Add R wrapper in `R/*.R` using
    `.Call(RC_my_function, arg, PACKAGE = "RBCFTools")`
4.  Rebuild: `make install2` (if no new C files) or `make install` (if
    new files)

### Building DuckDB Extension

``` r
# From R session
library(RBCFTools)
build_dir <- tempdir()
bcf_reader_copy_source(build_dir)  # Copy sources (installed pkg is read-only)
ext_path <- bcf_reader_build(build_dir)

# Or use Makefile directly
cd inst/duckdb_bcf_reader_extension
make RBCFTOOLS_HTSLIB=1  # Use package htslib
```

### Debugging Remote File Access

Set `HTS_DEBUG=1` environment variable to see htslib’s remote file
plugin activity:

``` r
Sys.setenv(HTS_DEBUG = "1")
setup_hts_env()
vcf_open_arrow("s3://bucket/file.vcf.gz")
```

### Docker Testing

``` bash
# Build and run tests in container
docker build -f Dockerfile .

# Interactive dev container
docker build --build-arg BUILD_MODE=develop -f Dockerfile -t rbcftools:dev .
docker run -it rbcftools:dev R
```

## Documentation & Resources

- **README**: [README.md](https://rgenomicsetl.github.io/README.md)
  (generated from
  [README.Rmd](https://rgenomicsetl.github.io/README.Rmd) via
  `make rdm`)
- **VCF Specification**:
  <https://samtools.github.io/hts-specs/VCFv4.3.pdf>
- **bcftools manual**:
  <https://samtools.github.io/bcftools/bcftools.html>
- **DuckDB extension API**:
  <https://duckdb.org/docs/extensions/overview.html>
- **nanoarrow docs**: <https://arrow.apache.org/nanoarrow/latest/>

## Anti-Patterns

❌ **Don’t** use [`cat()`](https://rdrr.io/r/base/cat.html) in R
code—use [`message()`](https://rdrr.io/r/base/message.html) or
[`warning()`](https://rdrr.io/r/base/warning.html)  
❌ **Don’t** use sequential
[`.Call()`](https://rdrr.io/r/base/CallExternal.html) for batch
operations—prefer vectorized C code  
❌ **Don’t** assume Windows support—scripts must check `OS_type: unix`  
❌ **Don’t** link against system htslib/bcftools—package bundles
specific versions  
❌ **Don’t** forget to add test coverage for new features in
`inst/tinytest/`  
❌ **Don’t** modify generated files (README.md, man/\*.Rd)—edit sources
(README.Rmd, roxygen2 comments)  
❌ **Don’t** over-engineer—prefer simple, robust solutions  
❌ **Don’t** add heavy dependencies—nanoarrow is the exception, arrow
package is avoided

## Known Limitations

- **Memory copies**: Arrow streaming involves C-level copies; Parquet
  export adds IPC serialization overhead
- **No VEP/SnpEff parsing**: Structured annotations stay as raw strings
  (see VEP section above)
- **No Windows support**: htslib build system is Unix-only
- **DuckDB extension unsigned**: Requires `allow_unsigned_extensions`
  config
