# RBCFTools: Bundled 'Samtools', 'BCFtools', and 'HTSlib' Genomics Utilities

Bundles the 'Samtools' and 'BCFtools' command-line executables together
with the 'HTSlib' and 'libbcftools' libraries for reading and
manipulating VCF, BCF, SAM, BAM, and CRAM files. 'Samtools' and
'BCFtools' are built against one shared vendored 'HTSlib' source.
Provides streaming facilities from VCF and BCF to Apache Arrow via
'nanoarrow', export to Arrow IPC and Parquet via 'duckdb', a native
'bcf_reader' extension, and utilities for reading and writing VCF and
BCF data in 'DuckLake'.

## See also

Useful links:

- <https://github.com/RGenomicsETL/RBCFTools>

- <https://rgenomicsetl.github.io/RBCFTools/>

- <https://github.com/samtools/samtools>

- <https://github.com/samtools/bcftools>

- <https://github.com/samtools/htslib>

- Report bugs at <https://github.com/RGenomicsETL/RBCFTools/issues>

## Author

**Maintainer**: Sounkou Mahamane Toure <sounkoutoure@gmail.com>

Other contributors:

- Bonfield, James K and Marshall, John and Danecek, Petr and Li, Heng
  and Ohan, Valeriu and Whitwham, Andrew and Keane, Thomas Davies,
  Robert M, Pierre Lindenbaum (Authors of included htslib library and
  bcftools command line tools) \[copyright holder\]

- Genome Research Ltd. (Copyright holder of the included Samtools
  source) \[copyright holder\]

- Zilong Li <zilong.dk@gmail.com> (Author of the vcfpp library from whom
  makefiles and configure strategy is borrowed) \[copyright holder\]

- Duckdb C API and extension and API authors (Authors of the duckdb
  extension and API used for parquet export) \[copyright holder\]
