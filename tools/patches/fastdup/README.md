# RBCFTools FastDup overlay

These patches are applied in lexical order to FastDup 1.0.0 commit
`7b3f62587283a257fd38c5c20ceeda0364c285ef`. The unmodified upstream archive
and SHA-256 are declared in `tools/fastdup-upstream.dcf`.

1. `0001-use-external-htslib.patch` lowers the unnecessarily new CMake floor to
   3.16 and adds `FASTDUP_HTSLIB_ROOT`. RBCFTools points it at its canonical
   HTSlib 1.24 source/build tree; FastDup's HTSlib copy is not vendored.
2. `0002-wide-optical-coordinates.patch` uses 32-bit tile/x/y fields. Upstream
   intentionally retained Picard's signed-16-bit optical-coordinate overflow.
3. `0003-separate-libraries.patch` includes the SAM read group's `LB` library in
   pair assembly and duplicate keys. Reads from different libraries cannot
   mark one another as duplicates.
4. `0004-honor-tagging-policy.patch` writes `DT` only when requested by
   `--tagging-policy`, with Picard's `DontTag`, `OpticalOnly`, and `All`
   semantics.

Run `tools/vendor-fastdup.R` to reacquire, verify, prune, patch, and replace the
vendored source. Run `tools/apply-fastdup-patches.sh --check SOURCE_DIR` to
check that the overlay applies cleanly to a fresh upstream tree.
