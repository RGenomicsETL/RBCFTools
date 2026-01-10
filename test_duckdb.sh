#!/bin/bash

# Test script for vcf2parquet_duckdb.R (native DuckDB bcf_reader version)

SCRIPT=$(Rscript -e "cat(system.file('scripts', 'vcf2parquet_duckdb.R', package='RBCFTools'))")
BCF=$(Rscript -e "cat(system.file('extdata', '1000G_3samples.bcf', package='RBCFTools'))")
BCF=${1:-"$BCF"}
OUT_PQ=$(echo $BCF | sed -e 's/\.bcf$/_duckdb.parquet/' -e 's/\.vcf\.gz$/_duckdb.parquet/' -e 's/\.vcf$/_duckdb.parquet/')
threads=10

echo "=============================================="
echo "Testing DuckDB Native VCF Converter"
echo "=============================================="
echo "Script: $SCRIPT"
echo "Input VCF/BCF: $BCF"
echo "Output Parquet: $OUT_PQ"
echo "Threads: $threads"
echo ""

# Build extension once at the beginning
echo "=== Step 1: Building bcf_reader extension (one time) ==="
BUILD_DIR=$(mktemp -d)
echo "Build directory: $BUILD_DIR"

EXT_PATH=$(Rscript -e "library(RBCFTools); cat(bcf_reader_build('$BUILD_DIR', verbose=FALSE))")
if [ ! -f "$EXT_PATH" ]; then
    echo "ERROR: Failed to build extension"
    rm -rf "$BUILD_DIR"
    exit 1
fi
echo "Extension built: $EXT_PATH"
echo ""

# Convert BCF to Parquet using native DuckDB mode with parallel processing
echo "=== Step 2: Convert VCF/BCF to Parquet (DuckDB mode) ==="
time $SCRIPT convert \
    --row-group-size 100000 -t $threads -c zstd -i $BCF -o $OUT_PQ --ext-path "$EXT_PATH"

if [ $? -ne 0 ]; then
    echo "ERROR: Conversion failed"
    rm -rf $BUILD_DIR
    exit 1
fi

# Verify file was created
if [ ! -f "$OUT_PQ" ]; then
    echo "ERROR: Output parquet file not created"
    rm -rf $BUILD_DIR
    exit 1
fi

echo ""
echo "=== Step 3: Query VCF/BCF directly with SQL (DuckDB mode) ==="
$SCRIPT query -i $BCF -q "SELECT CHROM, COUNT(*) as n FROM bcf_read('{file}') GROUP BY CHROM" \
    --ext-path "$EXT_PATH"

echo ""
echo "=== Step 4: Query Parquet file with DuckDB ==="
$SCRIPT query -i $OUT_PQ -q "SELECT CHROM, POS, REF, ALT FROM parquet_scan('$OUT_PQ') LIMIT 5"

echo ""
echo "=== Step 5: Describe Parquet table structure ==="
$SCRIPT query -i $OUT_PQ -q "DESCRIBE SELECT * FROM parquet_scan('$OUT_PQ')"

echo ""
echo "=== Step 6: Show VCF schema via DuckDB ==="
$SCRIPT schema -i $BCF --ext-path "$EXT_PATH"

echo ""
echo "=== Step 7: Parquet file info ==="
$SCRIPT info -i $OUT_PQ

echo ""
echo "=== Step 8: Test region query ==="
# Get first chromosome from the file
FIRST_CHROM=$(Rscript -e "library(RBCFTools); cat(vcf_get_contigs('$BCF')[1])")
if [ -n "$FIRST_CHROM" ]; then
    echo "Querying region: $FIRST_CHROM"
    $SCRIPT query -i $BCF -r "$FIRST_CHROM" \
        -q "SELECT COUNT(*) as n FROM bcf_read('{file}', region := '{region}')" \
        --ext-path "$EXT_PATH"
fi

echo ""
echo "=== Step 9: Test column selection ==="
OUT_SLIM="${OUT_PQ%.parquet}_slim.parquet"
$SCRIPT convert -i $BCF -o $OUT_SLIM --columns CHROM,POS,REF,ALT \
    --ext-path "$EXT_PATH" -c snappy

if [ -f "$OUT_SLIM" ]; then
    echo "Created slim parquet: $OUT_SLIM"
    $SCRIPT query -i $OUT_SLIM -q "DESCRIBE SELECT * FROM parquet_scan('$OUT_SLIM')"
    rm -f "$OUT_SLIM"
fi

# Interval query timing tests with R/DuckDB
echo ""
echo "=== Step 10: Performance Testing ==="
Rscript - "$OUT_PQ" "$BCF" "$EXT_PATH" << 'RSCRIPT'
library(duckdb)
library(data.table)
library(RBCFTools)

args <- commandArgs(trailingOnly = TRUE)
parquet_file <- args[1]
vcf_file <- args[2]
ext_path <- args[3]

if (!file.exists(parquet_file)) {
    cat(sprintf("Warning: Parquet file not found at %s\n", parquet_file))
    quit(save = "no", status = 0)
}

cat(sprintf("Using parquet file: %s\n", parquet_file))
cat(sprintf("Using VCF file: %s\n", vcf_file))
cat(sprintf("Using extension: %s\n", ext_path))

# Connect to DuckDB with pre-built extension
con <- vcf_duckdb_connect(ext_path)
cat("Connected to DuckDB with bcf_reader extension loaded\n\n")

# Register parquet file as a view
dbExecute(con, sprintf("CREATE VIEW variants AS SELECT * FROM '%s'", parquet_file))

# Get schema
schema <- dbGetQuery(con, "DESCRIBE SELECT * FROM variants")
pos_col <- schema$column_name[grep("^pos$", tolower(schema$column_name))]
chrom_col <- schema$column_name[grep("^chrom$", tolower(schema$column_name))]

if (length(pos_col) == 0 || length(chrom_col) == 0) {
    cat("Error: Required columns (CHROM, POS) not found\n")
    dbDisconnect(con)
    quit(save = "no", status = 1)
}

cat("=== Test 1: Simple Variant Counting ===\n")

# Count variants in Parquet
cat("\n1a. Count all variants in Parquet:\n")
parquet_count_start <- Sys.time()
parquet_count <- dbGetQuery(con, "SELECT COUNT(*) as n FROM variants")$n[1]
parquet_count_time <- as.numeric(difftime(Sys.time(), parquet_count_start, units = "secs"))
cat(sprintf("   Result: %d variants (%.4f sec)\n", parquet_count, parquet_count_time))

# Count variants in VCF - use a fresh query
cat("\n1b. Count all variants in VCF:\n")
vcf_count_start <- Sys.time()
vcf_count_query <- sprintf("SELECT COUNT(*) as n FROM bcf_read('%s')", vcf_file)
cat(sprintf("   Query: %s\n", vcf_count_query))
vcf_count <- dbGetQuery(con, vcf_count_query)$n[1]
vcf_count_time <- as.numeric(difftime(Sys.time(), vcf_count_start, units = "secs"))
cat(sprintf("   Result: %d variants (%.4f sec)\n", vcf_count, vcf_count_time))

if (parquet_count == vcf_count) {
    cat(sprintf("\n✓ Counts match! Speedup: %.2fx faster\n", vcf_count_time / parquet_count_time))
} else {
    cat(sprintf("\n⚠ Warning: Counts differ (Parquet: %d, VCF: %d)\n", parquet_count, vcf_count))
}

# Count per chromosome
cat("\n=== Test 2: Count Variants Per Chromosome ===\n")

cat("\n2a. Parquet per-chromosome counts:\n")
parquet_perchrom_start <- Sys.time()
parquet_perchrom <- dbGetQuery(con, sprintf(
    "SELECT %s as chrom, COUNT(*) as n FROM variants GROUP BY %s ORDER BY n DESC LIMIT 5",
    chrom_col[1], chrom_col[1]
))
parquet_perchrom_time <- as.numeric(difftime(Sys.time(), parquet_perchrom_start, units = "secs"))
print(parquet_perchrom)
cat(sprintf("   Time: %.4f sec\n", parquet_perchrom_time))

cat("\n2b. VCF per-chromosome counts:\n")
vcf_perchrom_start <- Sys.time()
vcf_perchrom_query <- sprintf("SELECT CHROM, COUNT(*) as n FROM bcf_read('%s') GROUP BY CHROM ORDER BY n DESC LIMIT 5", vcf_file)
cat(sprintf("   Query: %s\n", substr(vcf_perchrom_query, 1, 100)), "...\n")
vcf_perchrom <- dbGetQuery(con, vcf_perchrom_query)
vcf_perchrom_time <- as.numeric(difftime(Sys.time(), vcf_perchrom_start, units = "secs"))
print(vcf_perchrom)
cat(sprintf("   Time: %.4f sec\n", vcf_perchrom_time))
cat(sprintf("   Speedup: %.2fx faster\n", vcf_perchrom_time / parquet_perchrom_time))

# Get chromosome statistics for interval tests
cat("\n=== Test 3: Interval Range Queries ===\n")
chrom_stats <- dbGetQuery(con, sprintf(
    "SELECT %s as chrom, COUNT(*) as n_variants, MIN(%s) as min_pos, MAX(%s) as max_pos 
     FROM variants GROUP BY %s ORDER BY n_variants DESC",
    chrom_col[1], pos_col[1], pos_col[1], chrom_col[1]
))
cat(sprintf("Dataset: %d chromosomes, %d total variants\n", 
           nrow(chrom_stats), sum(chrom_stats$n_variants)))
print(head(chrom_stats, 5))

# Generate test intervals
num_intervals <- min(100, sum(chrom_stats$n_variants > 10))
interval_width <- 100000  # 100kb intervals

# Select chromosomes with enough variants
test_chroms <- head(chrom_stats$chrom[chrom_stats$n_variants > 100], 
                   min(5, nrow(chrom_stats)))

if (length(test_chroms) == 0) {
    cat("\nNot enough variants for interval testing\n")
    dbDisconnect(con)
    quit(save = "no", status = 0)
}

cat(sprintf("\nGenerating %d test intervals (%d bp each) across %d chromosomes...\n",
           num_intervals, interval_width, length(test_chroms)))

# Generate intervals
intervals_list <- lapply(test_chroms, function(chr) {
    chr_data <- chrom_stats[chrom_stats$chrom == chr, ]
    n_intervals <- ceiling(num_intervals / length(test_chroms))
    
    starts <- as.integer(seq(chr_data$min_pos, 
                            max(chr_data$min_pos, chr_data$max_pos - interval_width),
                            length.out = n_intervals))
    
    data.table(
        chrom = chr,
        start_pos = starts,
        end_pos = starts + interval_width
    )
})
intervals <- rbindlist(intervals_list)
intervals[, query_id := .I]

cat(sprintf("Generated %d intervals\n", nrow(intervals)))

# Register intervals
dbWriteTable(con, "intervals", intervals, overwrite = TRUE)

# === Method 1: Query Parquet (via DuckDB view) ===
cat("\n3a. Parquet interval queries (range join):\n")
parquet_start <- Sys.time()

parquet_query <- sprintf("
    SELECT i.query_id, COUNT(*) as row_count
    FROM intervals i
    JOIN variants v ON v.%s = i.chrom AND v.%s >= i.start_pos AND v.%s <= i.end_pos
    GROUP BY i.query_id
    ORDER BY i.query_id
", chrom_col[1], pos_col[1], pos_col[1])

result_parquet <- dbGetQuery(con, parquet_query)
parquet_end <- Sys.time()
parquet_time <- as.numeric(difftime(parquet_end, parquet_start, units = "secs"))

cat(sprintf("   Result: %d intervals matched, %d total variants (%.4f sec)\n", 
           nrow(result_parquet), sum(result_parquet$row_count), parquet_time))

# === Method 2: Query VCF directly via bcf_read() ===
cat("\n3b. VCF interval queries (bcf_read with regions):\n")
vcf_start <- Sys.time()

# Query each interval separately via bcf_read with region parameter
vcf_counts <- lapply(seq_len(nrow(intervals)), function(i) {
    chr <- intervals$chrom[i]
    start_pos <- intervals$start_pos[i]
    end_pos <- intervals$end_pos[i]
    
    # Create region string for bcf_read
    region_str <- sprintf("%s:%d-%d", chr, start_pos, end_pos)
    
    tryCatch({
        region_query <- sprintf(
            "SELECT COUNT(*) as n FROM bcf_read('%s', region := '%s') WHERE %s >= %d AND %s <= %d", 
            vcf_file, region_str, pos_col[1], start_pos, pos_col[1], end_pos
        )
        count_result <- dbGetQuery(con, region_query)
        
        data.frame(
            query_id = intervals$query_id[i],
            row_count = as.integer(count_result$n[1])
        )
    }, error = function(e) {
        warning(sprintf("Query failed for interval %d (%s): %s", i, region_str, e$message))
        data.frame(
            query_id = intervals$query_id[i],
            row_count = 0L
        )
    })
})

result_vcf <- do.call(rbind, vcf_counts)
vcf_end <- Sys.time()
vcf_time <- as.numeric(difftime(vcf_end, vcf_start, units = "secs"))

cat(sprintf("   Result: %d intervals matched, %d total variants (%.4f sec)\n", 
           nrow(result_vcf), sum(result_vcf$row_count), vcf_time))
cat(sprintf("   Speedup: %.2fx faster\n\n", vcf_time / parquet_time))

# === Summary ===
cat("\n\n=== PERFORMANCE COMPARISON SUMMARY ===\n")
cat(sprintf("Dataset: %s\n", basename(parquet_file)))
cat(sprintf("Total variants: %d across %d chromosomes\n", 
           sum(chrom_stats$n_variants), nrow(chrom_stats)))
cat(sprintf("Test intervals: %d (%d bp each)\n", nrow(intervals), interval_width))
cat(sprintf("\nMethod 1 (Parquet):  %.4f sec (%.2f queries/sec)\n", 
           parquet_time, nrow(intervals) / parquet_time))
cat(sprintf("Method 2 (VCF direct): %.4f sec (%.2f queries/sec)\n", 
           vcf_time, nrow(intervals) / vcf_time))
cat(sprintf("\nSpeedup (Parquet vs VCF): %.2fx faster\n", vcf_time / parquet_time))

# Note about count differences
cat("\n=== Note on Count Differences ===\n")
cat("VCF region queries (via bcf_read) return variants that OVERLAP the region,\n")
cat("following VCF/BCF indexing rules. This includes variants that start before\n")
cat("or extend past the exact boundaries. Parquet queries use exact position\n")
cat("filtering (POS >= start AND POS <= end), which only counts variants whose\n")
cat("POS falls within the range. Both behaviors are correct for their use case:\n")
cat("  - VCF: Includes overlapping variants (correct for genomic range queries)\n")
cat("  - Parquet: Exact position filtering (faster, simpler SQL queries)\n")
cat(sprintf("\nTotal matches: Parquet=%d, VCF=%d (difference: %d)\n",
           sum(result_parquet$row_count), 
           sum(result_vcf$row_count),
           abs(sum(result_vcf$row_count) - sum(result_parquet$row_count))))

dbDisconnect(con)
RSCRIPT

# Cleanup
echo ""
echo "=== Cleanup ==="
echo "Removing temporary build directory: $BUILD_DIR"
rm -rf "$BUILD_DIR"

echo ""
echo "=============================================="
echo "DuckDB Native Converter Test Complete!"
echo "=============================================="
echo "Output file: $OUT_PQ"
echo "File size: $(du -h $OUT_PQ | cut -f1)"
echo ""
echo "To keep the parquet file, it's at: $OUT_PQ"
echo "To remove it: rm $OUT_PQ"
