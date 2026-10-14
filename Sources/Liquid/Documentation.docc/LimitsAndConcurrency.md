# Limits and concurrency

Use independent rendering state with finite operation capacities.

## Concurrent calls

``LiquidEngine``, ``LiquidTemplate``, ``LiquidObject``, and ``LiquidValue`` are
Sendable. A parsed template can be shared by concurrent tasks. Each invocation
creates separate variables, scopes, loop counters, temporary output, and budget
state. There is no implicit global cache or mutable template registry.

## Finite limits

``LiquidLimits`` controls cumulative source bytes, output bytes, loop iterations,
syntax/render depth, evaluator steps, and admitted context values. The defaults
are finite. Invalid limits fail at operation entry. Nested partials share the
same invocation budget; the budget does not reset when entering a partial.

```swift
let engine = LiquidEngine(limits: .init(loopIterations: 1_000))
```

These capacities describe logical owned operations. They are not wall-clock
deadlines, process-memory ceilings, or guarantees about Foundation/helper work.
Applications remain responsible for context retention and publication of output.

## Errors and cancellation

``LiquidError`` distinguishes syntax, rendering, quota, and value failures.
Cancellation is checked at operation entry and execution boundaries and remains
Swift's `CancellationError`. Treat a failed render as terminal; retrying with a
fresh full budget does not preserve a cumulative limit across separate operations.
