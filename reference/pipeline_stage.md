# Define an Executable Pipeline Stage

Defines one executable and its argument vector without invoking a shell.
Stages can reference executables bundled by RBCFTools, executables
exported by another package, or programs available on `PATH`.

## Usage

``` r
pipeline_stage(command, args = character(), name = NULL)
```

## Arguments

- command:

  A length-one character string naming an executable or giving its path.

- args:

  A character vector of arguments passed directly to the executable.

- name:

  A label used in pipeline results. Defaults to the executable's
  basename.

## Value

An object of class `rbcftools_pipeline_stage`.

## Examples

``` r
pipeline_stage(samtools_path(), c("view", "--help"))
#> $command
#> [1] "/home/runner/work/_temp/Library/RBCFTools/samtools/bin/samtools"
#> 
#> $args
#> [1] "view"   "--help"
#> 
#> $name
#> [1] "samtools"
#> 
#> attr(,"class")
#> [1] "rbcftools_pipeline_stage"
```
