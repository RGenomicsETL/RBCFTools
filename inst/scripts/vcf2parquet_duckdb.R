#!/usr/bin/env Rscript

# vcf2parquet_duckdb.R - Convert VCF files to Parquet using native DuckDB bcf_reader
# Part of RBCFTools package

suppressPackageStartupMessages({
  library(RBCFTools)
})

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)

show_help <- function() {
  cat(
    "
vcf2parquet_duckdb.R - VCF to Parquet converter using native DuckDB bcf_reader extension

USAGE:
  vcf2parquet_duckdb.R convert [options] -i <input.vcf> -o <output.parquet>
  vcf2parquet_duckdb.R query [options] -i <input.vcf> -q <sql-query>
  vcf2parquet_duckdb.R schema -i <input.vcf>
  vcf2parquet_duckdb.R info -i <file.parquet>

COMMANDS:
  convert          Convert VCF/BCF to Parquet format using DuckDB
  query            Run SQL query directly on VCF/BCF file using DuckDB
  schema           Show DuckDB schema from VCF header
  info             Show Parquet file information

CONVERT OPTIONS:
  -i, --input      Input VCF/BCF file (required)
  -o, --output     Output Parquet file (required)
  -c, --compression  Compression: snappy, gzip, zstd, none (default: zstd)
  -r, --region     Region to extract (e.g., chr1:1000-2000, requires index)
  -t, --threads    Number of parallel threads (default: 1, requires indexed file)
  --columns        Comma-separated column names to include (default: all)
  --row-group-size  Rows per row group (default: 100000)
  --build-dir      Directory to build extension (default: tempdir)
  --ext-path       Path to pre-built extension (skip build step)
  --quiet          Suppress warnings

QUERY OPTIONS:
  -i, --input      Input VCF/BCF file (required)
  -q, --query      SQL query string (required, use bcf_read() function)
  -r, --region     Region to filter (optional)
  -o, --output     Output file (CSV format, default: stdout)
  --build-dir      Directory to build extension (default: tempdir)
  --ext-path       Path to pre-built extension (skip build step)
  --quiet          Suppress warnings

SCHEMA OPTIONS:
  -i, --input      Input VCF file (required)
  --build-dir      Directory to build extension (default: tempdir)
  --ext-path       Path to pre-built extension (skip build step)

INFO OPTIONS:
  -i, --input      Input Parquet file (required)

EXAMPLES:
  # Convert VCF to Parquet
  vcf2parquet_duckdb.R convert -i variants.vcf.gz -o variants.parquet
  
  # Convert with zstd compression
  vcf2parquet_duckdb.R convert -i variants.vcf.gz -o variants.parquet -c zstd
  
  # Convert using 8 parallel threads (requires indexed file)
  vcf2parquet_duckdb.R convert -i variants.vcf.gz -o variants.parquet -t 8
  
  # Convert region only
  vcf2parquet_duckdb.R convert -i variants.vcf.gz -o chr1.parquet -r chr1:1-1000000
  
  # Convert specific columns only
  vcf2parquet_duckdb.R convert -i variants.vcf.gz -o slim.parquet --columns CHROM,POS,REF,ALT
  
  # Show VCF schema
  vcf2parquet_duckdb.R schema -i variants.vcf.gz
  
  # Query VCF file directly with SQL
  vcf2parquet_duckdb.R query -i variants.vcf.gz -q \"SELECT CHROM, COUNT(*) as n FROM bcf_read('{file}') GROUP BY CHROM\"
  
  # Query with region filter
  vcf2parquet_duckdb.R query -i variants.vcf.gz -r chr22 -q \"SELECT * FROM bcf_read('{file}', region := '{region}') LIMIT 10\"
  
  # Query Parquet file
  vcf2parquet_duckdb.R query -i variants.parquet -q \"SELECT CHROM, POS FROM parquet_scan('variants.parquet') WHERE CHROM='chr1'\"

NOTES:
  - This script uses the DuckDB bcf_reader extension for native VCF/BCF reading
  - The extension is built on first use (requires compiler) or can be pre-built
  - Parallel mode requires an indexed VCF/BCF file (.tbi or .csi)
  - Use {file} placeholder in queries to reference the input file
  - Use {region} placeholder in queries to reference the region parameter

DEPENDENCIES:
  - duckdb (for DuckDB database and bcf_reader extension)
  - DBI (for database interface)
  - Compiler (gcc/clang) for building bcf_reader extension

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
      opts$input <- args[i + 1]
      i <- i + 2
    } else if (arg %in% c("-o", "--output")) {
      opts$output <- args[i + 1]
      i <- i + 2
    } else if (arg %in% c("-c", "--compression")) {
      opts$compression <- args[i + 1]
      i <- i + 2
    } else if (arg %in% c("-r", "--region")) {
      opts$region <- args[i + 1]
      i <- i + 2
    } else if (arg %in% c("-t", "--threads")) {
      opts$threads <- as.integer(args[i + 1])
      i <- i + 2
    } else if (arg %in% c("-q", "--query")) {
      opts$query <- args[i + 1]
      i <- i + 2
    } else if (arg == "--columns") {
      opts$columns <- strsplit(args[i + 1], ",")[[1]]
      opts$columns <- trimws(opts$columns)
      i <- i + 2
    } else if (arg == "--row-group-size") {
      opts$row_group_size <- as.integer(args[i + 1])
      i <- i + 2
    } else if (arg == "--build-dir") {
      opts$build_dir <- args[i + 1]
      i <- i + 2
    } else if (arg == "--ext-path") {
      opts$ext_path <- args[i + 1]
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
  opts$compression <- "zstd"
}
if (is.null(opts$threads)) {
  opts$threads <- 1L
}
if (is.null(opts$row_group_size)) {
  opts$row_group_size <- 100000L
}

# Build or locate extension
get_extension_path <- function(opts) {
  # If pre-built path provided, use it
  if (!is.null(opts$ext_path)) {
    if (!file.exists(opts$ext_path)) {
      cat("Error: Extension not found at:", opts$ext_path, "\n")
      quit(status = 1)
    }
    return(opts$ext_path)
  }

  # Otherwise build it
  build_dir <- if (!is.null(opts$build_dir)) {
    opts$build_dir
  } else {
    tempdir()
  }

  cat("Building bcf_reader extension...\n")
  cat("  Build directory:", build_dir, "\n")

  tryCatch(
    {
      ext_path <- bcf_reader_build(build_dir, verbose = TRUE)
      cat("✓ Extension ready:", ext_path, "\n\n")
      return(ext_path)
    },
    error = function(e) {
      cat("\n✗ Error building extension:", e$message, "\n")
      cat("\nMake sure you have a C compiler installed (gcc/clang)\n")
      quit(status = 1)
    }
  )
}

# Command implementations
cmd_convert <- function(opts) {
  if (is.null(opts$input) || is.null(opts$output)) {
    cat("Error: -i/--input and -o/--output are required for convert\n")
    quit(status = 1)
  }

  ext_path <- get_extension_path(opts)
  threads <- opts$threads
  if (!is.null(opts$region) && threads > 1) {
    cat("  Region requested; using single-threaded mode to honor region filter.\n")
    threads <- 1L
  }

  cat("Converting VCF to Parquet (DuckDB mode)...\n")
  cat("  Input:", opts$input, "\n")
  cat("  Output:", opts$output, "\n")
  cat("  Compression:", opts$compression, "\n")
  cat("  Row group size:", opts$row_group_size, "\n")
  cat("  Threads:", threads, "\n")
  if (!is.null(opts$region)) {
    cat("  Region:", opts$region, "\n")
  }
  if (!is.null(opts$columns)) {
    cat("  Columns:", paste(opts$columns, collapse = ", "), "\n")
  }

  start_time <- Sys.time()

  tryCatch(
    {
      vcf_to_parquet_duckdb(
        input_file = opts$input,
        output_file = opts$output,
        extension_path = ext_path,
        columns = opts$columns,
        region = opts$region,
        compression = opts$compression,
        row_group_size = opts$row_group_size,
        threads = threads
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

  # Check if input is VCF or Parquet
  is_vcf <- grepl("\\.(vcf|bcf)(\\.gz)?$", opts$input, ignore.case = TRUE)

  if (is_vcf) {
    ext_path <- get_extension_path(opts)

    cat("Running query on VCF/BCF file (DuckDB mode)...\n")

    # Replace placeholders in query
    query <- opts$query
    query <- gsub("\\{file\\}", opts$input, query, fixed = FALSE)
    if (!is.null(opts$region)) {
      query <- gsub("\\{region\\}", opts$region, query, fixed = FALSE)
    }

    tryCatch(
      {
        result <- vcf_query_duckdb(
          file = opts$input,
          extension_path = ext_path,
          query = query,
          region = opts$region
        )

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
  } else {
    # Parquet file - use DuckDB directly
    if (!requireNamespace("duckdb", quietly = TRUE)) {
      cat("Error: duckdb package is required\n")
      quit(status = 1)
    }

    cat("Running query on Parquet file...\n")

    tryCatch(
      {
        con <- duckdb::dbConnect(duckdb::duckdb())
        on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

        result <- DBI::dbGetQuery(con, opts$query)

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
}

cmd_schema <- function(opts) {
  if (is.null(opts$input)) {
    cat("Error: -i/--input is required for schema\n")
    quit(status = 1)
  }

  ext_path <- get_extension_path(opts)

  cat("VCF DuckDB Schema for:", opts$input, "\n\n")

  tryCatch(
    {
      schema <- vcf_schema_duckdb(opts$input, extension_path = ext_path)
      print(schema, row.names = FALSE)
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
  cat("Run 'vcf2parquet_duckdb.R --help' for usage\n")
  quit(status = 1)
}
