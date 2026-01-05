# DuckDB BCF/VCF Reader Extension

A self-contained DuckDB extension for reading BCF/VCF genomic variant files directly in SQL queries.

## Features

- Read VCF, VCF.GZ, and BCF files directly in DuckDB
- Optional region filtering for indexed files
- Full genotype (GT) support with one column per sample
- Projection pushdown for efficient queries (e.g., `SELECT COUNT(*)`)

## Requirements

- GCC or Clang
- DuckDB v1.2.0 or later
- Only need to copy `duckdb.h` and `duckdb_extension.h` from your DuckDB build or release (no other files needed)
- If you bundle HTSlib, just set `HTSLIB_STATIC=/path/to/libhts.a` when building (no system install needed)

### Example: Building with bundled HTSlib

```bash
make HTSLIB_STATIC=../../src/bcftools-1.23/libhts.a
```

This will statically link your bundled HTSlib. No pkg-config or system htslib required.

## Building

```bash
make
```

This produces `build/bcf_reader.duckdb_extension`.

## Usage

```sql
-- Load the extension (requires -unsigned flag)
LOAD 'path/to/bcf_reader.duckdb_extension';

-- Read a VCF/BCF file
SELECT * FROM bcf_read('variants.vcf.gz') LIMIT 10;

-- Count variants
SELECT COUNT(*) FROM bcf_read('variants.bcf');

-- Filter by chromosome and position
SELECT CHROM, POS, REF, ALT 
FROM bcf_read('variants.vcf.gz')
WHERE CHROM = '22' AND POS > 10000000;

-- Read a specific region (requires index file)
SELECT * FROM bcf_read('variants.vcf.gz', region := 'chr1:1000000-2000000');

-- Variant type analysis
SELECT 
    CASE 
        WHEN LENGTH(REF) = 1 AND LENGTH(ALT) = 1 THEN 'SNP'
        WHEN LENGTH(REF) > LENGTH(ALT) THEN 'DEL'
        WHEN LENGTH(REF) < LENGTH(ALT) THEN 'INS'
        ELSE 'OTHER'
    END as variant_type,
    COUNT(*) as count
FROM bcf_read('variants.vcf.gz')
GROUP BY variant_type;

-- Export to Parquet
COPY (SELECT * FROM bcf_read('variants.vcf.gz')) 
TO 'variants.parquet' (FORMAT PARQUET);
```

## Schema

The extension produces the following columns:

| Column | Type | Description |
|--------|------|-------------|
| CHROM | VARCHAR | Chromosome name |
| POS | BIGINT | 1-based position |
| ID | VARCHAR | Variant ID |
| REF | VARCHAR | Reference allele |
| ALT | VARCHAR | Alternate allele(s), comma-separated |
| QUAL | FLOAT | Quality score |
| FILTER | VARCHAR | Filter status |
| INFO | VARCHAR | INFO field (placeholder) |
| GT_\<sample\> | VARCHAR | Genotype for each sample (e.g., "0/1", "1\|0") |

## Testing

```bash
make test
```

## Installing

```bash
make install
```

This installs to `~/.duckdb/extensions/v1.2.0/<platform>/`.

## Configuration

Edit the Makefile to change:

- `DUCKDB_VERSION` - Target DuckDB version (default: v1.2.0)
- `EXTENSION_VERSION` - Extension version (default: 1.0.0)

## Files

```
bcf_reader/
├── Makefile              # Build system
├── bcf_reader.c          # Extension source code
├── duckdb_extension.h    # DuckDB C extension header
├── duckdb.h              # DuckDB C API header
├── append_metadata.sh    # Script to append extension metadata
└── README.md             # This file
```

## License

MIT License
