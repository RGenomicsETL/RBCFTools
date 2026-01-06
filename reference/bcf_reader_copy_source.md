# Copy bcf_reader extension source to a build directory

Copies the extension source files from the package to a specified
directory for building. This is necessary because the installed package
directory is typically read-only.

## Usage

``` r
bcf_reader_copy_source(dest_dir)
```

## Arguments

- dest_dir:

  Directory where to copy the source files.

## Value

Invisible path to the destination directory

## Examples

``` r
if (FALSE) { # \dontrun{
# Copy to temp directory
build_dir <- bcf_reader_copy_source(tempdir())

# Copy to a specific location
build_dir <- bcf_reader_copy_source("/tmp/bcf_reader_build")
} # }
```
