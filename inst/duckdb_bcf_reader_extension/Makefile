# DuckDB BCF/VCF Reader Extension - Makefile
# Self-contained build without CMake
#
# Usage:
#   make                              - Build the extension (uses system htslib)
#   make RBCFTOOLS_HTSLIB=1           - Build using RBCFTools package htslib
#   make clean                        - Clean build artifacts
#   make test                         - Run basic tests
#   make install                      - Install to ~/.duckdb/extensions
#
# The extension is designed to be built as part of RBCFTools package configure,
# using the package's bundled htslib for maximum portability.
#
# Requirements:
#   - GCC or Clang
#   - htslib (from RBCFTools or system pkg-config)
#   - DuckDB v1.2.0+

# Extension configuration (can be overridden: make DUCKDB_VERSION=v1.5.0)
EXTENSION_NAME ?= bcf_reader
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

# ============================================================================
# htslib configuration
# Priority: HTSLIB_INCLUDE/LIB direct > RBCFTOOLS_HTSLIB > HTSLIB_STATIC > pkg-config > system defaults
# ============================================================================

# Option 0: Direct HTSLIB_INCLUDE and HTSLIB_LIB paths (highest priority)
# Used when building from R with explicit paths
ifdef HTSLIB_INCLUDE
ifdef HTSLIB_LIB
    CFLAGS += -I$(HTSLIB_INCLUDE)
    # Prefer dynamic linking for plugin support (S3, GCS, HTTP)
    # Static linking breaks htslib plugins needed for remote file access
    ifneq ($(wildcard $(HTSLIB_LIB)/libhts.so),)
        LDFLAGS := -L$(HTSLIB_LIB) -Wl,-rpath,$(HTSLIB_LIB) -lhts
    else ifneq ($(wildcard $(HTSLIB_LIB)/libhts.dylib),)
        LDFLAGS := -L$(HTSLIB_LIB) -Wl,-rpath,$(HTSLIB_LIB) -lhts
    else ifneq ($(wildcard $(HTSLIB_LIB)/libhts.a),)
        # Fall back to static only if no shared lib available
        LDFLAGS := $(HTSLIB_LIB)/libhts.a -lz -lbz2 -llzma -lcurl -lpthread
        ifdef USE_DEFLATE
            LDFLAGS += -ldeflate
        endif
    endif
    # Mark as configured to skip other options
    HTSLIB_CONFIGURED := 1
endif
endif

# Option 1: Use RBCFTools package htslib (recommended for package builds)
# Set RBCFTOOLS_HTSLIB=1 and optionally RBCFTOOLS_ROOT to package root
ifndef HTSLIB_CONFIGURED
ifdef RBCFTOOLS_HTSLIB
    # Default to parent directories if not specified
    RBCFTOOLS_ROOT ?= ../..
    HTSLIB_DIR := $(RBCFTOOLS_ROOT)/inst/htslib
    HTSLIB_INCLUDE := $(HTSLIB_DIR)/include
    HTSLIB_LIB := $(HTSLIB_DIR)/lib
    
    # Check if the directories exist
    ifneq ($(wildcard $(HTSLIB_INCLUDE)/htslib),)
        CFLAGS += -I$(HTSLIB_INCLUDE)
        # Prefer dynamic linking for plugin support (S3, GCS, HTTP)
        ifneq ($(wildcard $(HTSLIB_LIB)/libhts.so),)
            LDFLAGS := -L$(HTSLIB_LIB) -Wl,-rpath,$(HTSLIB_LIB) -lhts
        else ifneq ($(wildcard $(HTSLIB_LIB)/libhts.dylib),)
            LDFLAGS := -L$(HTSLIB_LIB) -Wl,-rpath,$(HTSLIB_LIB) -lhts
        else ifneq ($(wildcard $(HTSLIB_LIB)/libhts.a),)
            LDFLAGS := $(HTSLIB_LIB)/libhts.a -lz -lbz2 -llzma -lcurl -lpthread
            ifdef USE_DEFLATE
                LDFLAGS += -ldeflate
            endif
        endif
        HTSLIB_CONFIGURED := 1
    else
        $(warning RBCFTools htslib not found at $(HTSLIB_INCLUDE), falling back to pkg-config)
        RBCFTOOLS_HTSLIB :=
    endif
endif
endif

# Option 2: Use explicitly specified static htslib
ifndef HTSLIB_CONFIGURED
ifndef RBCFTOOLS_HTSLIB
ifdef HTSLIB_STATIC
    CFLAGS += -I$(dir $(HTSLIB_STATIC))../include
    LDFLAGS := $(HTSLIB_STATIC) -lz -lbz2 -llzma -lcurl -lpthread
    ifdef USE_DEFLATE
        LDFLAGS += -ldeflate
    endif
    HTSLIB_CONFIGURED := 1
endif
endif
endif

# Option 3: Use pkg-config (system htslib)
ifndef HTSLIB_CONFIGURED
ifndef RBCFTOOLS_HTSLIB
ifndef HTSLIB_STATIC
    HTSLIB_CFLAGS := $(shell pkg-config --cflags htslib 2>/dev/null)
    HTSLIB_LIBS := $(shell pkg-config --libs htslib 2>/dev/null)
    
    ifneq ($(HTSLIB_LIBS),)
        CFLAGS += $(HTSLIB_CFLAGS)
        LDFLAGS := $(HTSLIB_LIBS)
    else
        # Option 4: System defaults (fallback)
        $(warning Using system defaults for htslib)
        CFLAGS += -I/usr/include
        LDFLAGS := -lhts -lz -lbz2 -llzma -lcurl -lpthread
    endif
endif
endif
endif

# ============================================================================
# Build rules
# ============================================================================

# Build directories
BUILD_DIR := build
SRC_FILES := bcf_reader.c
OBJ_FILES := $(BUILD_DIR)/bcf_reader.o

# Output files
SHARED_LIB := $(BUILD_DIR)/lib$(EXTENSION_NAME)$(SHARED_EXT)
EXTENSION_FILE := $(BUILD_DIR)/$(EXTENSION_NAME).duckdb_extension

# Default target
all: $(EXTENSION_FILE)

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compile source files - depends on vcf_types.h now
$(BUILD_DIR)/%.o: %.c duckdb_extension.h vcf_types.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# Link shared library
$(SHARED_LIB): $(OBJ_FILES)
	$(CC) $(SHARED_FLAGS) -o $@ $^ $(LDFLAGS)

# Append DuckDB extension metadata
$(EXTENSION_FILE): $(SHARED_LIB)
	@echo "Creating DuckDB extension with metadata..."
	@chmod +x append_metadata.sh
	@./append_metadata.sh $(SHARED_LIB) $(EXTENSION_FILE) "$(PLATFORM)" "$(DUCKDB_VERSION)" "$(EXTENSION_VERSION)"

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

# ============================================================================
# Test targets
# ============================================================================

# Test the extension
test: $(EXTENSION_FILE)
	@echo "Testing extension with DuckDB..."
	@duckdb -unsigned -c "\
		LOAD './$(EXTENSION_FILE)'; \
		SELECT 'Extension loaded!' as status; \
		SELECT COUNT(*) as total FROM bcf_read('../extdata/test_deep_variant.vcf.gz'); \
	" || (echo 'FAILED: Extension or test query failed' && exit 1)
	@echo "DuckDB extension test passed!"

# Test: display schema with proper types
test_schema: $(EXTENSION_FILE)
	@echo "Testing extension: displaying schema..."
	@duckdb -unsigned -c "\
		LOAD './$(EXTENSION_FILE)'; \
		DESCRIBE SELECT * FROM bcf_read('../extdata/test_deep_variant.vcf.gz'); \
	"

# Test: display first 10 rows
test_head: $(EXTENSION_FILE)
	@echo "Testing extension: displaying first row where FORMAT_AD_test_deep_variant is not NULL or empty..."
	@duckdb -unsigned -c "\
		LOAD './$(EXTENSION_FILE)'; \
		SELECT * FROM bcf_read('../extdata/test_deep_variant.vcf.gz') \
		WHERE FORMAT_AD_test_deep_variant IS NOT NULL AND FORMAT_AD_test_deep_variant != '' \
		LIMIT 1; \
	" || (echo 'FAILED: Extension or test_head query failed' && exit 1)
	@echo "DuckDB extension test_head passed!"

# Test: count per chromosome
test_count: $(EXTENSION_FILE)
	@echo "Testing extension: count per chromosome..."
	@duckdb -unsigned -c "\
		LOAD './$(EXTENSION_FILE)'; \
		SELECT CHROM, COUNT(*) as n \
		FROM bcf_read('../extdata/test_deep_variant.vcf.gz') \
		GROUP BY CHROM; \
	"

# ============================================================================
# Install targets
# ============================================================================

# Install to user's DuckDB extensions directory
install: $(EXTENSION_FILE)
	@mkdir -p ~/.duckdb/extensions/$(DUCKDB_VERSION)/$(PLATFORM)
	cp $(EXTENSION_FILE) ~/.duckdb/extensions/$(DUCKDB_VERSION)/$(PLATFORM)/
	@echo "Installed to ~/.duckdb/extensions/$(DUCKDB_VERSION)/$(PLATFORM)/$(EXTENSION_NAME).duckdb_extension"

# ============================================================================
# Info targets
# ============================================================================

# Show configuration
info:
	@echo "Extension: $(EXTENSION_NAME)"
	@echo "Platform: $(PLATFORM)"
	@echo "DuckDB Version: $(DUCKDB_VERSION)"
	@echo "Compiler: $(CC)"
	@echo "CFLAGS: $(CFLAGS)"
	@echo "LDFLAGS: $(LDFLAGS)"
ifdef RBCFTOOLS_HTSLIB
	@echo "htslib: RBCFTools package ($(HTSLIB_DIR))"
else ifdef HTSLIB_STATIC
	@echo "htslib: Static ($(HTSLIB_STATIC))"
else
	@echo "htslib: System (pkg-config or defaults)"
endif

.PHONY: all clean test test_schema test_head test_count install info
