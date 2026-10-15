# Render metrics

Measure one invocation without changing its rendering or failure policy.

## Overview

The 1.2 API ``LiquidEngine`` provides `renderWithMetrics` and
`renderWithDiagnosticsAndMetrics`, each accepting source or parsed templates.
Both return ``LiquidMeasuredRenderResult`` with output, diagnostics and immutable
``LiquidRenderMetrics``. The diagnostic method alone recovers eligible failures;
syntax, invalid values, quotas, cancellation and unexpected host errors still throw.
Failed invocations return no metrics.

```swift
let engine = LiquidEngine()
let result = try await engine.renderWithMetrics(
    template: "Hello, {{ name }}!", context: ["name": "Swift"]
)
print(result.output)
print(result.metrics.totalDuration)
```

Total duration uses a monotonic clock through final output admission and includes
host suspension. Source calls also report parsing time for the root and all
supplied partials; parsed calls have nil parse time. Parse time is included in
total time. The Liquid date reference clock is independent.

Counts describe admitted source bytes, final output bytes, consumed evaluator
steps, loop iterations and context/filter value visits. Partials share the same
budget. Counters follow the existing execution paths, including optimizations and
recovery. They are not allocations, CPU instructions or a portable cost model.
Ordinary APIs collect no timing, and no engine/template retains mutable metrics.

`liquid render --metrics PATH` writes a separate JSON metrics document after
rendered output delivery. It measures the prepared parsed-template call, excluding
CLI I/O and parsing. The metrics schema is independent of `analyze` JSON. A metrics
write failure fails the command even if output was delivered; the two outputs
are not a transaction. See the repository's metrics guide for schema 1 and I/O rules.
