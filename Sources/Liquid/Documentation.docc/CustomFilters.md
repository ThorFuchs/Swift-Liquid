# Custom filters

Supply typed application filters explicitly to an engine.

## Overview

Swift-Liquid 1.1 adds engine-scoped custom filters. Create a ``LiquidFilter``
with a Sendable asynchronous callback and pass it to the throwing
``LiquidEngine/init(filters:limits:strictFilters:referenceTime:)`` initializer.
The original initializer installs no filters and retains the 1.0 behavior.

```swift
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

Names are exact filter identifiers. Invalid names, duplicates and standard filter
names or aliases are rejected. Configuration is immutable; templates retain no
callbacks, so they can be reused with different engines. Shared engines can invoke
callbacks concurrently, and captures must meet checked Sendable requirements.

## Value boundary

The callback receives a ``LiquidValue``, positional values, and ordered named
values. Positional arguments evaluate first; named arguments retain their first
position and last expression when repeated. Ranges become bounded integer arrays.
Direct `blank`/`empty` comparison literals produce an invalid-value error.

Input/argument and result payloads each respect `outputBytes`, including text and
keys. Initial context and all filter-boundary value visits share `contextValues`.
Traversal also uses the invocation's evaluator-step and nesting limits. Returned
values pass admission before they enter another filter, assignment or output.

## Failure handling

Throw ``LiquidFilterFailure`` to opt into the existing explicit diagnostic
recovery rules. The raising API exposes the failure as a rendering error.
Unexpected callback errors, cancellation and operational failures propagate;
they are never converted into recovered output. Cancellation is checked before
and after awaiting the callback, including its error path.

The callback is trusted host code. Engine limits do not bound its own I/O,
allocations or execution time. There is no global registry, dynamic plugin loader,
filesystem discovery or CLI callback loading.
