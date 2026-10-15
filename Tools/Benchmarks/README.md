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
