# Performance measurements

Run `python3 Scripts/ci.py --lane performance` on an idle host. The standalone
Tools/Benchmarks package depends only on the local public Liquid library and
runs in release mode.

Workloads distinguish parsing plus rendering from rendering a reused parsed
template. They cover interpolation, a filter chain, a loop with properties, and
partial composition, and timestamp parsing/formatting. Each workload performs warmups, collects repeated samples,
checks expected output, and reports median, p95, minimum, maximum, and a stable
output checksum. Receipts include the actual command, compiler, platform, and
source hashes.

The 1.1 harness adds a separate custom-filter workload with positional
and named arguments plus standard-filter composition. The five original workloads
continue to use an engine with no application filters, so their output checksums
remain comparable. An empty registry is not inferred to have zero cost; matched
measurements against 1.0.0 are required for a performance claim.

A separate inspection workload measures parsing plus inspection and inspecting a
reused template. It checks all summary fields through a stable payload/checksum;
its timings include payload verification and hashing. These records are not render
latencies and do not execute callbacks or load partials.

The 1.2 harness adds metrics-enabled source and parsed calls for all six render
workloads, yielding 26 records including inspection. It retains 25 sample values
per record and twelve enabled/disabled summaries. Whole calls are timed externally;
returned metrics durations are not used as benchmark measurements. A fixed-order
single run is an observation, not a release regression verdict.

Measurements describe this host and workload. They do not establish superiority
over Ruby, Liquid-C, or another Swift implementation, and latency does not imply
process-memory usage. A matched reference comparison needs the same fixtures,
outputs, warmup, sample policy, and environment. A 10% median change triggers
review against an explicitly retained baseline; it is not automatically a release failure.

No speedup claim is carried over from RhoeLiquid. The [1.1 benchmark review](PerformanceReview-1.1.md)
records the initial comparison and its limits. Each release-candidate CI run retains
its own complete comparison and review flags.

## Matched 1.1.0 comparison

Run `python3 -B Scripts/ci.py --lane matched-performance` from a clean candidate
commit with immutable 1.1.0 commit
`1107ec865b9ae7ed35e1245386ba882db3abd93d` available locally. The common harness is
copied unchanged from that commit into both library checkouts. Its SHA-256 is
`cdaa1ce76d114eb12ef163a8e5445704a7da6ae5563a17abffd6de5c2d2de77f`; the manifest
SHA-256 is `aaf1bad0e6c4c7165b35320bf95878a2a3ac20a5efa9362066901ac9836b4439`.
No floating branch or tag selects the baseline.

This phase compares 14 records: source/reused rendering of interpolation, standard
filters, loops, partials, dates and custom filters, plus source/reused inspection.
Three serial ABBA blocks run baseline, candidate, candidate, baseline, producing
six complete runs per version. Each uses 25 measured samples, ten warmup samples
and 100 repetitions per sample. The unchanged 1.1 harness retains each run's
median, p95, minimum, maximum and output checksum. The comparison reports the
median of six run medians, with every run retained.

## Matched metrics overhead

A second phase uses one candidate binary with the current benchmark harness.
`--render-mode ordinary` and `--render-mode metrics` select 24 render records across throwing and diagnostic policies independently. Three further ABBA blocks alternate ordinary, metrics,
metrics, ordinary, yielding six runs per mode. The source, context, partials,
filters, sampling and expected outputs match the common workloads. All 25 sample
latencies per metrics-phase record are retained, along with checksums, six run
medians per side and 24 summary comparisons.

The baseline, common candidate and metrics candidate binaries all build before
any timing begins. Candidate library fingerprints must match across the two
harnesses. Every output checksum and sampling policy must match across compared
runs and across phases. No build occurs between timed runs. Inspection is excluded
from the metrics phase because it does not render.

## Review and evidence

Positive change means higher latency. Absolute median changes at or above 10%
produce review flags in each phase, including faster results. Mechanical success
is not a regression or overhead verdict. Review distributions, workload meaning
and environment; investigate material slowdowns and repeat when needed. Report
opt-in cost without implying the ordinary path has zero overhead or claiming a
speedup from noisy faster samples.

The schema-2 comparison records compiler, OS, architecture, CPU/model, memory,
library/harness hashes, exact commands, run order and load averages. CI waits for
its other qualification lanes before this job. That reduces interference from
this repository, but does not establish idle hardware, thermal stability or
isolation from unrelated jobs.

The historical [1.1 review](PerformanceReview-1.1.md) and released 1.0/1.1 evidence
remain unchanged. Final candidate CI is authoritative for that source inventory;
inspect both flag lists before preparing release assets. Packaging requires a
separate reviewed record bound to the comparison SHA-256. These measurements
cover small workloads and do not establish process-memory use or superiority to
another engine.
