SCRIPT=$(Rscript -e "cat(system.file('scripts', 'vcf2parquet.R', package='RBCFTools'))")
BCF=$(Rscript -e "cat(system.file('extdata', '1000G_3samples.bcf', package='RBCFTools'))")
BCF=${1:-"$BCF"}
OUT_PQ=$(echo $BCF | sed -e 's/\.bcf$/.parquet/' -e 's/\.vcf\.gz$/.parquet/' -e 's/\.vcf$/.parquet/')

echo "which Rscript: $(which Rscript)"
# Convert BCF to Parquet (using zstd for better compression than snappy)
[[ -f $OUT_PQ ]] || $SCRIPT convert --batch-size 1000000 --row-group-size 1000000 --streaming -t 10 -c zstd -i $BCF -o $OUT_PQ 

# Query with DuckDB SQL
$SCRIPT query -i $OUT_PQ -q "SELECT CHROM, POS, REF, ALT FROM parquet_scan('$OUT_PQ') LIMIT 5"

# Describe table structure
$SCRIPT query -i $OUT_PQ -q "DESCRIBE SELECT * FROM parquet_scan('$OUT_PQ')"

# Show schema
$SCRIPT schema -i $BCF 

# File info
$SCRIPT info -i $OUT_PQ 

ls -ltrh $OUT_PQ

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
cat(sprintf("\nUsing position column: %s\n", pos_col))

# Get table info
info <- dbGetQuery(con, sprintf(
    "SELECT COUNT(*) as total_rows, MIN(%s) as min_pos, MAX(%s) as max_pos FROM variants",
    pos_col, pos_col
))
cat(sprintf("\nTable statistics:\n"))
cat(sprintf("  Total rows: %d\n", info$total_rows[1]))
cat(sprintf("  Position range: %d - %d\n", info$min_pos[1], info$max_pos[1]))

# Generate interval ranges
num_queries <- 50
intervals <- data.table(
    query_id = seq_len(num_queries),
    start_pos = as.integer(seq(info$min_pos[1], info$max_pos[1] - 1000, length.out = num_queries)),
    end_pos = as.integer(seq(info$min_pos[1] + 1000, info$max_pos[1], length.out = num_queries))
)

cat(sprintf("\n\nRunning %d interval queries via range join...\n", num_queries))
cat("Sample intervals:\n")
print(head(intervals, 5))
cat("\n")

# Register intervals as a table in DuckDB
dbWriteTable(con, "intervals", intervals, overwrite = TRUE)

# === Method 1: Single range join query (DuckDB optimized) ===
cat("\n=== Method 1: Single Range Join Query ===\n")
range_join_start <- Sys.time()

# Use a range join - DuckDB will optimize filter pushdown to parquet
range_join_query <- sprintf("
    SELECT 
        i.query_id,
        COUNT(*) as row_count
    FROM intervals i
    JOIN variants v ON v.%s >= i.start_pos AND v.%s <= i.end_pos
    GROUP BY i.query_id
    ORDER BY i.query_id
", pos_col, pos_col)

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
union_queries <- sapply(seq_len(num_queries), function(i) {
    sprintf("SELECT %d AS query_id, COUNT(*) AS row_count FROM variants WHERE %s >= %d AND %s <= %d",
            i, pos_col, intervals$start_pos[i], pos_col, intervals$end_pos[i])
})
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
    JOIN variants v ON v.%s >= i.start_pos AND v.%s <= i.end_pos
    ORDER BY i.query_id, v.%s
", pos_col, pos_col, pos_col)

all_data <- dbGetQuery(con, fetch_query)
fetch_end <- Sys.time()

cat(sprintf("Fetch all data elapsed time: %.4f seconds\n", 
    as.numeric(difftime(fetch_end, fetch_start, units = "secs"))))
cat(sprintf("Total rows fetched: %d\n", nrow(all_data)))
cat(sprintf("Rows/second: %.0f\n", 
    nrow(all_data) / as.numeric(difftime(fetch_end, fetch_start, units = "secs"))))

# === Summary ===
cat("\n\n=== INTERVAL QUERY TIMING SUMMARY ===\n")
cat(sprintf("Parquet file: %s\n", parquet_file))
cat(sprintf("Total variants: %d\n", info$total_rows[1]))
cat(sprintf("Number of interval queries: %d\n", num_queries))
cat(sprintf("\nMethod 1 (Range Join counts):  %.4f sec (%.2f queries/sec)\n", 
    as.numeric(difftime(range_join_end, range_join_start, units = "secs")),
    num_queries / as.numeric(difftime(range_join_end, range_join_start, units = "secs"))))
cat(sprintf("Method 2 (UNION ALL counts):   %.4f sec (%.2f queries/sec)\n", 
    as.numeric(difftime(union_end, union_start, units = "secs")),
    num_queries / as.numeric(difftime(union_end, union_start, units = "secs"))))
cat(sprintf("Method 3 (Fetch all data):     %.4f sec (%.0f rows/sec)\n", 
    as.numeric(difftime(fetch_end, fetch_start, units = "secs")),
    nrow(all_data) / as.numeric(difftime(fetch_end, fetch_start, units = "secs"))))

dbDisconnect(con)
RSCRIPT

