# Opt-in render metrics

Swift-Liquid 1.2 API. `renderWithMetrics` has the same throwing
behavior as `render`. `renderWithDiagnosticsAndMetrics` has the same explicit
recovery behavior as `renderWithDiagnostics`. Both accept source or a parsed
template and return a checked Sendable `LiquidMeasuredRenderResult`, containing
`output`, `diagnostics` and `metrics`. Throwing renders return empty diagnostics.
Recovered diagnostics still mean the output is not error-free.

```swift
let engine = LiquidEngine()
let result = try await engine.renderWithMetrics(
    template: "Hello, {{ name }}!", context: ["name": "Swift"]
)
print(result.output)
print(result.metrics.outputBytes)
let parsed = try LiquidTemplate("{{ name }}")
let reused = try await engine.renderWithDiagnosticsAndMetrics(
    parsed, context: ["name": "Swift"]
)
assert(reused.metrics.parseDuration == nil)
```

## Observations

`LiquidRenderMetrics` is immutable, checked Sendable and Equatable. Its fields:

| Field | Meaning |
| --- | --- |
| `totalDuration: Duration` | Monotonic elapsed duration from measured entry to the snapshot after final output admission; includes parsing when requested, value admission, evaluation and suspension in host callbacks |
| `parseDuration: Duration?` | Source parsing interval, including root and all supplied partials, after cumulative source admission; nil for parsed-template calls |
| `sourceBytes: Int` | Cumulative UTF-8 bytes of the root and every supplied partial, even unused partials |
| `outputBytes: Int` | Final returned output's UTF-8 bytes, excluding intermediate/captured buffers |
| `renderSteps: Int` | Consumed evaluator-step capacity |
| `loopIterations: Int` | Consumed cumulative loop-iteration capacity |
| `admittedValues: Int` | Consumed context/custom-filter value capacity, including repeated boundary visits |

Durations use `ContinuousClock`, independently of the Liquid date reference
clock. Parse duration is a subset of total duration, including the empty-source
case. Parsed calls exclude all parsing done by their caller. Total duration
excludes result delivery and subsequent caller/CLI work. Timing may be zero at
clock resolution; there are no per-node or per-callback timers.

Counts snapshot the existing invocation budget without extra evaluation or an
AST walk. Nested partials share the same budget. Values count each context value
and each input, argument and result visit at host-filter boundaries; containers
and their elements count separately. Steps follow existing evaluation, rendering,
iteration and filter-boundary charging rules, including optimized paths. Counts
can differ between throwing and diagnostic rendering because those paths retain
their existing optimization and recovery behavior. Compare like entry points.
These observations describe this version's logical capacities, not allocations, instructions,
unique inputs or a stable cost model across versions. Final output bytes are not
peak output storage or the `outputBytes` capacity.

## Behavior and failures

Measured and ordinary rendering share one execution path, admission rules,
parser modes, partial scope, limits and error mapping. Measurement adds no steps
or value/iteration charges. Existing APIs collect no timing. Measurement state
belongs to the invocation; engines, parsed roots and partials retain no counters.
The result contains no source, context, paths or host arguments.

Syntax, invalid values/limits, quotas, cancellation and unexpected host errors
still throw with their existing identity. No measured result or partial metrics
are returned on failure. Explicit diagnostic rendering alone recovers eligible
Liquid errors; its result retains all diagnostics. Host callbacks remain trusted
application code, and budgets do not bound their I/O, allocation or execution time.

## CLI schema 1

`liquid render TEMPLATE --metrics PATH` uses the measured parsed-template API
after the existing CLI preparation. CLI file I/O and parsing are excluded from
the duration; `parseNanoseconds` is always null. This is render timing, not total
command time. Ordinary commands and `analyze` JSON schema 1 are unchanged.

The metrics file is one UTF-8 JSON object followed by a newline. All fields are
required; counts and durations are nonnegative integers, with durations expressed
as signed 64-bit nanoseconds, truncated toward zero. Null means parsing was not
measured, distinct from a measured zero. A duration outside this representation
fails the command instead of overflowing or converting to a floating-point value.

```json
{
  "schemaVersion": 1,
  "totalNanoseconds": 123456,
  "parseNanoseconds": null,
  "sourceBytes": 10,
  "outputBytes": 5,
  "renderSteps": 3,
  "loopIterations": 0,
  "admittedValues": 1
}
```

Consumers must parse JSON, ignore unknown fields and reject unsupported schema
versions. Compatible additions may add optional fields within version 1. Changing
types/meaning or removing/renaming required fields requires a new schema version.
Key order, indentation and escape spelling are presentation details.

Metrics go only to an explicit regular-file destination, never stdout (`-` is
rejected). Before rendering, the CLI rejects destinations aliasing template,
context, supplied partial or output files, including symlink/hard-link aliases.
It checks the destination's parent and replaces the metrics file atomically only
after successful rendering and output delivery. A prior metrics file remains on
render or write failure; it does not describe that attempt. Metrics writing may
still fail after preflight, causing stderr and exit 1 even if output was delivered.
Output and metrics files are separate atomic writes, not one transaction.

The [public consumer](../Examples/MetricsConsumer) and regression suite cover
source/parsed calls, recovery, admission, cancellation and concurrent reuse.
The release benchmark harness measures opt-in overhead independently of returned
durations; a single duration is not a comparative performance result.
