# Render exact named content

Use the required `registry:` argument with the four render families, accepting
either a source root or a parsed ``LiquidTemplate``. All use the existing evaluator,
one runtime budget and immutable ``LiquidTemplateRegistry`` entry indexes.

```swift
import Liquid

let registry = try LiquidTemplateRegistry([
    .init("é", .raw("first")),
    .init("e\u{301}", .parsed(try LiquidTemplate("second")))
])
let result = try await LiquidEngine().renderWithMetrics(
    template: "{% include 'é' %}|{% render 'e\u{301}' %}", registry: registry)
// result.output is "first|second".
```

## Preparation before evaluation

Root plus every entry source, including unused content, must fit ``LiquidLimits``.
Raw content is parsed in declaration order using the supplied syntax mode. Parsed
inputs retain their AST/mode and are checked against current depth limits. No host
callback or output occurs until the entire bundle is prepared. Invalid unused
content is terminal. Syntax errors retain existing anonymous line/column metadata.

Each lookup uses ``LiquidTemplateRegistry/resolve(_:)`` once to select the stored
index/name/AST. Literal-first include may retry a context String only after an
actual miss. Name capacity, cancellation and host errors never trigger retry.
Shared include and isolated render semantics are unchanged. Runtime diagnostic
names retain actual stored UTF-8 spelling, including a selected suffix.

## Observations and limits

Metrics are returned only after completed output admission. `parseDuration` sums
actual raw-template construction intervals; nil means no raw input was parsed.
A parsed root with raw entries therefore has parse duration. `totalDuration`
includes source admission, preparation, parsed-AST validation and runtime. The
source count includes all entries; remaining counters use the same runtime ledger.

Diagnostic rendering recovers only existing approved runtime failures. Admission,
syntax, capacity, cancellation and unexpected host errors remain terminal, without
partial output/metrics. Logical budgets do not bound process memory or interrupt
synchronous standard-library operations. Hosts own authorization and error policy.

Existing `templates:` calls retain canonical String lookup. Exact dependency
inspection, CLI and Vapor migration remain separate gates. No new grammar, I/O,
cache, automatic escaping or release is implied.
