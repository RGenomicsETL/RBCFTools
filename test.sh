SCRIPT=$(Rscript -e "cat(system.file('scripts', 'vcf2parquet.R', package='RBCFTools'))")
BCF=$(Rscript -e "cat(system.file('extdata', '1000G_3samples.bcf', package='RBCFTools'))")
BCF=${1:-"$BCF"}
OUT_PQ=$(echo $BCF | sed -e 's/\.bcf$/.parquet/' -e 's/\.vcf\.gz$/.parquet/' -e 's/\.vcf$/.parquet/')
threads=10

echo "which Rscript: $(which Rscript)"
# Convert BCF to Parquet (using zstd for better compression than snappy)
[[ -f $OUT_PQ ]] || $SCRIPT convert \
    --batch-size 1000000 --row-group-size 1000000 --streaming -t $threads -c zstd -i $BCF -o $OUT_PQ 

# Query with DuckDB SQL
$SCRIPT query -i $OUT_PQ -q "SELECT CHROM, POS, REF, ALT FROM parquet_scan('$OUT_PQ') LIMIT 5"

# Describe table structure
$SCRIPT query -i $OUT_PQ -q "DESCRIBE SELECT * FROM parquet_scan('$OUT_PQ')"

# Show schema
$SCRIPT schema -i $BCF 

# File info
$SCRIPT info -i $OUT_PQ 

# Interval query timing tests with R/DuckDB
Rscript - "$OUT_PQ" << 'RSCRIPT'
library(duckdb)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)
parquet_file <- args[1]

if (!file.exists(parquet_file)) {
    cat(sprintf("Warning: Parquet file not found at %s\n", parquet_file))
    quit(save = "no", status = 0)
}

cat(sprintf("Using parquet file: %s\n", parquet_file))

# Connect to DuckDB
con <- dbConnect(duckdb())

# Register parquet file as a view (enables pushdown optimization)
dbExecute(con, sprintf("CREATE VIEW variants AS SELECT * FROM '%s'", parquet_file))
cat("Registered parquet file as 'variants' view\n")

# Get schema
schema <- dbGetQuery(con, "DESCRIBE SELECT * FROM variants")
cat(sprintf("\nParquet file schema:\n"))
print(schema)

# Identify position column (look for POS, position, or similar)
col_names <- tolower(schema$column_name)
pos_col <- schema$column_name[grep("pos", col_names)]
if (length(pos_col) == 0) {
    cat("Error: No position-like column found in parquet file\n")
    dbDisconnect(con)
    quit(save = "no", status = 1)
}
pos_col <- pos_col[1]

# Identify chromosome column
chrom_col <- schema$column_name[grep("chrom", col_names)]
if (length(chrom_col) == 0) {
    chrom_col <- NULL
    cat("No chromosome column found, using position-only intervals\n")
} else {
    chrom_col <- chrom_col[1]
}
cat(sprintf("Using position column: %s\n", pos_col))
if (!is.null(chrom_col)) cat(sprintf("Using chromosome column: %s\n", chrom_col))

# Get table info per chromosome
if (!is.null(chrom_col)) {
    chrom_stats <- dbGetQuery(con, sprintf(
        "SELECT %s as chrom, COUNT(*) as n_variants, MIN(%s) as min_pos, MAX(%s) as max_pos 
         FROM variants GROUP BY %s ORDER BY %s",
        chrom_col, pos_col, pos_col, chrom_col, chrom_col
    ))
    cat(sprintf("\nChromosome statistics (%d chromosomes):\n", nrow(chrom_stats)))
    print(head(chrom_stats, 10))
    if (nrow(chrom_stats) > 10) cat(sprintf("... and %d more chromosomes\n", nrow(chrom_stats) - 10))
} else {
    chrom_stats <- NULL
}

# Get overall table info
info <- dbGetQuery(con, sprintf(
    "SELECT COUNT(*) as total_rows, MIN(%s) as min_pos, MAX(%s) as max_pos FROM variants",
    pos_col, pos_col
))
cat(sprintf("\nTable statistics:\n"))
cat(sprintf("  Total rows: %d\n", info$total_rows[1]))
cat(sprintf("  Position range: %d - %d\n", info$min_pos[1], info$max_pos[1]))

# Generate interval ranges spread across chromosomes
num_intervals_per_chrom <- 100  # intervals per chromosome
interval_width <- 10000  # 10kb intervals

if (!is.null(chrom_col) && nrow(chrom_stats) > 1) {
    # Generate intervals for each chromosome
    intervals_list <- lapply(seq_len(nrow(chrom_stats)), function(i) {
        chr <- chrom_stats$chrom[i]
        min_p <- chrom_stats$min_pos[i]
        max_p <- chrom_stats$max_pos[i]
        
        # Generate evenly spaced start positions across the chromosome
        starts <- as.integer(seq(min_p, max(min_p, max_p - interval_width), length.out = num_intervals_per_chrom))
        
        data.table(
            chrom = chr,
            start_pos = starts,
            end_pos = starts + interval_width
        )
    })
    intervals <- rbindlist(intervals_list)
    intervals[, query_id := .I]
    setcolorder(intervals, c("query_id", "chrom", "start_pos", "end_pos"))
} else {
    # No chromosome column - generate position-only intervals
    num_queries <- 500
    starts <- as.integer(seq(info$min_pos[1], max(info$min_pos[1], info$max_pos[1] - interval_width), length.out = num_queries))
    intervals <- data.table(
        query_id = seq_len(num_queries),
        start_pos = starts,
        end_pos = starts + interval_width
    )
}

num_queries <- nrow(intervals)
cat(sprintf("\n\nGenerated %d interval queries", num_queries))
if (!is.null(chrom_col) && nrow(chrom_stats) > 1) {
    cat(sprintf(" across %d chromosomes\n", nrow(chrom_stats)))
} else {
    cat("\n")
}

cat(sprintf("\n\nRunning %d interval queries via range join...\n", num_queries))
cat("Sample intervals:\n")
print(head(intervals, 10))
cat("\n")

# Register intervals as a table in DuckDB
dbWriteTable(con, "intervals", intervals, overwrite = TRUE)

# Build join condition based on whether we have chromosome column
if (!is.null(chrom_col) && "chrom" %in% names(intervals)) {
    join_condition <- sprintf("v.%s = i.chrom AND v.%s >= i.start_pos AND v.%s <= i.end_pos",
                              chrom_col, pos_col, pos_col)
} else {
    join_condition <- sprintf("v.%s >= i.start_pos AND v.%s <= i.end_pos", pos_col, pos_col)
}

# === Method 1: Single range join query (DuckDB optimized) ===
cat("\n=== Method 1: Single Range Join Query ===\n")
range_join_start <- Sys.time()

# Use a range join - DuckDB will optimize filter pushdown to parquet
range_join_query <- sprintf("
    SELECT 
        i.query_id,
        COUNT(*) as row_count
    FROM intervals i
    JOIN variants v ON %s
    GROUP BY i.query_id
    ORDER BY i.query_id
", join_condition)

result <- dbGetQuery(con, range_join_query)
range_join_end <- Sys.time()

cat(sprintf("Range join elapsed time: %.4f seconds\n", 
    as.numeric(difftime(range_join_end, range_join_start, units = "secs"))))
cat(sprintf("Total rows matched: %d\n", sum(result$row_count)))
cat(sprintf("Mean rows per query: %.1f\n", mean(result$row_count)))
cat(sprintf("Queries/second: %.2f\n", 
    num_queries / as.numeric(difftime(range_join_end, range_join_start, units = "secs"))))

# === Method 2: UNION ALL of interval queries (parallel execution) ===
cat("\n=== Method 2: UNION ALL Parallel Queries ===\n")
union_start <- Sys.time()

# Build a single query with UNION ALL for all intervals
if (!is.null(chrom_col) && "chrom" %in% names(intervals)) {
    union_queries <- sapply(seq_len(num_queries), function(i) {
        sprintf("SELECT %d AS query_id, COUNT(*) AS row_count FROM variants WHERE %s = '%s' AND %s >= %d AND %s <= %d",
                i, chrom_col, intervals$chrom[i], pos_col, intervals$start_pos[i], pos_col, intervals$end_pos[i])
    })
} else {
    union_queries <- sapply(seq_len(num_queries), function(i) {
        sprintf("SELECT %d AS query_id, COUNT(*) AS row_count FROM variants WHERE %s >= %d AND %s <= %d",
                i, pos_col, intervals$start_pos[i], pos_col, intervals$end_pos[i])
    })
}
union_query <- paste(union_queries, collapse = " UNION ALL ")

result2 <- dbGetQuery(con, union_query)
union_end <- Sys.time()

cat(sprintf("UNION ALL elapsed time: %.4f seconds\n", 
    as.numeric(difftime(union_end, union_start, units = "secs"))))
cat(sprintf("Total rows matched: %d\n", sum(result2$row_count)))
cat(sprintf("Queries/second: %.2f\n", 
    num_queries / as.numeric(difftime(union_end, union_start, units = "secs"))))

# === Method 3: Fetch actual data (not just counts) ===
cat("\n=== Method 3: Fetch All Matching Rows ===\n")
fetch_start <- Sys.time()

fetch_query <- sprintf("
    SELECT 
        i.query_id,
        v.*
    FROM intervals i
    JOIN variants v ON %s
    ORDER BY i.query_id, v.%s
", join_condition, pos_col)

all_data <- dbGetQuery(con, fetch_query)
fetch_end <- Sys.time()

cat(sprintf("Fetch all data elapsed time: %.4f seconds\n", 
    as.numeric(difftime(fetch_end, fetch_start, units = "secs"))))
cat(sprintf("Total rows fetched: %d\n", nrow(all_data)))
if (nrow(all_data) > 0) {
    cat(sprintf("Rows/second: %.0f\n", 
        nrow(all_data) / as.numeric(difftime(fetch_end, fetch_start, units = "secs"))))
}

# === Summary ===
cat("\n\n=== INTERVAL QUERY TIMING SUMMARY ===\n")
cat(sprintf("Parquet file: %s\n", parquet_file))
cat(sprintf("Total variants: %d\n", info$total_rows[1]))
if (!is.null(chrom_col) && !is.null(chrom_stats)) {
    cat(sprintf("Chromosomes: %d\n", nrow(chrom_stats)))
}
cat(sprintf("Number of interval queries: %d\n", num_queries))
cat(sprintf("Interval width: %d bp\n", interval_width))
cat(sprintf("\nMethod 1 (Range Join counts):  %.4f sec (%.2f queries/sec)\n", 
    as.numeric(difftime(range_join_end, range_join_start, units = "secs")),
    num_queries / as.numeric(difftime(range_join_end, range_join_start, units = "secs"))))
cat(sprintf("Method 2 (UNION ALL counts):   %.4f sec (%.2f queries/sec)\n", 
    as.numeric(difftime(union_end, union_start, units = "secs")),
    num_queries / as.numeric(difftime(union_end, union_start, units = "secs"))))
fetch_time <- as.numeric(difftime(fetch_end, fetch_start, units = "secs"))
if (nrow(all_data) > 0 && fetch_time > 0) {
    cat(sprintf("Method 3 (Fetch all data):     %.4f sec (%.0f rows/sec)\n", fetch_time,
        nrow(all_data) / fetch_time))
} else {
    cat(sprintf("Method 3 (Fetch all data):     %.4f sec (no rows matched)\n", fetch_time))
}

dbDisconnect(con)
RSCRIPT

