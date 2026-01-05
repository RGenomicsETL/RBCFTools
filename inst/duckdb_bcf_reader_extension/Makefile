# DuckDB BCF/VCF Reader Extension - Makefile
# Self-contained build without CMake
#
# Usage:
#   make          - Build the extension
#   make clean    - Clean build artifacts
#   make test     - Run basic tests
#   make install  - Install to ~/.duckdb/extensions
#
# Requirements:
#   - GCC or Clang
#   - htslib (pkg-config)
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
CFLAGS := -O2 -Wall -fPIC
INCLUDES := -I.

# htslib via pkg-config
HTSLIB_CFLAGS ?= $(shell pkg-config --cflags htslib 2>/dev/null)
HTSLIB_LIBS ?= $(shell pkg-config --libs htslib 2>/dev/null)

# If HTSLIB_STATIC is set, use it for linking
ifeq ($(HTSLIB_STATIC),)
	ifeq ($(HTSLIB_LIBS),)
		HTSLIB_CFLAGS := -I/usr/include/htslib
		HTSLIB_LIBS := -lhts -lz -lbz2 -llzma -lcurl -lpthread
	endif
	CFLAGS += $(HTSLIB_CFLAGS)
	LDFLAGS ?= $(HTSLIB_LIBS)
else
	CFLAGS += -I$(dir $(HTSLIB_STATIC))
	LDFLAGS ?= $(HTSLIB_STATIC) -lz -lbz2 -llzma -lcurl -ldeflate
endif

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

# Compile source files
$(BUILD_DIR)/%.o: %.c duckdb_extension.h | $(BUILD_DIR)
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

# Test the extension
test: $(EXTENSION_FILE)
	@echo "Testing extension with DuckDB..."
	@duckdb -unsigned -c "\
		LOAD './$(EXTENSION_FILE)'; \
		SELECT 'Extension loaded!' as status; \
		SELECT COUNT(*) as total FROM bcf_read('../extdata/test_deep_variant.vcf.gz'); \
	" || (echo 'FAILED: Extension or test query failed' && exit 1)
	@echo "DuckDB extension test passed!"

# Install to user's DuckDB extensions directory
install: $(EXTENSION_FILE)
	@mkdir -p ~/.duckdb/extensions/$(DUCKDB_VERSION)/$(PLATFORM)
	cp $(EXTENSION_FILE) ~/.duckdb/extensions/$(DUCKDB_VERSION)/$(PLATFORM)/
	@echo "Installed to ~/.duckdb/extensions/$(DUCKDB_VERSION)/$(PLATFORM)/$(EXTENSION_NAME).duckdb_extension"

# Show configuration
info:
	@echo "Extension: $(EXTENSION_NAME)"
	@echo "Platform: $(PLATFORM)"
	@echo "DuckDB Version: $(DUCKDB_VERSION)"
	@echo "Compiler: $(CC)"
	@echo "CFLAGS: $(CFLAGS)"
	@echo "LDFLAGS: $(LDFLAGS)"

.PHONY: all clean test install info
