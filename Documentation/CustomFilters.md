# Engine-scoped custom filters

Custom filters are an unreleased 1.1 development feature. The 1.0.0 tag keeps its
original API. The root package still has no package dependencies and exports
only the `Liquid` library and `liquid` executable.

## Configuration

Create a `LiquidFilter` with a Sendable asynchronous callback, then pass filters
to the throwing engine initializer:

```swift
import Liquid

let label = LiquidFilter("label") { input, arguments, named in
    guard case .string(let text) = input,
          case .string(let prefix) = arguments.first else {
        throw LiquidFilterFailure("Expected text and a prefix")
    }
    let separator: String
    if case .string(let value) = named["separator"] { separator = value }
    else { separator = ": " }
    return .string(prefix + separator + text)
}
let engine = try LiquidEngine(filters: [label], strictFilters: true)
let output = try await engine.render(
    template: "{{ title | label: 'Topic', separator: ' — ' | escape }}",
    context: ["title": "Swift & Liquid"]
)
// Topic — Swift &amp; Liquid
```

Names must be single identifiers accepted by the existing filter syntax.
Spelling is exact and case-sensitive, including Unicode scalar spelling.
The engine rejects invalid names, exact duplicates, and standard filter names
or aliases, including `h`. Configuration failures are `LiquidError.invalidValue`.
There is no override option or registration/removal operation.

The existing nonthrowing `LiquidEngine(limits:strictFilters:referenceTime:)`
initializer remains unchanged and installs no custom filters. Unknown filter
behavior remains controlled by `strictFilters`.

## Arguments and values

The callback receives the pipeline input, `[LiquidValue]` positional arguments,
and a `LiquidObject` of named arguments. Expressions are evaluated once:
positional arguments first in their source order, then named arguments in their
first-occurrence order. Repeated named arguments use the last expression at the
original position, matching the pinned Ruby parser's argument containers.
The parser permits positional and named arguments to be interleaved.

Values preserve nil, booleans, native integers, finite floating-point numbers,
strings, arrays, and ordered objects. Explicit object order and exact key
spelling survive both sides of the callback. Internal dictionaries without
ordering metadata, such as loop metadata, use UTF-8 key order at this boundary.
Ranges become bounded integer arrays. Direct `blank` and `empty` comparison
literals are rejected with `LiquidError.invalidValue`; they do not acquire new
public enum cases or silently become strings. Assignment retains its existing
Liquid coercion rules before a later filter sees the assigned value.

The admitted input and arguments together have a maximum UTF-8 payload size of
`outputBytes`, counting strings, object keys and named argument names. The returned
value has the same independent capacity. Every visited value consumes the
invocation's cumulative `contextValues` allowance, including the initial context,
callback input/arguments, and returned values. Traversal also charges
`renderSteps`, checks cancellation and enforces `nestingDepth`. All partials and
filter calls share these budgets. This can reject a large value even if a later
filter would reduce it.

Returned non-finite numbers, oversized payloads, excessive nesting, or exhausted
budgets fail before another filter or assignment can consume the value.
These failures remain operational errors in both rendering APIs.

## Failures and cancellation

Throw `LiquidFilterFailure(message)` for an application filter failure that may
participate in explicit recovery. The raising API throws `LiquidError.rendering`
with `Filter 'name' failed: message`. `renderWithDiagnostics` applies the existing
node recovery rules: lax/strict assignments suppress error text, strict2
assignments emit it, output/echo emit it, and failed assignments retain the old
value. Diagnostics include the available line and partial name. Error messages
also respect output capacity.

Unexpected callback errors propagate unchanged. Throwing `LiquidError` from a
callback does not opt it into recovery. Cancellation is checked before and after
the callback, including when it throws a recoverable failure; a cancelled task
cannot return recovered output instead. Cooperative callbacks should check
cancellation during their own long-running work.

Callbacks are trusted application code. They can perform work outside the engine,
and logical render limits cannot bound their allocations, I/O or execution time.
Keep captured state immutable or isolate it using Swift concurrency. A shared
engine may invoke the same callback concurrently.

## Scope and qualification

Configuration belongs to the engine. Parsed templates retain no callback
references and can be reused with differently configured engines. Each render
owns mutable scope, diagnostics, counters and budgets; explicit partials use the
same immutable filter configuration. The CLI does not discover or load callbacks.

The unchanged [1.0 consumer](../Examples/Consumer) qualifies source compatibility.
A separate [custom-filter consumer](../Examples/FiltersConsumer) uses only public
APIs. Fifteen pinned cases compare matching Ruby/Swift host callbacks, separately
from the 2,032 core reference checks. Swift configuration, conversion, admission,
failure, cancellation and isolation policies have dedicated public regression tests;
they do not increase the Shopify core conformance count.
