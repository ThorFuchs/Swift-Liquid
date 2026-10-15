# Release benchmarks

```sh
swift run -c release --package-path Tools/Benchmarks LiquidBenchmarks /tmp/liquid-benchmarks.json
```

The executable measures six render workloads in source and reused-template modes,
each with metrics disabled and enabled, plus source/reused inspection: 26 records.
Each runs ten warmup samples and 25 measured samples of 100 repetitions. Outputs
are checked, and measured/unmeasured pairs must retain matching checksums. JSON
retains sample latencies and twelve instrumentation-overhead comparisons.

The FNV-1a checksum detects changed output; it is not a cryptographic hash.
`Scripts/ci.py --lane performance` adds compiler, source, command and exit receipts.
Timings measure calls externally, independently of returned render metrics. A
fixed-order run cannot establish a release regression verdict; see the
[performance guide](../../Documentation/Performance.md) for matched qualification.

For repeated instrumentation comparison, the same binary supports explicit modes:

```sh
LiquidBenchmarks /tmp/ordinary.json --render-mode ordinary
LiquidBenchmarks /tmp/metrics.json --render-mode metrics
```

Each mode emits twelve render records with all sample values. The matched lane
builds both versions with the unchanged pinned 1.1.0 common harness, then compares
metrics modes in a separate candidate binary. Both phases use three serial ABBA
blocks; all three binaries are built before timing. The package manifest and
library fingerprints, checksums, sampling, distributions and review flags are
retained. Historical 1.0/1.1 artifacts remain unchanged.
