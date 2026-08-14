# RBCFTools Samtools vendor receipt

- Upstream: https://github.com/samtools/samtools
- Release: 1.24
- Archive: `samtools-1.24.tar.bz2`
- Archive URL: https://github.com/samtools/samtools/releases/download/1.24/samtools-1.24.tar.bz2
- SHA-256: `89b2a440123eeaa400392ce1736e7d60ce9041843027d76819753c5a8246bfdd`

RBCFTools omits the archive's `htslib-1.24/` copy and upstream test data.
The package configure script builds Samtools against the one canonical HTSlib
source tree at `src/bcftools-1.24/htslib-1.24/`, with
`--disable-configure-htslib` so HTSlib is configured and built only once.
