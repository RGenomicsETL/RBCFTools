# Convert Parquet back to VCF/BCF format

Reconstruct a VCF file from Parquet data created by
[`vcf_to_parquet_duckdb`](https://rgenomicsetl.github.io/RBCFTools/reference/vcf_to_parquet_duckdb.md).
Uses the VCF header stored in Parquet metadata for proper formatting.

## Usage

``` r
parquet_to_vcf(
  input_file,
  output_file,
  header = NULL,
  index = TRUE,
  con = NULL
)
```

## Arguments

- input_file:

  Path to input Parquet file (must have VCF metadata)

- output_file:

  Path to output VCF/VCF.GZ/BCF file. Format determined by extension.

- header:

  Optional VCF header string. If NULL (default), reads from Parquet
  metadata.

- index:

  Logical, if TRUE creates tabix/CSI index for output. Default TRUE.

- con:

  Optional existing DuckDB connection

## Value

Invisible path to output file

## Examples

``` r
if (FALSE) { # \dontrun{
# Round-trip: VCF -> Parquet -> VCF
vcf_file <- system.file("extdata", "1000G_3samples.vcf.gz", package = "RBCFTools")
ext_path <- bcf_reader_build(tempdir(), verbose = FALSE)

# Convert to Parquet (with metadata)
parquet_file <- tempfile(fileext = ".parquet")
vcf_to_parquet_duckdb(vcf_file, parquet_file, ext_path)

# Convert back to VCF
vcf_out <- tempfile(fileext = ".vcf.gz")
parquet_to_vcf(parquet_file, vcf_out)
} # }
```
