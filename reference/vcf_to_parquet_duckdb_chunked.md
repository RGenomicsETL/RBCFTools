# Convert VCF/BCF to Parquet using adaptive chunking strategy

Uses sub-chromosomal chunking for optimal parallelization. Works for
both single and multi-chromosome files by creating ~100MB chunks across
all chromosomes.

## Usage

``` r
vcf_to_parquet_duckdb_chunked(
  input_file,
  output_file,
  extension_path = NULL,
  columns = NULL,
  compression = "zstd",
  row_group_size = 1e+05,
  threads = parallel::detectCores(),
  contigs = NULL
)
```

## Arguments

- input_file:

  Path to input VCF, VCF.GZ, or BCF file

- output_file:

  Path to output Parquet file

- extension_path:

  Path to the bcf_reader.duckdb_extension file.

- columns:

  Optional character vector of columns to include. NULL for all.

- compression:

  Parquet compression: "snappy", "zstd", "gzip", or "none"

- row_group_size:

  Number of rows per row group (default: 100000)

- threads:

  Number of parallel threads for processing (default: 1). When threads
  \> 1 and file is indexed, uses parallel processing by splitting work
  across chromosomes/contigs. See `vcf_to_parquet_duckdb_parallel`.

- contigs:

  Character vector of contig names

## Value

List with conversion metrics
