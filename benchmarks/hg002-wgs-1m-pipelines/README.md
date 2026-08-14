
<!-- Generated as README.md from README.Rmd. Edit README.Rmd or ../run-short-read-pipelines.R, then rerun the benchmark. -->

# HG002 WGS one-million-pair executable-pipeline benchmark

This is an executed real-human-data benchmark of the generic RBCFTools
process pipeline, not a synthetic package fixture. It maps all one
million NovaSeq WGS read pairs in the pinned Zenodo HG002 artifact with
BWA and Rminibwa, prepares one valid
name-sort/`fixmate -m`/coordinate-sort BAM per mapper, and runs both
Samtools `markdup` and the RBCFTools-patched FastDup against each
prepared BAM.

Large references, FASTQs, indexes, and BAMs remain outside Git.
[`../run-short-read-pipelines.R`](../run-short-read-pipelines.R) records
results incrementally, validates every BAM and index, records
duplicate-QNAME digests, retains text logs/metrics, and removes bulk
outputs after successful validation.

## Inputs and executable authorities

The full human reference is the Ensembl release 116 GRCh38 primary
assembly:

- <https://ftp.ensembl.org/pub/release-116/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz>
- 194 sequences and 3,099,750,718 unpadded bases.

The reads are the complete paired WGS subset published by Heng Li as
**Small short- and long-read datasets**, DOI
[10.5281/zenodo.19703025](https://doi.org/10.5281/zenodo.19703025),
under CC BY 4.0:

- mate 1: `HG002.WGS-1M_1.fq.gz`, 70,196,167 bytes;
- mate 2: `HG002.WGS-1M_2.fq.gz`, 72,385,151 bytes;
- workload: 1,000,000 records in each mate (2,000,000 input reads).

The record’s `map.mak` targets a local `hs38.fa`. This benchmark
declares the exact full GRCh38 reference above rather than silently
assuming that local filename’s sequence content. Stable input locators,
checksums, and workload roles are also recorded in
[`input-manifest.csv`](input-manifest.csv).

| Field                            |                                           Value |
|:---------------------------------|------------------------------------------------:|
| Run UTC                          |                         2026-08-14 13:28:23 UTC |
| Host                             |                    Ubuntu-2404-noble-amd64-base |
| Platform                         |                             x86_64-pc-linux-gnu |
| CPU                              |             13th Gen Intel(R) Core(TM) i5-13500 |
| Logical CPUs                     |                                              20 |
| Memory bytes                     |                                  67,194,490,880 |
| Kernel                           |                   Linux 6.8.0-78-generic x86_64 |
| RBCFTools                        |                                 1.24.1.0.0.9000 |
| RBCFTools commit                 |        8f8a534191d5b9dd84e2ee62cc7e4e48efba879d |
| Source tree state                |                                        modified |
| FastDup                          |                                           1.0.0 |
| Samtools                         |                                            1.24 |
| Rminibwa                         |                                        0.7-r421 |
| Pinned logical CPUs              |                                    0,2,4,6,8,10 |
| Physical-core sibling sets       |                       0-1;2-3;4-5;6-7;8-9;10-11 |
| Pinned CPU max frequencies (kHz) | 4800000,4800000,4800000,4800000,4800000,4800000 |
| Mapper/marker threads            |                                               6 |
| Sort threads per sort            |                                               2 |
| Fixmate threads                  |                                               1 |
| Marker repetitions               |                                               3 |
| Cache policy                     |   cold: sync + drop_caches=3 before timed phase |
| Reference bytes                  |                                   3,151,425,851 |
| Mate 1 bytes                     |                                      70,196,167 |
| Mate 2 bytes                     |                                      72,385,151 |

## Executed method

For each mapper, the benchmark builds a full GRCh38 index or explicitly
records reuse of a prebuilt index, then executes:

``` text
BWA mem or minibwa map
  | samtools sort -n
  | samtools fixmate -m
  | samtools sort (coordinate)
  > prepared.bam
```

That one prepared BAM is then consumed independently by:

``` text
samtools markdup prepared.bam samtools.bam
samtools index samtools.bam

fastdup --input prepared.bam --output fastdup.bam ...
samtools index fastdup.bam
```

This isolates duplicate-marker time from mapping and sort time while
also exercising the complete executable pipeline. FastDup receives a
seekable file because its algorithm rereads coordinate-sorted input; it
is not represented as a streaming stage.

Every timed process is confined to the same explicit logical-CPU set
with `run_pipeline(cpu_affinity = ...)`. The selected IDs contain one
SMT sibling from each physical core; the runner rejects duplicate
`thread_siblings_list` values. All concurrently active stages share that
one CPU set, so pipeline stages cannot silently multiply the benchmark’s
physical-core budget. Internal thread flags are still recorded because
they describe scheduling demand, not additional entitled cores.

RBCFTools samples each live stage’s Linux `/proc/<pid>/status` every 10
ms. `pipeline_peak_rss_kib` is the largest simultaneous sum of stage RSS
values; it is aggregate RSS and may double-count shared pages, rather
than unique PSS. `pipeline_peak_threads` is the largest simultaneous sum
of live stage thread counts. These are pipeline-level high-water marks;
GNU `time -v` around only one sibling process would not measure them.

## Measured wall time

| Mapper   | Phase             | Tool              | Repetition | Cache | Wall seconds | Peak aggregate RSS (GiB) | Peak simultaneous threads | Pinned CPUs  | Internal thread configuration                    | Stage statuses                                        | Output bytes |
|:---------|:------------------|:------------------|-----------:|:------|-------------:|-------------------------:|--------------------------:|:-------------|:-------------------------------------------------|:------------------------------------------------------|-------------:|
| rminibwa | reference index   | minibwa index     |          1 | cold  |      382.268 |                   55.757 |                         1 | 0,2,4,6,8,10 | minibwa_index=6                                  | minibwa index=0                                       |              |
| rminibwa | map and prepare   | mapper + samtools |          1 | cold  |       68.847 |                    8.910 |                        16 | 0,2,4,6,8,10 | mapper=6;name_sort=2;fixmate=1;coordinate_sort=2 | minibwa map=0;name sort=0;fixmate=0;coordinate sort=0 |  177,654,881 |
| rminibwa | duplicate marking | samtools markdup  |          1 | cold  |        2.164 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    |  178,179,877 |
| rminibwa | index             | samtools index    |          1 | cold  |        0.244 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,086,112 |
| rminibwa | duplicate marking | FastDup           |          1 | cold  |        2.754 |                    1.379 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             |  179,049,910 |
| rminibwa | index             | samtools index    |          1 | cold  |        0.222 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,086,224 |
| rminibwa | duplicate marking | FastDup           |          2 | cold  |        3.099 |                    1.394 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             |  179,049,910 |
| rminibwa | index             | samtools index    |          2 | cold  |        0.254 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,086,224 |
| rminibwa | duplicate marking | samtools markdup  |          2 | cold  |        2.206 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    |  178,179,877 |
| rminibwa | index             | samtools index    |          2 | cold  |        0.234 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,086,112 |
| rminibwa | duplicate marking | samtools markdup  |          3 | cold  |        2.368 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    |  178,179,877 |
| rminibwa | index             | samtools index    |          3 | cold  |        0.224 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,086,112 |
| rminibwa | duplicate marking | FastDup           |          3 | cold  |        2.623 |                    1.390 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             |  179,049,910 |
| rminibwa | index             | samtools index    |          3 | cold  |        0.255 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,086,224 |
| bwa      | reference index   | bwa index         |          1 | cold  |     2166.491 |                    4.334 |                         1 | 0,2,4,6,8,10 | bwa_index=1                                      | bwa index=0                                           |              |
| bwa      | map and prepare   | mapper + samtools |          1 | cold  |      127.751 |                    6.734 |                        15 | 0,2,4,6,8,10 | mapper=6;name_sort=2;fixmate=1;coordinate_sort=2 | bwa mem=0;name sort=0;fixmate=0;coordinate sort=0     |  185,649,200 |
| bwa      | duplicate marking | samtools markdup  |          1 | cold  |        2.039 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    |  186,201,911 |
| bwa      | index             | samtools index    |          1 | cold  |        0.284 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,092,544 |
| bwa      | duplicate marking | FastDup           |          1 | cold  |        2.571 |                    1.347 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             |  187,191,318 |
| bwa      | index             | samtools index    |          1 | cold  |        0.202 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,093,064 |
| bwa      | duplicate marking | FastDup           |          2 | cold  |        2.978 |                    1.398 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             |  187,191,318 |
| bwa      | index             | samtools index    |          2 | cold  |        0.305 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,093,064 |
| bwa      | duplicate marking | samtools markdup  |          2 | cold  |        1.778 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    |  186,201,911 |
| bwa      | index             | samtools index    |          2 | cold  |        0.192 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,092,544 |
| bwa      | duplicate marking | samtools markdup  |          3 | cold  |        2.388 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    |  186,201,911 |
| bwa      | index             | samtools index    |          3 | cold  |        0.233 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,092,544 |
| bwa      | duplicate marking | FastDup           |          3 | cold  |        2.532 |                    1.405 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             |  187,191,318 |
| bwa      | index             | samtools index    |          3 | cold  |        0.202 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |    4,093,064 |

| Mapper   | Tool             | Minimum wall (s) | Median wall (s) | Maximum wall (s) | Median peak RSS (GiB) | Median peak threads |
|:---------|:-----------------|-----------------:|----------------:|-----------------:|----------------------:|--------------------:|
| bwa      | FastDup          |            2.532 |           2.571 |            2.978 |                 1.398 |              26.000 |
| rminibwa | FastDup          |            2.623 |           2.754 |            3.099 |                 1.390 |              26.000 |
| bwa      | samtools markdup |            1.778 |           2.039 |            2.388 |                 0.012 |               9.000 |
| rminibwa | samtools markdup |            2.164 |           2.206 |            2.368 |                 0.012 |               9.000 |

Duplicate-marker runs use three repetitions with alternating tool order
and a cold page cache before each timed phase. The table establishes
what was observed for this real HG002 WGS subset on one pinned host; it
does not claim a general speedup outside the declared workload and
resource contract.

## Output validation

Every output passed `samtools quickcheck`, was indexed by the bundled
Samtools, and was scanned to count all records and duplicate-flagged
records. Duplicate QNAMEs were deduplicated, sorted, and hashed so
marker agreement is auditable without retaining multi-gigabyte BAMs.

| Mapper   | Marker   | Repetition | Records | Duplicate records | Duplicate QNAMEs | Duplicate-QNAME SHA-256                                          |   BAM bytes | BAI bytes | Quickcheck |
|:---------|:---------|-----------:|--------:|------------------:|-----------------:|:-----------------------------------------------------------------|------------:|----------:|:-----------|
| rminibwa | samtools |          1 | 2011403 |            131616 |            66196 | 46a15ffcc0c686f4b2a2f7bde6c0d7fb98b0f0b2ac0d52cf8da08098422a6752 | 178,179,877 | 4,086,112 | TRUE       |
| rminibwa | fastdup  |          1 | 2011403 |            131622 |            66199 | 1f3961beac17777fe0a70106ebaf475e91803fb1d949f5cd889b04ea0678c339 | 179,049,910 | 4,086,224 | TRUE       |
| rminibwa | fastdup  |          2 | 2011403 |            131622 |            66199 | 1f3961beac17777fe0a70106ebaf475e91803fb1d949f5cd889b04ea0678c339 | 179,049,910 | 4,086,224 | TRUE       |
| rminibwa | samtools |          2 | 2011403 |            131616 |            66196 | 46a15ffcc0c686f4b2a2f7bde6c0d7fb98b0f0b2ac0d52cf8da08098422a6752 | 178,179,877 | 4,086,112 | TRUE       |
| rminibwa | samtools |          3 | 2011403 |            131616 |            66196 | 46a15ffcc0c686f4b2a2f7bde6c0d7fb98b0f0b2ac0d52cf8da08098422a6752 | 178,179,877 | 4,086,112 | TRUE       |
| rminibwa | fastdup  |          3 | 2011403 |            131622 |            66199 | 1f3961beac17777fe0a70106ebaf475e91803fb1d949f5cd889b04ea0678c339 | 179,049,910 | 4,086,224 | TRUE       |
| bwa      | samtools |          1 | 2012384 |            132028 |            66190 | 72e1fb13985f59c5f907ce0ea94cef8c00e1d0391d18174a8b42827bd15add5f | 186,201,911 | 4,092,544 | TRUE       |
| bwa      | fastdup  |          1 | 2012384 |            132044 |            66198 | 604fe7883f6e19333c59c38779536b5d26039677496c25484d558ea1e49fc4c3 | 187,191,318 | 4,093,064 | TRUE       |
| bwa      | fastdup  |          2 | 2012384 |            132044 |            66198 | 604fe7883f6e19333c59c38779536b5d26039677496c25484d558ea1e49fc4c3 | 187,191,318 | 4,093,064 | TRUE       |
| bwa      | samtools |          2 | 2012384 |            132028 |            66190 | 72e1fb13985f59c5f907ce0ea94cef8c00e1d0391d18174a8b42827bd15add5f | 186,201,911 | 4,092,544 | TRUE       |
| bwa      | samtools |          3 | 2012384 |            132028 |            66190 | 72e1fb13985f59c5f907ce0ea94cef8c00e1d0391d18174a8b42827bd15add5f | 186,201,911 | 4,092,544 | TRUE       |
| bwa      | fastdup  |          3 | 2012384 |            132044 |            66198 | 604fe7883f6e19333c59c38779536b5d26039677496c25484d558ea1e49fc4c3 | 187,191,318 | 4,093,064 | TRUE       |

| Mapper   | Repetition | Same duplicate-record count | Same duplicate-QNAME count | Same duplicate-QNAME digest |
|:---------|-----------:|:----------------------------|:---------------------------|:----------------------------|
| bwa      |          1 | FALSE                       | FALSE                      | FALSE                       |
| bwa      |          2 | FALSE                       | FALSE                      | FALSE                       |
| bwa      |          3 | FALSE                       | FALSE                      | FALSE                       |
| rminibwa |          1 | FALSE                       | FALSE                      | FALSE                       |
| rminibwa |          2 | FALSE                       | FALSE                      | FALSE                       |
| rminibwa |          3 | FALSE                       | FALSE                      | FALSE                       |

Matching duplicate counts alone do not prove identical decisions;
matching the sorted unique-QNAME digest provides a stronger marker-level
comparison. Any intentional differences caused by the RBCFTools FastDup
corrections remain governed by the package root `ERRATA.md`.
