# Metrics consumer

An independent SwiftPM package importing only public `Liquid` APIs. It checks
source/parsed metrics, nested partial counters, explicit recovered diagnostics
and checked Sendable results. Run from the repository root:

```sh
swift run --package-path Examples/MetricsConsumer LiquidMetricsConsumer
```

See the [metrics contract](../../Documentation/Metrics.md).
