# RBCFTools: \`htslib\` And \`bcftools\` Libraries And Command Line Tools Wrapper

Provides R bindings to 'htslib' and 'bcftools' for reading and
manipulating VCF/BCF files. Includes experimental streaming facilities
from VCF to Apache Arrow via 'nanoarrow', enabling efficient export to
Parquet and Arrow IPC formats using 'DuckDB' without requiring the heavy
'arrow' package. Bundles 'htslib' and 'bcftools' libraries and
command-line tools.

## See also

Useful links:

- <https://github.com/RGenomicsETL/RBCFTools>

- <https://rgenomicsetl.github.io/RBCFTools/>

- Report bugs at <https://github.com/RGenomicsETL/RBCFTools/issues>

## Author

**Maintainer**: Sounkou Mahamane Toure <sounkoutoure@gmail.com>

Other contributors:

- Bonfield, James K and Marshall, John and Danecek, Petr and Li, Heng
  and Ohan, Valeriu and Whitwham, Andrew and Keane, Thomas and Davies,
  Robert M (Authors of included htslib library and bcftools command line
  tools) \[copyright holder\]

- Zilong Li <zilong.dk@gmail.com> (Author of the vcfpp library from whom
  makefiles and configure strategy is borrowed) \[copyright holder\]
