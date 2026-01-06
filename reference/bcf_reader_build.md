# Build the bcf_reader DuckDB extension

Compiles the bcf_reader extension from source using the package's
htslib. Source files are copied to the build directory first.

## Usage

``` r
bcf_reader_build(build_dir, force = FALSE, verbose = TRUE)
```

## Arguments

- build_dir:

  Directory where to build the extension. Source files will be copied
  here and the extension will be built in `build_dir/build/`.

- force:

  Logical, force rebuild even if extension exists

- verbose:

  Logical, show build output

## Value

Path to the built extension file

## Examples

``` r
if (FALSE) { # \dontrun{
# Build in temp directory
ext_path <- bcf_reader_build(tempdir())

# Build in a specific location
ext_path <- bcf_reader_build("/tmp/bcf_reader")

# Force rebuild
ext_path <- bcf_reader_build("/tmp/bcf_reader", force = TRUE)
} # }
```
