#!/bin/bash
# Test script for bcf_reader DuckDB extension
# Tests various VCF/BCF file formats from inst/extdata

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTDATA_DIR="$SCRIPT_DIR/../extdata"
EXTENSION="$SCRIPT_DIR/build/bcf_reader.duckdb_extension"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "  DuckDB BCF Reader Extension Test Suite"
echo "=============================================="
echo ""

# Check if extension exists
if [ ! -f "$EXTENSION" ]; then
    echo -e "${YELLOW}Extension not found. Building...${NC}"
    cd "$SCRIPT_DIR" && make clean && make RBCFTOOLS_HTSLIB=1 RBCFTOOLS_ROOT=../..
    echo ""
fi

# Function to run a test query
run_test() {
    local test_name="$1"
    local query="$2"
    
    echo -e "${YELLOW}Test: ${test_name}${NC}"
    if duckdb -unsigned -c "LOAD '$EXTENSION'; $query" 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}"
    else
        echo -e "${RED}✗ FAILED${NC}"
        exit 1
    fi
    echo ""
}

# Suppress bcf_reader warnings for cleaner output
export SUPPRESS_BCF_WARNINGS=1

echo "=============================================="
echo "  Testing BCF Files (with index)"
echo "=============================================="

run_test "1000G_3samples.bcf - Basic read" \
    "SELECT CHROM, POS, REF, ALT FROM bcf_read('$EXTDATA_DIR/1000G_3samples.bcf') LIMIT 5;"

run_test "1000G_3samples.bcf - Count rows" \
    "SELECT COUNT(*) as total_variants FROM bcf_read('$EXTDATA_DIR/1000G_3samples.bcf');"

run_test "1000G_3samples.bcf - Region query" \
    "SELECT CHROM, POS, REF, ALT FROM bcf_read('$EXTDATA_DIR/1000G_3samples.bcf', region := '1:10000-20000') LIMIT 5;"

run_test "gnomad.exomes.bcf - Multi-allelic sites" \
    "SELECT CHROM, POS, REF, ALT, INFO_AC, INFO_AF FROM bcf_read('$EXTDATA_DIR/gnomad.exomes.r2.0.1.sites.bcf') LIMIT 5;"

run_test "gnomad.exomes.bcf - Count rows" \
    "SELECT COUNT(*) as total_variants FROM bcf_read('$EXTDATA_DIR/gnomad.exomes.r2.0.1.sites.bcf');"

echo "=============================================="
echo "  Testing VCF.gz Files (with tabix index)"
echo "=============================================="

run_test "test_deep_variant.vcf.gz - Basic read with GT" \
    "SELECT CHROM, POS, REF, ALT, FORMAT_GT_test_deep_variant, FORMAT_AD_test_deep_variant FROM bcf_read('$EXTDATA_DIR/test_deep_variant.vcf.gz') LIMIT 5;"

run_test "test_deep_variant.vcf.gz - Region query" \
    "SELECT CHROM, POS, REF, ALT FROM bcf_read('$EXTDATA_DIR/test_deep_variant.vcf.gz', region := '1:536000-540000') LIMIT 10;"

run_test "test_deep_variant.vcf.gz - Count rows" \
    "SELECT COUNT(*) as total_variants FROM bcf_read('$EXTDATA_DIR/test_deep_variant.vcf.gz');"

echo "=============================================="
echo "  Testing Plain VCF Files"
echo "=============================================="

run_test "test_info_fields.vcf - INFO fields" \
    "SELECT CHROM, POS, REF, ALT, INFO_AC, INFO_AF FROM bcf_read('$EXTDATA_DIR/test_info_fields.vcf');"

run_test "test_format_simple.vcf - FORMAT fields" \
    "SELECT * FROM bcf_read('$EXTDATA_DIR/test_format_simple.vcf');"

run_test "test_format_info.vcf - Core columns" \
    "SELECT CHROM, POS, REF, ALT, QUAL, FILTER FROM bcf_read('$EXTDATA_DIR/test_format_info.vcf') LIMIT 5;"

run_test "test_vep.vcf - VEP annotations parsed" \
    "SELECT CHROM, POS, REF, ALT, VEP_Consequence, VEP_SYMBOL, VEP_AF FROM bcf_read('$EXTDATA_DIR/test_vep.vcf') LIMIT 3;"

echo "=============================================="
echo "  Testing BCF without index"
echo "=============================================="

run_test "1000G.ALL.2of4intersection.bcf - Basic read" \
    "SELECT CHROM, POS, REF, ALT, QUAL FROM bcf_read('$EXTDATA_DIR/1000G.ALL.2of4intersection.20100804.genotypes.bcf') LIMIT 5;"

echo "=============================================="
echo "  Testing Edge Cases"
echo "=============================================="

run_test "Projection pushdown (COUNT only)" \
    "SELECT COUNT(*) FROM bcf_read('$EXTDATA_DIR/1000G_3samples.bcf');"

run_test "Filter by chromosome" \
    "SELECT CHROM, COUNT(*) as n FROM bcf_read('$EXTDATA_DIR/1000G_3samples.bcf') GROUP BY CHROM ORDER BY n DESC LIMIT 5;"

run_test "Export to Parquet (in-memory)" \
    "COPY (SELECT CHROM, POS, REF, ALT FROM bcf_read('$EXTDATA_DIR/1000G_3samples.bcf') LIMIT 100) TO '/tmp/test_variants.parquet' (FORMAT PARQUET); SELECT COUNT(*) FROM '/tmp/test_variants.parquet';"

echo "=============================================="
echo -e "  ${GREEN}All tests passed!${NC}"
echo "=============================================="
