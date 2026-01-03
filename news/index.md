# Changelog

## RBCFTools 1.23-0.0.0.9000 (development version)

- Vendor and provide minimal CLI wrappers of bcftools/htslib
- VCF to Arrow stream implementation with FORMAT field extraction:
  - Proper GT field decoding (genotype integers to strings like “0\|0”,
    “0/1”)
  - List-type FORMAT fields (AD, GL, PL) now correctly extracted
  - Header sanity checking based on VCF spec (matching htslib’s
    `bcf_hdr_check_sanity()`)
  - R warnings emitted when correcting non-conformant headers (Number,
    Type)
