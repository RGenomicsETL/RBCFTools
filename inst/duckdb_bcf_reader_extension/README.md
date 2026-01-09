# DuckDB BCF/VCF Reader Extension

A high-performance DuckDB extension for reading BCF/VCF genomic variant files directly in SQL queries. Built with VCF spec-compliant type handling matching the nanoarrow `vcf_arrow_stream` implementation.

## Features

- **Multiple formats**: Read VCF, VCF.GZ (bgzip), and BCF files directly in DuckDB
- **VCF spec-compliant types**: Proper handling of INTEGER, FLOAT, FLAG, and STRING types with LIST support for Number=A/G/R/. fields
- **Region filtering**: Fast random access with CSI (BCF) or TBI (VCF.gz) index support
- **Projection pushdown**: Efficient queries that only read required columns (e.g., `SELECT COUNT(*)` is fast)
- **Parallel scanning**: Automatic parallel scan by contig when an index is available
- **Genotype support**: Proper GT field decoding (e.g., "0/1", "1|1", "./.")
- **Type validation**: Warns when header types don't match VCF spec and corrects schema accordingly
- **Structured annotations**: Auto-detects INFO/CSQ, INFO/BCSQ, or INFO/ANN in the header and emits one typed column per subfield (prefixed `VEP_`), using bcftools split-vep inference. First transcript is exposed (scalar); list mode can be added later if needed.

## Requirements

- GCC or Clang
- DuckDB v1.2.0 or later
- htslib (can use system install, pkg-config, or static link)

### Building Options

**Using system htslib (via pkg-config):**
```bash
make
```

**Using RBCFTools package htslib:**
```bash
make RBCFTOOLS_HTSLIB=1
```

**Using static htslib:**
```bash
make HTSLIB_STATIC=/path/to/libhts.a
```

**With libdeflate support** (if htslib was built with libdeflate):
```bash
make HTSLIB_STATIC=/path/to/libhts.a USE_DEFLATE=1
```

Note: Static `libhts.a` requires its dependencies: `-lz -lbz2 -llzma -lcurl -lpthread` (and `-ldeflate` if enabled). The Makefile handles this automatically.

This produces `build/bcf_reader.duckdb_extension`.

## Usage

```sql
-- Load the extension (requires -unsigned flag for unsigned extensions)
LOAD 'path/to/bcf_reader.duckdb_extension';

-- Read a VCF/BCF file
SELECT * FROM bcf_read('variants.vcf.gz') LIMIT 10;

-- Count variants (uses projection pushdown - very fast!)
SELECT COUNT(*) FROM bcf_read('variants.bcf');

-- Filter by chromosome and position
SELECT CHROM, POS, REF, ALT 
FROM bcf_read('variants.vcf.gz')
WHERE CHROM = '22' AND POS > 10000000;

-- Access parsed VEP/BCSQ/ANN annotations (auto-detected)
SELECT CHROM, POS, VEP_Consequence, VEP_SYMBOL, VEP_AF
FROM bcf_read('annotated.vcf.gz')
LIMIT 5;

-- Read a specific region (requires index file: .tbi or .csi)
SELECT * FROM bcf_read('variants.vcf.gz', region := 'chr1:1000000-2000000');

-- Access INFO fields
SELECT CHROM, POS, INFO_AC, INFO_AF, INFO_DP
FROM bcf_read('variants.vcf.gz')
WHERE INFO_AF[1] > 0.01;  -- AF is a list for multi-allelic sites

-- Access FORMAT/genotype fields per sample
SELECT CHROM, POS, FORMAT_GT_NA12878, FORMAT_AD_NA12878, FORMAT_DP_NA12878
FROM bcf_read('variants.vcf.gz')
WHERE FORMAT_GT_NA12878 = '0/1';

-- Variant type analysis
SELECT 
    CASE 
        WHEN LENGTH(REF) = 1 AND LENGTH(ALT[1]) = 1 THEN 'SNP'
        WHEN LENGTH(REF) > LENGTH(ALT[1]) THEN 'DEL'
        WHEN LENGTH(REF) < LENGTH(ALT[1]) THEN 'INS'
        ELSE 'COMPLEX'
    END as variant_type,
    COUNT(*) as count
FROM bcf_read('variants.vcf.gz')
GROUP BY variant_type;

-- Export to Parquet for fast subsequent queries
COPY (SELECT * FROM bcf_read('variants.vcf.gz')) 
TO 'variants.parquet' (FORMAT PARQUET);

-- Join with annotation table
SELECT v.CHROM, v.POS, v.REF, v.ALT, a.gene_name, a.consequence
FROM bcf_read('variants.vcf.gz') v
JOIN 'annotations.parquet' a 
  ON v.CHROM = a.chrom AND v.POS = a.pos;
```

## Schema

The extension produces columns following the VCF specification:

### Core Columns

| Column | Type | Description |
|--------|------|-------------|
| CHROM | VARCHAR | Chromosome name |
| POS | BIGINT | 1-based position |
| ID | VARCHAR | Variant ID (NULL if ".") |
| REF | VARCHAR | Reference allele |
| ALT | LIST(VARCHAR) | List of alternate alleles |
| QUAL | DOUBLE | Quality score (NULL if missing) |
| FILTER | LIST(VARCHAR) | List of filter names (["PASS"] if passed) |

### INFO Columns (INFO_\<name\>)

INFO fields are prefixed with `INFO_` and typed according to the VCF header:

| Header Type | Header Number | DuckDB Type |
|-------------|---------------|-------------|
| Integer | 1 | INTEGER |
| Integer | A/G/R/. | LIST(INTEGER) |
| Float | 1 | FLOAT |
| Float | A/G/R/. | LIST(FLOAT) |
| String | 1 | VARCHAR |
| String | A/G/R/. | LIST(VARCHAR) |
| Flag | 0 | BOOLEAN |

### FORMAT Columns (FORMAT_\<field\>_\<sample\>)

FORMAT fields are prefixed with `FORMAT_` and suffixed with the sample name:

| Field | Type | Description |
|-------|------|-------------|
| FORMAT_GT_\<sample\> | VARCHAR | Genotype (e.g., "0/1", "1\|0", "./.") |
| FORMAT_AD_\<sample\> | LIST(INTEGER) | Allelic depths |
| FORMAT_DP_\<sample\> | INTEGER | Read depth |
| FORMAT_GQ_\<sample\> | INTEGER/FLOAT | Genotype quality |
| FORMAT_PL_\<sample\> | LIST(INTEGER) | Phred-scaled likelihoods |

## Type Validation

The extension validates field types against the VCF 4.3 specification and emits warnings when headers don't match:

```
[bcf_reader] FORMAT/AD should be Number=R per VCF spec; correcting schema
[bcf_reader] FORMAT/GQ should be Type=Integer per VCF spec, but header declares Type=Float; using header type
```

Known VCF spec field definitions are enforced:
- **GT**: Number=1, Type=String
- **AD**: Number=R, Type=Integer  
- **DP**: Number=1, Type=Integer
- **GQ**: Number=1, Type=Integer
- **PL**: Number=G, Type=Integer
- **AC**: Number=A, Type=Integer
- **AF**: Number=A, Type=Float
- **AN**: Number=1, Type=Integer
- And many more...

## Performance Tips

1. **Use indexed files**: Create .tbi (tabix) or .csi index for random access and parallel scanning
2. **Use region queries**: `bcf_read('file.vcf.gz', region := 'chr1:1-1000000')` is much faster than filtering
3. **Select only needed columns**: Projection pushdown skips parsing unused fields
4. **Export to Parquet**: For repeated queries, convert to Parquet once
5. **Use BCF format**: BCF is faster to parse than VCF.gz

## Testing

```bash
# Build and run test suite
chmod +x test_extension.sh
./test_extension.sh
```

## Installing

```bash
make install
```

Installs to `~/.duckdb/extensions/v1.2.0/<platform>/`.

## Architecture

The extension uses:
- **htslib**: For VCF/BCF parsing (vcf.h, hts.h, tbx.h)
- **DuckDB C API**: Table function with bind/init/scan callbacks
- **VCF spec types**: Matching the nanoarrow vcf_arrow_stream implementation

Key design decisions:
- ALT and FILTER are LIST types (not comma-separated strings)
- INFO/FORMAT fields use proper numeric types (not all strings)
- GT is decoded to human-readable format (not raw BCF encoding)
- NULL handling follows VCF conventions (missing = NULL)

## License

MIT License - Copyright (c) 2026 RBCFTools Authors
