# DuckDB R UDF Extension - Makefile
# Self-contained build without CMake
#
# Usage:
#   make                              - Build the extension
#   make clean                        - Clean build artifacts
#   make test                         - Run basic tests
#   make install                      - Install to ~/.duckdb/extensions
#
# Requirements:
#   - GCC or Clang
#   - R development headers (R.h, Rinternals.h)
#   - DuckDB v1.2.0+

# Extension configuration
EXTENSION_NAME ?= r_udf
DUCKDB_VERSION ?= v1.2.0
EXTENSION_VERSION ?= 1.0.0

# Detect platform
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Linux)
    ifeq ($(UNAME_M),x86_64)
        PLATFORM := linux_amd64
    else ifeq ($(UNAME_M),aarch64)
        PLATFORM := linux_arm64
    endif
    SHARED_EXT := .so
    SHARED_FLAGS := -shared -fPIC
else ifeq ($(UNAME_S),Darwin)
    ifeq ($(UNAME_M),x86_64)
        PLATFORM := osx_amd64
    else ifeq ($(UNAME_M),arm64)
        PLATFORM := osx_arm64
    endif
    SHARED_EXT := .dylib
    SHARED_FLAGS := -shared -fPIC -undefined dynamic_lookup
endif

# Compiler settings
CC := gcc
CFLAGS := -O2 -Wall -Wextra -Wno-unused-parameter -fPIC
INCLUDES := -I.

# R configuration
# Use R's own include path but simplify linking to just -lR
R_HOME := $(shell R RHOME 2>/dev/null)
ifdef R_HOME
    R_INCLUDE := $(shell $(R_HOME)/bin/R CMD config --cppflags 2>/dev/null)
    R_LIB_DIR := $(R_HOME)/lib
else
    R_INCLUDE :=
    R_LIB_DIR :=
endif

# If R_INCLUDE not found, try common locations
ifeq ($(R_INCLUDE),)
    ifneq ($(wildcard /usr/share/R/include/R.h),)
        R_INCLUDE := -I/usr/share/R/include
        R_LIB_DIR := /usr/lib/R/lib
    else ifneq ($(wildcard /usr/local/include/R.h),)
        R_INCLUDE := -I/usr/local/include
        R_LIB_DIR := /usr/local/lib
    endif
endif

CFLAGS += $(R_INCLUDE)
# Simple R linking - just the core R library, not all dependencies
LDFLAGS := -L$(R_LIB_DIR) -Wl,-rpath,$(R_LIB_DIR) -lR

# Build output
BUILD_DIR := build
SHARED_LIB := $(BUILD_DIR)/$(EXTENSION_NAME)$(SHARED_EXT)
OUTPUT := $(BUILD_DIR)/$(EXTENSION_NAME).duckdb_extension

# Source files
SOURCES := r_udf.c
OBJECTS := $(SOURCES:%.c=$(BUILD_DIR)/%.o)

# DuckDB extension header (copy from bcf_reader if not present)
DUCKDB_HEADERS := duckdb.h duckdb_extension.h

.PHONY: all clean install test check-r

all: check-r $(OUTPUT)

check-r:
	@if [ -z "$(R_INCLUDE)" ]; then \
		echo "Error: R development headers not found"; \
		echo "Please install R development package:"; \
		echo "  Ubuntu/Debian: sudo apt-get install r-base-dev"; \
		echo "  RHEL/CentOS: sudo yum install R-devel"; \
		echo "  macOS: R headers should be included with R installation"; \
		exit 1; \
	fi
	@echo "R include: $(R_INCLUDE)"
	@echo "R ldflags: $(R_LDFLAGS)"

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Copy DuckDB headers from bcf_reader if not present
duckdb.h:
	@if [ ! -f duckdb.h ]; then \
		if [ -f ../duckdb_bcf_reader_extension/duckdb.h ]; then \
			cp ../duckdb_bcf_reader_extension/duckdb.h .; \
		else \
			echo "Error: duckdb.h not found"; \
			exit 1; \
		fi \
	fi

duckdb_extension.h:
	@if [ ! -f duckdb_extension.h ]; then \
		if [ -f ../duckdb_bcf_reader_extension/duckdb_extension.h ]; then \
			cp ../duckdb_bcf_reader_extension/duckdb_extension.h .; \
		else \
			echo "Error: duckdb_extension.h not found"; \
			exit 1; \
		fi \
	fi

$(BUILD_DIR)/%.o: %.c $(DUCKDB_HEADERS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(SHARED_LIB): $(OBJECTS)
	$(CC) $(SHARED_FLAGS) -o $@ $^ $(LDFLAGS)

# Append DuckDB extension metadata
$(OUTPUT): $(SHARED_LIB)
	@echo "Creating DuckDB extension with metadata..."
	@chmod +x append_metadata.sh
	@./append_metadata.sh $(SHARED_LIB) $(OUTPUT) "$(PLATFORM)" "$(DUCKDB_VERSION)" "$(EXTENSION_VERSION)"
	@echo "Built: $@"
	@ls -la $@

clean:
	rm -rf $(BUILD_DIR)
	rm -f *.o

install: $(OUTPUT)
	@INSTALL_DIR=~/.duckdb/extensions/$(DUCKDB_VERSION)/$(PLATFORM); \
	mkdir -p $$INSTALL_DIR; \
	cp $(OUTPUT) $$INSTALL_DIR/$(EXTENSION_NAME).duckdb_extension; \
	echo "Installed to: $$INSTALL_DIR/$(EXTENSION_NAME).duckdb_extension"

# Test the extension with DuckDB
test: $(OUTPUT)
	@echo "Testing r_udf extension..."
	@R --quiet -e " \
		library(duckdb); \
		drv <- duckdb(config = list('allow_unsigned_extensions' = 'true')); \
		con <- dbConnect(drv); \
		tryCatch({ \
			dbExecute(con, \"LOAD '$(shell pwd)/$(OUTPUT)'\"); \
			cat('Extension loaded successfully\n'); \
			result <- dbGetQuery(con, \"SELECT * FROM r_eval('1+1')\"); \
			cat('r_eval(1+1) = ', result[[1]], '\n'); \
			result <- dbGetQuery(con, \"SELECT * FROM r_eval('R.version.string')\"); \
			cat('R version: ', result[[1]], '\n'); \
		}, error = function(e) { \
			cat('Error:', conditionMessage(e), '\n'); \
			quit(status = 1); \
		}); \
		dbDisconnect(con); \
	"
	@echo "All tests passed!"

# Print configuration
info:
	@echo "Extension: $(EXTENSION_NAME)"
	@echo "Version: $(EXTENSION_VERSION)"
	@echo "Platform: $(PLATFORM)"
	@echo "R_HOME: $(R_HOME)"
	@echo "R_INCLUDE: $(R_INCLUDE)"
	@echo "R_LIB_DIR: $(R_LIB_DIR)"
	@echo "LDFLAGS: $(LDFLAGS)"
	@echo "Output: $(OUTPUT)"
