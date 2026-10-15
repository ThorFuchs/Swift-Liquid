# Dependency inspection benchmarks

The performance lane builds this independent package in release mode before
measuring source and parsed bundles for a shared diamond and a cycle. Each of
four records retains ten warmup samples, 25 measured samples of 20 repetitions,
all latencies, median/p95, graph shape and a stable name checksum. Every invocation
also checks the full result against the admitted expected graph. Equality and
checksum audit costs are inside the external timing boundary.

```sh
python3 -B Scripts/ci.py --lane performance
```

These new workloads measure graph costs separately. They do not modify the
existing pinned matched render/inspection/metrics harness or establish a speedup.
