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

The 1.2 development harness adds metrics-enabled source and parsed calls for all
six render workloads, yielding 26 records including inspection. Each enabled
record must retain the ordinary record's output checksum. The JSON retains all
25 sample values and reports twelve enabled/disabled median comparisons. These
measure whole API calls externally, not their returned durations. Execution is
sequential in a fixed order; a single run does not isolate drift, background load
or thermal effects. Treat these comparisons as instrumentation observations,
not a release regression verdict or a speedup claim.

The matched release gate still retains its pinned 1.0.0 common harness. Updating
the baseline to 1.1.0 and extending it to all common 1.1 workloads belongs to final
1.2 release preparation, as specified by the adopted roadmap. Historical receipts
remain unchanged.

Measurements describe this host and workload. They do not establish superiority
over Ruby, Liquid-C, or another Swift implementation, and latency does not imply
process-memory usage. A matched reference comparison needs the same fixtures,
outputs, warmup, sample policy, and environment. A 10% median change triggers
review against an explicitly retained baseline; it is not automatically a release failure.

No speedup claim is carried over from RhoeLiquid. The [1.1 benchmark review](PerformanceReview-1.1.md)
records the initial comparison and its limits. Each release-candidate CI run retains
its own complete comparison and review flags.

## Matched 1.0.0 comparison

Run `python3 -B Scripts/ci.py --lane matched-performance` from a clean candidate
commit with the 1.0.0 commit available locally. CI fetches the exact commit
`d36018e6b6822ae408a6c1c439c2307484525b7b`; no floating branch or tag resolution
selects the baseline. Both libraries are built with the unchanged 1.0.0 benchmark
source and manifest, with a pinned harness SHA-256. The root package is unchanged.

Both binaries are built before timing. Three sequential ABBA blocks run baseline,
candidate, candidate, baseline, yielding six complete runs per version. Each run
uses the original 25 samples, 10 warmup samples and 100 repetitions per sample.
The report compares the median of six run medians for each of ten workload/mode
pairs and retains every run's latency summary, checksum and run order. Positive change
means higher latency. Changes of either sign at or above 10% require review;
mechanical measurement success does not resolve a review flag.

The receipt records toolchain, OS, architecture, CPU/model, memory, source hashes,
common harness hash and load averages. Comparisons run in one process sequence
on one host; no builds occur during timing. The CI comparison waits for this
repository's other qualification jobs, reducing interference from those jobs.
It does not establish an idle machine, thermal stability or unrelated-workload
isolation. Review outliers and repeat a comparison when they leave a material
regression unresolved.
