#!/usr/bin/env Rscript

# vcf2parquet.R - Convert VCF files to Parquet format and query them
# Part of RBCFTools package

suppressPackageStartupMessages({
    library(RBCFTools)
})

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)

show_help <- function() {
    cat(
        "
vcf2parquet.R - VCF to Parquet converter and query tool

USAGE:
  vcf2parquet.R convert [options] -i <input.vcf> -o <output.parquet>
  vcf2parquet.R query [options] -i <input.parquet> -q <sql-query>
  vcf2parquet.R schema -i <input.vcf>
  vcf2parquet.R info -i <file.parquet>

COMMANDS:
  convert          Convert VCF/BCF to Parquet format
  query            Run SQL query on Parquet file
  schema           Show Arrow schema from VCF header
  info             Show Parquet file information

CONVERT OPTIONS:
  -i, --input      Input VCF/BCF file (required)
  -o, --output     Output Parquet file (required)
  -c, --compression  Compression: snappy, gzip, zstd, lz4, uncompressed (default: snappy)
  -b, --batch-size   Number of records per batch (default: 10000)
  -r, --region     Region to extract (e.g., chr1:1000-2000)
  -s, --samples    Sample filter (comma-separated or file)
  -t, --threads    Number of parallel threads (default: 1, requires indexed file)
  --streaming      Use streaming mode for large files
  --no-info        Exclude INFO fields
  --no-format      Exclude FORMAT/sample data
  --row-group-size  Rows per row group (default: 100000)
  --quiet          Suppress warnings

QUERY OPTIONS:
  -i, --input      Input Parquet file(s) (required, can be multiple)
  -q, --query      SQL query string (required)
  -o, --output     Output file (CSV format, default: stdout)
  --quiet          Suppress warnings

SCHEMA OPTIONS:
  -i, --input      Input VCF file (required)

INFO OPTIONS:
  -i, --input      Input Parquet file (required)

EXAMPLES:
  # Convert VCF to Parquet
  vcf2parquet.R convert -i variants.vcf.gz -o variants.parquet
  
  # Convert with gzip compression
  vcf2parquet.R convert -i variants.vcf.gz -o variants.parquet -c gzip
  
  # Convert using 8 parallel threads (requires indexed file)
  vcf2parquet.R convert -i variants.vcf.gz -o variants.parquet -t 8
  
  # Convert region only
  vcf2parquet.R convert -i variants.vcf.gz -o chr1.parquet -r chr1:1-1000000
  
  # Convert in streaming mode (large files)
  vcf2parquet.R convert -i huge.vcf.gz -o huge.parquet --streaming
  
  # Parallel + streaming for massive files
  vcf2parquet.R convert -i huge.vcf.gz -o huge.parquet -t 16 --streaming
  
  # Show VCF schema
  vcf2parquet.R schema -i variants.vcf.gz
  
  # Query Parquet file
  vcf2parquet.R query -i variants.parquet -q \"SELECT CHROM, POS, REF, ALT FROM parquet_scan('variants.parquet') WHERE CHROM='chr1' LIMIT 10\"
  
  # Query multiple files
  vcf2parquet.R query -i file1.parquet -i file2.parquet -q \"SELECT COUNT(*) FROM variants\"
  
  # Query with output to CSV
  vcf2parquet.R query -i variants.parquet -q \"SELECT * FROM variants WHERE QUAL > 30\" -o filtered.csv

DEPENDENCIES:
  - duckdb (for Parquet operations and queries)
  - nanoarrow (for Arrow format support)

"
    )
    quit(status = 0)
}

if (length(args) == 0 || args[1] %in% c("-h", "--help", "help")) {
    show_help()
}

command <- args[1]
args <- args[-1]

# Parse arguments
parse_args <- function(args) {
    opts <- list()
    i <- 1
    while (i <= length(args)) {
        arg <- args[i]
        if (arg %in% c("-i", "--input")) {
            if (is.null(opts$input)) {
                opts$input <- character(0)
            }
            opts$input <- c(opts$input, args[i + 1])
            i <- i + 2
        } else if (arg %in% c("-o", "--output")) {
            opts$output <- args[i + 1]
            i <- i + 2
        } else if (arg %in% c("-c", "--compression")) {
            opts$compression <- args[i + 1]
            i <- i + 2
        } else if (arg %in% c("-b", "--batch-size")) {
            opts$batch_size <- as.integer(args[i + 1])
            i <- i + 2
        } else if (arg %in% c("-r", "--region")) {
            opts$region <- args[i + 1]
            i <- i + 2
        } else if (arg %in% c("-s", "--samples")) {
            opts$samples <- args[i + 1]
            i <- i + 2
        } else if (arg %in% c("-t", "--threads")) {
            opts$threads <- as.integer(args[i + 1])
            i <- i + 2
        } else if (arg %in% c("-q", "--query")) {
            opts$query <- args[i + 1]
            i <- i + 2
        } else if (arg == "--streaming") {
            opts$streaming <- TRUE
            i <- i + 1
        } else if (arg == "--no-info") {
            opts$include_info <- FALSE
            i <- i + 1
        } else if (arg == "--no-format") {
            opts$include_format <- FALSE
            i <- i + 1
        } else if (arg == "--row-group-size") {
            opts$row_group_size <- as.integer(args[i + 1])
            i <- i + 2
        } else if (arg == "--quiet") {
            opts$quiet <- TRUE
            i <- i + 1
        } else {
            cat("Unknown option:", arg, "\n")
            quit(status = 1)
        }
    }
    opts
}

opts <- parse_args(args)

# Set quiet mode if requested
if (!is.null(opts$quiet) && opts$quiet) {
    options(warn = -1)
}

# Set defaults
if (is.null(opts$compression)) {
    opts$compression <- "snappy"
}
if (is.null(opts$batch_size)) {
    opts$batch_size <- 10000L
}
if (is.null(opts$include_info)) {
    opts$include_info <- TRUE
}
if (is.null(opts$include_format)) {
    opts$include_format <- TRUE
}
if (is.null(opts$streaming)) {
    opts$streaming <- FALSE
}
if (is.null(opts$threads)) {
    opts$threads <- 1L
}
if (is.null(opts$row_group_size)) {
    opts$row_group_size <- 100000L
}

# Command implementations
cmd_convert <- function(opts) {
    if (is.null(opts$input) || is.null(opts$output)) {
        cat("Error: -i/--input and -o/--output are required for convert\n")
        quit(status = 1)
    }

    cat("Converting VCF to Parquet...\n")
    cat("  Input:", opts$input, "\n")
    cat("  Output:", opts$output, "\n")
    cat("  Compression:", opts$compression, "\n")
    cat("  Batch size:", opts$batch_size, "\n")
    cat("  Threads:", opts$threads, "\n")
    if (!is.null(opts$region)) {
        cat("  Region:", opts$region, "\n")
    }
    if (!is.null(opts$samples)) {
        cat("  Samples:", opts$samples, "\n")
    }
    cat("  Streaming:", opts$streaming, "\n")
    cat("  Include INFO:", opts$include_info, "\n")
    cat("  Include FORMAT:", opts$include_format, "\n")

    start_time <- Sys.time()

    tryCatch(
        {
            vcf_to_parquet(
                input_vcf = opts$input,
                output_parquet = opts$output,
                compression = opts$compression,
                row_group_size = opts$row_group_size,
                streaming = opts$streaming,
                threads = opts$threads,
                batch_size = opts$batch_size,
                region = opts$region,
                samples = opts$samples,
                include_info = opts$include_info,
                include_format = opts$include_format
            )

            elapsed <- as.numeric(difftime(
                Sys.time(),
                start_time,
                units = "secs"
            ))
            file_size <- file.info(opts$output)$size / 1024 / 1024

            cat("\n✓ Conversion complete!\n")
            cat("  Time:", sprintf("%.2f", elapsed), "seconds\n")
            cat("  Output size:", sprintf("%.2f", file_size), "MB\n")
        },
        error = function(e) {
            cat("\n✗ Error:", e$message, "\n")
            quit(status = 1)
        }
    )
}

cmd_query <- function(opts) {
    if (is.null(opts$input) || is.null(opts$query)) {
        cat("Error: -i/--input and -q/--query are required for query\n")
        quit(status = 1)
    }

    if (!requireNamespace("duckdb", quietly = TRUE)) {
        cat("Error: duckdb package is required for query command\n")
        cat("Install with: install.packages('duckdb')\n")
        quit(status = 1)
    }

    cat("Running query on Parquet file(s)...\n")

    tryCatch(
        {
            con <- duckdb::dbConnect(duckdb::duckdb())
            on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

            # Register input files
            if (length(opts$input) == 1) {
                # Single file - can use parquet_scan directly in query
                result <- DBI::dbGetQuery(con, opts$query)
            } else {
                # Multiple files - register as table
                query_with_union <- paste(
                    "SELECT * FROM parquet_scan([",
                    paste0("'", opts$input, "'", collapse = ", "),
                    "])"
                )
                duckdb::duckdb_register(
                    con,
                    "variants",
                    dbGetQuery(con, query_with_union)
                )
                result <- DBI::dbGetQuery(con, opts$query)
            }

            if (!is.null(opts$output)) {
                write.csv(result, opts$output, row.names = FALSE)
                cat("✓ Results written to:", opts$output, "\n")
                cat("  Rows:", nrow(result), "\n")
            } else {
                print(result)
            }
        },
        error = function(e) {
            cat("\n✗ Error:", e$message, "\n")
            quit(status = 1)
        }
    )
}

cmd_schema <- function(opts) {
    if (is.null(opts$input)) {
        cat("Error: -i/--input is required for schema\n")
        quit(status = 1)
    }

    cat("VCF Arrow Schema for:", opts$input, "\n\n")

    tryCatch(
        {
            schema <- vcf_arrow_schema(opts$input)
            print(schema)
        },
        error = function(e) {
            cat("\n✗ Error:", e$message, "\n")
            quit(status = 1)
        }
    )
}

cmd_info <- function(opts) {
    if (is.null(opts$input)) {
        cat("Error: -i/--input is required for info\n")
        quit(status = 1)
    }

    if (!requireNamespace("duckdb", quietly = TRUE)) {
        cat("Error: duckdb package is required for info command\n")
        cat("Install with: install.packages('duckdb')\n")
        quit(status = 1)
    }

    cat("Parquet File Information:", opts$input, "\n\n")

    tryCatch(
        {
            con <- duckdb::dbConnect(duckdb::duckdb())
            on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

            # Get schema
            schema_info <- DBI::dbGetQuery(
                con,
                sprintf(
                    "SELECT * FROM parquet_schema('%s')",
                    opts$input
                )
            )

            # Get file stats
            stats <- DBI::dbGetQuery(
                con,
                sprintf(
                    "SELECT COUNT(*) as row_count FROM parquet_scan('%s')",
                    opts$input
                )
            )

            file_size <- file.info(opts$input)$size

            cat("File size:", sprintf("%.2f MB", file_size / 1024 / 1024), "\n")
            cat("Total rows:", stats$row_count, "\n")
            cat("Number of columns:", nrow(schema_info), "\n\n")

            cat("Schema (top-level columns):\n")
            # Filter to show meaningful columns
            top_level <- schema_info[
                !grepl("^(list|element|duckdb_)", schema_info$name),
            ]
            print(
                top_level[, c("name", "type")],
                row.names = FALSE
            )
        },
        error = function(e) {
            cat("\n✗ Error:", e$message, "\n")
            quit(status = 1)
        }
    )
}

# Execute command
if (command == "convert") {
    cmd_convert(opts)
} else if (command == "query") {
    cmd_query(opts)
} else if (command == "schema") {
    cmd_schema(opts)
} else if (command == "info") {
    cmd_info(opts)
} else {
    cat("Unknown command:", command, "\n")
    cat("Run 'vcf2parquet.R --help' for usage\n")
    quit(status = 1)
}
