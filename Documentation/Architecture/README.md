# Architecture

The public package contains one `Liquid` library and one `liquid` executable.
There are no third-party package dependencies. The adaptation starts from
RhoeLiquid commit `9e52492671bc31741932811fe689a86fed76be69`; the extraction
manifest records source paths and original file hashes.

The public boundary is deliberately small: `LiquidValue`, ordered `LiquidObject`,
`LiquidTemplate`, `LiquidEngine`, syntax modes, finite limits, public errors, and diagnostic render results.
Values, engines, and templates use checked Sendable conformance. The adapted
lexer, parser, AST, evaluator, and utility types are internal implementation details.

Each render creates its own renderer and budget. No actor serializes unrelated
render operations; no mutable cache or registry is shared between callers.
The private evaluator currently bridges admitted values to `Any` within one
invocation. This is an implementation boundary, not a public Sendable escape.
Foundation is used for text utilities, dates, and JSON string decoding. It does
not execute template code or provide implicit template loading.

Parsed partials are immutable and supplied in a source map. The renderer resolves
exact names and an optional `.liquid` suffix. `render` isolates local scope and
`include` shares Liquid state. All nested operations share one rendering budget.

Native String storage replaces upstream's unsafe inline byte representation.
Global registries, memory-pressure observers, optimized shared renderer caches,
data adapters, services, and document products are excluded from the public package.
The standard AST excludes macro, contract, inheritance, pipeline, and custom-tag
nodes. Variable and property keys preserve decoded Unicode scalar spelling.
String operations use Liquid code-point semantics rather than Swift grapheme counts.

Limits admit source and context before parsing/evaluation, check active nesting,
charge evaluation and loop work, and reject oversized rendered outputs. They are
logical operation capacities. Synchronous standard-library/Foundation helpers and
temporary intermediate allocation are not a hard heap/RSS or instruction quota.
Cancellation is checked at operation entry and execution boundaries.

Date recognition ports the pinned Ruby Date/Time grammar into Swift. Compiled
regular expressions are immutable and shared; parsing fragments, the base clock,
and recovered diagnostics belong to each invocation. An explicit reference time
makes partial-date parsing repeatable. BSD notices accompany the adaptations.

The 1.1 inspection API traverses the same internal AST used for
rendering. It retains the parsed partial reference alongside the existing render
name, distinguishes literal/dynamic includes, and returns an immutable summary.
Each traversal owns exact UTF-8 sets and checks source/depth limits and
cancellation. It does not enter the evaluator or call filters/load partials. The
CLI formats this summary without maintaining a separate source scanner. See
[inspection](../Inspection.md) for the API and versioned JSON contract.

Opt-in metrics share the normal execution path and snapshot its invocation budget
after final output admission. Immutable results include monotonic durations and
counts; measurement creates no shared mutable state, evaluator work or library
I/O. Ordinary APIs do not read a measurement clock. See [metrics](../Metrics.md).
