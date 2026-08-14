
<!-- Generated as README.md from README.Rmd. Edit README.Rmd or ../run-short-read-pipelines.R, then rerun the benchmark. -->

# Complete HG02088 exome executable-pipeline benchmark

This is an executed full-input benchmark of the generic RBCFTools
process pipeline, not a synthetic package fixture. It maps all
10,110,535 read pairs from the HG02088 exome run with BWA and Rminibwa,
prepares one valid name-sort/`fixmate -m`/coordinate-sort BAM per
mapper, and runs both Samtools `markdup` and the RBCFTools-patched
FastDup against each prepared BAM.

Large references, FASTQs, indexes, and BAMs remain outside Git.
[`../run-short-read-pipelines.R`](../run-short-read-pipelines.R) records
results incrementally, validates every BAM and index, records
duplicate-QNAME digests, retains text logs/metrics, and removes bulk
outputs after successful validation.

## Inputs and executable authorities

The human reference is the 1000 Genomes hs37d5 FASTA:

- <https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/phase2_reference_assembly_sequence/hs37d5.fa.gz>
- 86 sequences and 3,137,454,505 unpadded bases.

The reads are the complete real 1000 Genomes phase 3 HG02088 exome run
SRR716421, classified as exome by the project sequence index:

- mate 1:
  <https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/HG02088/sequence_read/SRR716421_1.filt.fastq.gz>
- mate 2:
  <https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/HG02088/sequence_read/SRR716421_2.filt.fastq.gz>
- workload: 10,110,535 records in each mate (20,221,070 input reads).

Stable locators and workload roles are also recorded in
[`input-manifest.csv`](input-manifest.csv).

| Field                            |                                           Value |
|:---------------------------------|------------------------------------------------:|
| Run UTC                          |                         2026-08-14 13:00:22 UTC |
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
| Reference bytes                  |                                   3,189,750,467 |
| Mate 1 bytes                     |                                     852,214,060 |
| Mate 2 bytes                     |                                     864,944,265 |

## Executed method

For each mapper, the benchmark builds a full hs37d5 index or explicitly
records reuse of a prebuilt index. The reported BWA index was previously
produced once with `bwa index -p <cache>/bwa-hs37d5 hs37d5.fa`; the
runner hard-linked its five sidecars into the run directory. Remove
`RBCFTOOLS_BENCH_BWA_INDEX_CACHE` from the command below to time a fresh
BWA index build instead.

The mapping and preparation phase then executes:

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

| Mapper   | Phase             | Tool              | Repetition | Cache          | Wall seconds | Peak aggregate RSS (GiB) | Peak simultaneous threads | Pinned CPUs  | Internal thread configuration                    | Stage statuses                                        |  Output bytes |
|:---------|:------------------|:------------------|-----------:|:---------------|-------------:|-------------------------:|--------------------------:|:-------------|:-------------------------------------------------|:------------------------------------------------------|--------------:|
| rminibwa | reference index   | minibwa index     |          1 | cold           |      387.062 |                   56.289 |                         1 | 0,2,4,6,8,10 | minibwa_index=6                                  | minibwa index=0                                       |               |
| rminibwa | map and prepare   | mapper + samtools |          1 | cold           |      257.350 |                   10.621 |                        18 | 0,2,4,6,8,10 | mapper=6;name_sort=2;fixmate=1;coordinate_sort=2 | minibwa map=0;name sort=0;fixmate=0;coordinate sort=0 | 1,501,357,699 |
| rminibwa | duplicate marking | samtools markdup  |          1 | cold           |       19.452 |                    0.011 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    | 1,502,961,417 |
| rminibwa | index             | samtools index    |          1 | cold           |        1.404 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,096,536 |
| rminibwa | duplicate marking | FastDup           |          1 | cold           |       21.125 |                    2.815 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             | 1,513,404,083 |
| rminibwa | index             | samtools index    |          1 | cold           |        1.524 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,104,912 |
| rminibwa | duplicate marking | FastDup           |          2 | cold           |       21.143 |                    2.822 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             | 1,513,404,083 |
| rminibwa | index             | samtools index    |          2 | cold           |        1.415 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,104,912 |
| rminibwa | duplicate marking | samtools markdup  |          2 | cold           |       17.796 |                    0.011 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    | 1,502,961,417 |
| rminibwa | index             | samtools index    |          2 | cold           |        1.404 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,096,536 |
| rminibwa | duplicate marking | samtools markdup  |          3 | cold           |       18.334 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    | 1,502,961,417 |
| rminibwa | index             | samtools index    |          3 | cold           |        1.413 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,096,536 |
| rminibwa | duplicate marking | FastDup           |          3 | cold           |       20.590 |                    2.823 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             | 1,513,404,083 |
| rminibwa | index             | samtools index    |          3 | cold           |        1.382 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,104,912 |
| bwa      | reference index   | bwa index         |          1 | prebuilt index |              |                          |                        NA | 0,2,4,6,8,10 | prebuilt                                         | reused=0                                              | 5,490,659,117 |
| bwa      | map and prepare   | mapper + samtools |          1 | cold           |      432.100 |                    8.228 |                        17 | 0,2,4,6,8,10 | mapper=6;name_sort=2;fixmate=1;coordinate_sort=2 | bwa mem=0;name sort=0;fixmate=0;coordinate sort=0     | 1,542,340,195 |
| bwa      | duplicate marking | samtools markdup  |          1 | cold           |       19.243 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    | 1,543,928,986 |
| bwa      | index             | samtools index    |          1 | cold           |        1.446 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,103,808 |
| bwa      | duplicate marking | FastDup           |          1 | cold           |       21.917 |                    2.771 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             | 1,557,643,402 |
| bwa      | index             | samtools index    |          1 | cold           |        1.615 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,113,776 |
| bwa      | duplicate marking | FastDup           |          2 | cold           |       21.903 |                    2.768 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             | 1,557,643,402 |
| bwa      | index             | samtools index    |          2 | cold           |        1.372 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,113,776 |
| bwa      | duplicate marking | samtools markdup  |          2 | cold           |       18.849 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    | 1,543,928,986 |
| bwa      | index             | samtools index    |          2 | cold           |        1.473 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,103,808 |
| bwa      | duplicate marking | samtools markdup  |          3 | cold           |       18.685 |                    0.012 |                         9 | 0,2,4,6,8,10 | markdup=6                                        | samtools markdup=0                                    | 1,543,928,986 |
| bwa      | index             | samtools index    |          3 | cold           |        1.402 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,103,808 |
| bwa      | duplicate marking | FastDup           |          3 | cold           |       22.284 |                    2.786 |                        26 | 0,2,4,6,8,10 | fastdup=6                                        | fastdup=0                                             | 1,557,643,402 |
| bwa      | index             | samtools index    |          3 | cold           |        1.505 |                    0.020 |                         8 | 0,2,4,6,8,10 | samtools_index=6                                 | samtools index=0                                      |     4,113,776 |

| Mapper   | Tool             | Minimum wall (s) | Median wall (s) | Maximum wall (s) | Median peak RSS (GiB) | Median peak threads |
|:---------|:-----------------|-----------------:|----------------:|-----------------:|----------------------:|--------------------:|
| bwa      | FastDup          |           21.903 |          21.917 |           22.284 |                 2.771 |              26.000 |
| rminibwa | FastDup          |           20.590 |          21.125 |           21.143 |                 2.822 |              26.000 |
| bwa      | samtools markdup |           18.685 |          18.849 |           19.243 |                 0.012 |               9.000 |
| rminibwa | samtools markdup |           17.796 |          18.334 |           19.452 |                 0.011 |               9.000 |

Duplicate-marker runs use three repetitions with alternating tool order
and a cold page cache before each timed phase. The table establishes
what was observed for this complete exome on one pinned host; it does
not claim a general speedup outside the declared workload and resource
contract.

## Output validation

Every output passed `samtools quickcheck`, was indexed by the bundled
Samtools, and was scanned to count all records and duplicate-flagged
records. Duplicate QNAMEs were deduplicated, sorted, and hashed so
marker agreement is auditable without retaining multi-gigabyte BAMs.

| Mapper   | Marker   | Repetition |  Records | Duplicate records | Duplicate QNAMEs | Duplicate-QNAME SHA-256                                          |     BAM bytes | BAI bytes | Quickcheck |
|:---------|:---------|-----------:|---------:|------------------:|-----------------:|:-----------------------------------------------------------------|--------------:|----------:|:-----------|
| rminibwa | samtools |          1 | 20225776 |            467238 |           236489 | ce3cc8ccd0fa1dc3d46a8980b1bb0d616e023fae1140a241b83b3e2bdbd915cd | 1,502,961,417 | 4,096,536 | TRUE       |
| rminibwa | fastdup  |          1 | 20225776 |            467238 |           236489 | 3f1654b7e06f79fc4432a702b4d7728b93605be9b944c9f86b3d72ba76f465ee | 1,513,404,083 | 4,104,912 | TRUE       |
| rminibwa | fastdup  |          2 | 20225776 |            467238 |           236489 | 3f1654b7e06f79fc4432a702b4d7728b93605be9b944c9f86b3d72ba76f465ee | 1,513,404,083 | 4,104,912 | TRUE       |
| rminibwa | samtools |          2 | 20225776 |            467238 |           236489 | ce3cc8ccd0fa1dc3d46a8980b1bb0d616e023fae1140a241b83b3e2bdbd915cd | 1,502,961,417 | 4,096,536 | TRUE       |
| rminibwa | samtools |          3 | 20225776 |            467238 |           236489 | ce3cc8ccd0fa1dc3d46a8980b1bb0d616e023fae1140a241b83b3e2bdbd915cd | 1,502,961,417 | 4,096,536 | TRUE       |
| rminibwa | fastdup  |          3 | 20225776 |            467238 |           236489 | 3f1654b7e06f79fc4432a702b4d7728b93605be9b944c9f86b3d72ba76f465ee | 1,513,404,083 | 4,104,912 | TRUE       |
| bwa      | samtools |          1 | 20225961 |            466183 |           235164 | b7e4d17985f344365657f82993a0e29a66d2b3e0aa26dafc8f9375e8a6781b7f | 1,543,928,986 | 4,103,808 | TRUE       |
| bwa      | fastdup  |          1 | 20225961 |            466181 |           235163 | 8ca85cbb809779fcabc3d16c35a6d66565d37825791f2afe2707b284cb3bb959 | 1,557,643,402 | 4,113,776 | TRUE       |
| bwa      | fastdup  |          2 | 20225961 |            466181 |           235163 | 8ca85cbb809779fcabc3d16c35a6d66565d37825791f2afe2707b284cb3bb959 | 1,557,643,402 | 4,113,776 | TRUE       |
| bwa      | samtools |          2 | 20225961 |            466183 |           235164 | b7e4d17985f344365657f82993a0e29a66d2b3e0aa26dafc8f9375e8a6781b7f | 1,543,928,986 | 4,103,808 | TRUE       |
| bwa      | samtools |          3 | 20225961 |            466183 |           235164 | b7e4d17985f344365657f82993a0e29a66d2b3e0aa26dafc8f9375e8a6781b7f | 1,543,928,986 | 4,103,808 | TRUE       |
| bwa      | fastdup  |          3 | 20225961 |            466181 |           235163 | 8ca85cbb809779fcabc3d16c35a6d66565d37825791f2afe2707b284cb3bb959 | 1,557,643,402 | 4,113,776 | TRUE       |

| Mapper   | Repetition | Same duplicate-record count | Same duplicate-QNAME count | Same duplicate-QNAME digest |
|:---------|-----------:|:----------------------------|:---------------------------|:----------------------------|
| bwa      |          1 | FALSE                       | FALSE                      | FALSE                       |
| bwa      |          2 | FALSE                       | FALSE                      | FALSE                       |
| bwa      |          3 | FALSE                       | FALSE                      | FALSE                       |
| rminibwa |          1 | TRUE                        | TRUE                       | FALSE                       |
| rminibwa |          2 | TRUE                        | TRUE                       | FALSE                       |
| rminibwa |          3 | TRUE                        | TRUE                       | FALSE                       |

Matching duplicate counts alone do not prove identical decisions;
matching the sorted unique-QNAME digest provides a stronger marker-level
comparison. Any intentional differences caused by the RBCFTools FastDup
corrections remain governed by the package root `ERRATA.md`.
