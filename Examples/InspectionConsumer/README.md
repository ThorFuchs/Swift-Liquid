# Public inspection consumer

This separate Swift 6 package imports only `Liquid`. It compares source and parsed
inspection, checks the immutable Sendable summary, and installs a callback that
must never run. Partial references need no supplied sources.

```sh
swift run --package-path Examples/InspectionConsumer LiquidInspectionConsumer
```

See [the inspection contract](../../Documentation/Inspection.md).
