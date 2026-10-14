# Release benchmarks

```sh
swift run -c release --package-path Tools/Benchmarks LiquidBenchmarks /tmp/liquid-benchmarks.json
```

The executable measures four workloads in two modes: parse/render and reused
template. Each mode runs ten warmup samples and 25 measured samples of 100
repetitions. Every output is checked. The FNV-1a checksum detects changed output;
it is not a cryptographic hash. `Scripts/ci.py --lane performance` adds compiler,
source identity, command, and exit receipts.
