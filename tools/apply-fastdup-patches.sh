#!/bin/sh
set -eu

usage() {
    echo "Usage: $0 [--check] SOURCE_DIR" >&2
    exit 2
}

MODE=apply
if [ "${1:-}" = "--check" ]; then
    MODE=check
    shift
fi
[ "$#" -eq 1 ] || usage

SOURCE_DIR=$(realpath "$1")
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PATCH_DIR="${ROOT_DIR}/tools/patches/fastdup"
EXPECTED_PATCHES='0001-use-external-htslib.patch
0002-wide-optical-coordinates.patch
0003-separate-libraries.patch
0004-honor-tagging-policy.patch'
ACTUAL_PATCHES=$(find "${PATCH_DIR}" -type f -name '*.patch' -exec basename {} \; | LC_ALL=C sort)

if [ "${ACTUAL_PATCHES}" != "${EXPECTED_PATCHES}" ]; then
    echo "FastDup patch set does not match the declared overlay" >&2
    exit 1
fi

if [ "${MODE}" = check ]; then
    CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fastdup-patches.XXXXXX")
    trap 'rm -rf "${CHECK_DIR}"' EXIT HUP INT TERM
    cp -R "${SOURCE_DIR}/." "${CHECK_DIR}/"
    SOURCE_DIR=${CHECK_DIR}
fi

for patch_name in ${EXPECTED_PATCHES}; do
    patch_file="${PATCH_DIR}/${patch_name}"
    patch -d "${SOURCE_DIR}" -p1 --forward < "${patch_file}"
done
