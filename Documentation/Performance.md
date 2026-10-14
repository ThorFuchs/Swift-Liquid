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

The 1.1 development harness adds a separate custom-filter workload with positional
and named arguments plus standard-filter composition. The five original workloads
continue to use an engine with no application filters, so their output checksums
remain comparable. An empty registry is not inferred to have zero cost; matched
measurements against 1.0.0 are required for a performance claim.

A separate inspection workload measures parsing plus inspection and inspecting a
reused template. It checks all summary fields through a stable payload/checksum;
its timings include payload verification and hashing. These records are not render
latencies and do not execute callbacks or load partials.

Measurements describe this host and workload. They do not establish superiority
over Ruby, Liquid-C, or another Swift implementation, and latency does not imply
process-memory usage. A matched reference comparison needs the same fixtures,
outputs, warmup, sample policy, and environment. A 10% median change triggers
review against an explicitly retained baseline; it is not automatically a release failure.

No speedup claim is carried over from RhoeLiquid. Public benchmark results will
be recorded after the current correctness and resource checks complete.
