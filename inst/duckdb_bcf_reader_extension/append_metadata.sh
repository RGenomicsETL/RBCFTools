#!/bin/bash
# append_metadata.sh - Append DuckDB extension metadata to a shared library
#
# Usage: ./append_metadata.sh <input.so> <output.duckdb_extension> <platform> <duckdb_version> <extension_version>

set -e

INPUT="$1"
OUTPUT="$2"
PLATFORM="$3"
DUCKDB_VERSION="$4"
EXTENSION_VERSION="$5"

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ] || [ -z "$PLATFORM" ] || [ -z "$DUCKDB_VERSION" ] || [ -z "$EXTENSION_VERSION" ]; then
    echo "Usage: $0 <input.so> <output.duckdb_extension> <platform> <duckdb_version> <extension_version>"
    exit 1
fi

# Copy input to output
cp "$INPUT" "$OUTPUT"

# Create a temporary file for the metadata
METADATA_FILE=$(mktemp)

# Function to write a 32-byte padded string (null-padded)
write_padded_string() {
    local str="$1"
    local len=${#str}
    printf "%s" "$str" >> "$METADATA_FILE"
    # Pad with nulls to 32 bytes
    for ((i=len; i<32; i++)); do
        printf '\x00' >> "$METADATA_FILE"
    done
}

# Start signature (WebAssembly compatible):
# 0x00 - custom section marker
# 0x93 0x04 - LEB128 encoded payload length (531 = 1 + 16 + 2 + 256 + 256)
# 0x10 - name length (16)
# "duckdb_signature" - section name
# 0x80 0x04 - LEB128 encoded data length (512)
printf '\x00\x93\x04\x10duckdb_signature\x80\x04' >> "$METADATA_FILE"

# 8 fields, each 32 bytes (256 bytes total):
# FIELD8 (unused) - empty
write_padded_string ""
# FIELD7 (unused) - empty
write_padded_string ""
# FIELD6 (unused) - empty
write_padded_string ""
# FIELD5 (abi_type)
write_padded_string "C_STRUCT"
# FIELD4 (extension_version)
write_padded_string "$EXTENSION_VERSION"
# FIELD3 (duckdb_version)
write_padded_string "$DUCKDB_VERSION"
# FIELD2 (platform)
write_padded_string "$PLATFORM"
# FIELD1 (magic number "4")
write_padded_string "4"

# Empty signature space (256 bytes of nulls)
dd if=/dev/zero bs=256 count=1 2>/dev/null >> "$METADATA_FILE"

# Append metadata to output file
cat "$METADATA_FILE" >> "$OUTPUT"

# Cleanup
rm -f "$METADATA_FILE"

echo "Created: $OUTPUT"
echo "  Platform: $PLATFORM"
echo "  DuckDB Version: $DUCKDB_VERSION"
echo "  Extension Version: $EXTENSION_VERSION"
