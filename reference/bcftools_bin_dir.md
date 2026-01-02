# Get Path to bcftools Binary Directory

Returns the path to the directory containing bcftools and related
scripts.

## Usage

``` r
bcftools_bin_dir()
```

## Value

A character string containing the path to the bcftools bin directory.

## Details

The directory contains the following tools:

- `bcftools` - Main bcftools executable

- `color-chrs.pl` - Chromosome coloring script

- `gff2gff` - GFF conversion tool

- `gff2gff.py` - GFF conversion Python script

- `guess-ploidy.py` - Ploidy guessing script

- `plot-roh.py` - ROH plotting script

- `plot-vcfstats` - VCF statistics plotting script

- `roh-viz` - ROH visualization tool

- `run-roh.pl` - ROH analysis script

- `vcfutils.pl` - VCF utilities script

- `vrfs-variances` - Variant frequency variances tool

## Examples

``` r
bcftools_bin_dir()
#> [1] "/home/runner/work/_temp/Library/RBCFTools/bcftools/bin"
```
