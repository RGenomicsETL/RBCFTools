# RBCFTools FastDup errata and overlay policy

RBCFTools bundles FastDup 1.0.0 at commit
`7b3f62587283a257fd38c5c20ceeda0364c285ef`, but does not treat upstream's
"identical results" claim as a compatibility contract. The exact source
archive is locked in `tools/fastdup-upstream.dcf`; ordered overlay patches live
in `tools/patches/fastdup/`.

## Fixed by the RBCFTools overlay

### FD-001 — signed-16-bit optical coordinates

**Upstream behavior:** `PhysicalLocation::x` and `y` are signed 16-bit values.
The upstream source explicitly identifies this as a Picard bug and retains it.
Coordinates around the 32,767/32,768 transition wrap, so physically adjacent
clusters can be classified as distant and optical duplicate counts become
wrong.

**RBCFTools correction:** `0002-wide-optical-coordinates.patch` stores tile,
x, and y as signed 32-bit values and removes the narrowing cast in the read-name
parser.

**Contract:** optical distance is computed from the parsed non-overflowed
coordinates. RBCFTools intentionally differs from overflow-compatible Picard
and unpatched FastDup output.

### FD-002 — duplicate sets crossed SAM libraries

**Upstream behavior:** the duplicate key omits the library (`LB`) associated
with each record's read group (`RG`). Templates from different libraries can
therefore mark one another as duplicates when their mapped geometry matches.

**RBCFTools correction:** `0003-separate-libraries.patch` builds a deterministic
RG-to-LB map from the SAM header, carries a library identifier in `ReadEnds`,
uses it in pair assembly, ordering, and duplicate comparisons, and groups
missing/unknown libraries under one explicit default identifier.

**Contract:** records from distinct `LB` values cannot be members of the same
duplicate set. FastDup's metrics file remains aggregate; this patch does not
invent per-library metric rows.

### FD-003 — `DT` was written under `DontTag`

**Upstream behavior:** duplicate records receive `DT:Z:LB` or `DT:Z:SQ`
regardless of `--tagging-policy`, including the default `DontTag` mode.

**RBCFTools correction:** `0004-honor-tagging-policy.patch` implements the
advertised policies:

- `DontTag`: no new `DT` tag;
- `OpticalOnly`: only optical duplicates receive `DT:Z:SQ`;
- `All`: optical duplicates receive `DT:Z:SQ`, other duplicates receive
  `DT:Z:LB`.

## Packaging correction

### FD-004 — duplicate HTSlib ownership

**Upstream behavior:** FastDup vendors and links its own HTSlib tree.

**RBCFTools correction:** the upstream HTSlib directory is excluded.
`0001-use-external-htslib.patch` adds `FASTDUP_HTSLIB_ROOT`, and package
configuration points it to `src/bcftools-1.24/htslib-1.24`. FastDup, Samtools,
BCFtools, and the R native library are therefore compiled from the package's
one canonical HTSlib source/configuration.

## Deliberate limitations

- FastDup requires a seekable coordinate-sorted SAM/BAM input and rereads it;
  it is a file-dependent step, not a streaming pipe stage.
- Barcode/UMI-aware duplicate keys are not implemented by this overlay.
- The overlay does not claim byte-for-byte Picard output. Duplicate flags,
  optical classification, requested `DT` policy, and library isolation are the
  tested contracts.
- Upstream changes are never copied over the vendored tree manually. Update
  the lock, refresh the ordered patches, run `tools/vendor-fastdup.R`, and
  rerun the fixture and package checks.
