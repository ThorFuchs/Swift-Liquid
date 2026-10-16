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

## Matched 1.3.0 comparison

Run `python3 -B Scripts/ci.py --lane matched-performance` from a clean candidate
commit with immutable 1.3.0 commit
`9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e` available locally. The common harness is
copied unchanged from that commit into both library checkouts. Its SHA-256 is
`2aed7fe384085e4b4b5ba26dcb2545f4006248822b21a864ef515cc51d3c985f`; the manifest
SHA-256 is `aaf1bad0e6c4c7165b35320bf95878a2a3ac20a5efa9362066901ac9836b4439`.
No floating branch or tag selects the baseline.

This phase compares all 26 records: ordinary and measured source/reused rendering
of interpolation, standard filters, loops, partials, dates and custom filters,
plus source/reused inspection. All common inputs, modes, output checksums and
sampling come from the unchanged 1.3 harness.
Three serial ABBA blocks run baseline, candidate, candidate, baseline, producing
six complete runs per version. Each uses 25 measured samples, ten warmup samples
and 100 repetitions per sample. The unchanged 1.3 harness retains every individual sample, each run's
median, p95, minimum, maximum and output checksum. The gate recomputes summary
statistics from those samples. The comparison reports the
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

The schema-4 comparison records compiler, OS, architecture, CPU/model, memory,
library/harness hashes, exact commands, run order and load averages. CI waits for
its other qualification lanes before this job. That reduces interference from
this repository, but does not establish idle hardware, thermal stability or
isolation from unrelated jobs.

Each comparison also retains both sides' six run medians, their median absolute
deviation (MAD), relative MAD, and `(maximum - minimum) / median` as a percentage.
A range at or above 10% adds a separate variance-review flag, even when the two
aggregate medians agree. This describes observed spread; it is not a confidence
interval, a proof of independent samples or an estimate of population variance.
Release admission recomputes these fields and both variance flag lists from the
retained runs, and requires the bound review to acknowledge them.

The 1.3.0 common harness and manifest have the same hashes as the previously used
1.2.0 harness. Advancing the pinned library baseline changes no common workload,
output or sample policy. Historical comparisons retain their original baseline.

The historical [1.1 review](PerformanceReview-1.1.md) and released 1.0–1.3 evidence
remain unchanged. Final candidate CI is authoritative for that source inventory;
inspect both flag lists before preparing release assets. Packaging requires a
separate reviewed record bound to the comparison SHA-256. These measurements
cover small workloads and do not establish process-memory use or superiority to
another engine.

## Dependency graph workloads

The performance lane also builds `Tools/DependencyBenchmarks` in release mode.
Four records measure source and parsed inspection for a 66-node shared diamond
(128 edges) and a 129-node graph with a 128-member cycle (129 edges). Each retains
ten warmups, 25 measured samples of 20 repetitions, stable name checksums and
full result equality audits inside the timed boundary. The packaging gate checks
the four shapes/modes, sample policy, checksums and recomputed median/p95.

These observations measure graph inspection separately. They are not render
latencies or a matched graph comparison; no graph speedup claim follows. Their result
checking costs remain in the observations. Source/library/toolchain receipts
accompany both benchmark packages; final qualification and its bound review are
authoritative for the candidate source inventory.

## Larger workloads and cancellation response

The performance lane additionally runs `Tools/MaintenanceBenchmarks` in release
mode. See [measured maintenance](MeasuredMaintenance.md) for its workload shapes,
timing boundaries, admission and cancellation limitations. These observations are
separate from the common cross-version and metrics comparisons. No runtime
optimization or latency guarantee follows from adding a measurement.

The [1.3.1 maintenance review](PerformanceReview-1.3.1.md) records the PR #14
flags and the independent-host investigation of possible output-checkpoint cost.
The final qualification archive retains every observation and the bound release
decision; earlier measurements are not substituted for the final candidate.

The [interpolation investigation](PerformanceReview-Interpolation.md) retains
controlled 1.3.1 comparisons and rejected hypotheses separately from the pinned
release comparison. Caller context and identical-source controls are explicit.

The [caller/date follow-up](PerformanceReview-CallerDate.md) separates actor round
trips from render work, retains all cross-version and identical-source observations,
and rejects a formatter candidate whose benefit was not corroborated under both
callers. The production engine remains unchanged after that investigation.

The [recurring date investigation](PerformanceReview-RecurringDate.md) directly
compares 1.3.0 with merged main using wall and process CPU observations, explicit
callers and identical-source controls. It retains the unresolved historical date
flags and the adverse filter control without changing the production engine.

The [CPU and executor trace follow-up](PerformanceReview-DateTracing.md) retains
sampled stacks, actual executor events, image-identity symbolication and every
untraced review flag. Recorder failures and incomplete cohorts remain explicit.
Trace elapsed values are separate from ordinary benchmarks; no production change
or historical date-regression clearance follows.

The [controlled recognition study](PerformanceReview-DateRecognition.md) separates
lowercasing, full date recognition, loose-parser construction/parsing and known-date
formatting under explicit callers, with typed audit controls and independently
built identical-source comparisons. Its [complete aggregate appendix](PerformanceReview-DateRecognition-Data.md)
retains all 404 comparisons and both flag lists. Grammar work is the next observed
CPU target for these inputs; the production engine and cancellation checkpoints
remain unchanged, and historical date flags remain unresolved.
