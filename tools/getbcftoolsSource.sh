#!/usr/bin/env bash
set -euo pipefail

# Recreate the bundled source tree from exact upstream release archives.
BCFTOOLS_VERSION=1.24
BCFTOOLS_SHA256=8caddc22610ee2851666047c859bb91da0c1e32d0c2ec553db6f153ad130e46f
HTSLIB_VERSION=1.24
HTSLIB_SHA256=28a8de191381c7a97a35675ceac76fa1ea95e7b678d6a2e9d600a7874e4077de

THIS_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="${THIS_DIR}/../src"
BCFTOOLS_DIR="${SRC_DIR}/bcftools-${BCFTOOLS_VERSION}"

cd "${SRC_DIR}"
rm -rf "${BCFTOOLS_DIR}"

echo "Downloading bcftools ${BCFTOOLS_VERSION}"
curl --fail --location --retry 3 \
  --output "bcftools-${BCFTOOLS_VERSION}.tar.bz2" \
  "https://github.com/samtools/bcftools/releases/download/${BCFTOOLS_VERSION}/bcftools-${BCFTOOLS_VERSION}.tar.bz2"
printf '%s  %s\n' "${BCFTOOLS_SHA256}" "bcftools-${BCFTOOLS_VERSION}.tar.bz2" | sha256sum -c -
tar -xjf "bcftools-${BCFTOOLS_VERSION}.tar.bz2"
rm -f "bcftools-${BCFTOOLS_VERSION}.tar.bz2"

patch -d "${BCFTOOLS_DIR}" -p1 < "${THIS_DIR}/patches/bcftools-${BCFTOOLS_VERSION}/libbcftools-shared.patch"

rm -rf "${BCFTOOLS_DIR}"/htslib-*
echo "Downloading htslib ${HTSLIB_VERSION}"
curl --fail --location --retry 3 \
  --output "htslib-${HTSLIB_VERSION}.tar.bz2" \
  "https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2"
printf '%s  %s\n' "${HTSLIB_SHA256}" "htslib-${HTSLIB_VERSION}.tar.bz2" | sha256sum -c -
mkdir -p "${BCFTOOLS_DIR}/htslib-${HTSLIB_VERSION}"
tar -xjf "htslib-${HTSLIB_VERSION}.tar.bz2" \
  --strip-components=1 \
  -C "${BCFTOOLS_DIR}/htslib-${HTSLIB_VERSION}"
rm -f "htslib-${HTSLIB_VERSION}.tar.bz2"
