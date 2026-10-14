# Liquid language contract

The 1.0 target is the open-source Shopify Liquid core, with the pinned 5.14.0
Ruby implementation as a reference. It is separate from Shopify's hosted theme
objects, tags, and commerce filters. Shopify documents that distinction in
[Liquid variations](https://shopify.github.io/liquid/basics/variations/).

Standard surface:

| Area | Features |
| --- | --- |
| Output | Variables, dot/bracket lookup, negative array indices, filter pipelines, whitespace control |
| Values | Strings, integers, floats, booleans, nil/null, ordered objects, arrays, ranges, blank/empty comparison literals |
| Conditions | if/elsif/else, unless, case/when, comparison, contains, right-associative and/or |
| Iteration | for/else, limit, offset/continue, reversed, forloop, tablerow, cycle, break, continue |
| Variables | assign, capture, increment, decrement; separate counter namespace |
| Composition | include shared scope, render isolated scope, explicit partial source maps |
| Utility tags | raw, comment, inline comment, doc, echo, liquid, ifchanged |
| Filters | Standard string, HTML, URL, Base64, numeric, date, and array filters, including squish and remove_last |

Only nil and false are falsy. Output is not automatically HTML-escaped. Logical
operators associate right to left. `blank` and `empty` are distinct comparison
literals; they do not resolve an identically named input property unless followed
by access segments. Literal object entries and JSON object entries retain order.

Unknown filters leave their input unchanged by default, as in open-source Liquid.
`LiquidEngine(strictFilters: true)` makes them errors. Rhoe extension filters are
treated as unknown filters. Unknown tags are syntax errors. `LiquidSyntaxMode`
selects lax, strict, or strict2 parsing; the fixture runner preserves these modes.

The 1.1 [custom-filter API](CustomFilters.md) lets a host explicitly
provide additional names for one engine. Empty configuration preserves the 1.0
surface. Standard names and aliases cannot be overridden, and template parsing
does not retain host callbacks or gain a second dialect.

The supported numeric domain is Swift `Int` plus finite binary `Double`, rather
than Ruby's arbitrary-precision integers. JSON values outside `Int` may round to
Double; strings are appropriate when exact large-decimal representation matters.
Numeric overflow/non-finite input must fail as an operational error, never crash.
String sizes, splitting, first/last access, and slicing use Unicode code points.
Keys and equality retain Unicode scalar spelling. Case mapping uses the native
Unicode implementation. Dates accept whole-second epochs, complete ISO and
ordinal dates, English month names, RFC and asctime forms. Timezone-free input
uses UTC; explicit offsets and
parsed decimal fractions are preserved. Calendar years are bounded to 1...9999.
Ruby Date's loose grammar and Time.parse's defaults are implemented, including
partial dates and embedded fragments. See [dates](Dates.md) for the UTC hosting
policy, reference clock, coercion, and supported range. Integer `size` follows the native integer storage
width (8 bytes on the qualified 64-bit host).

Finite limits can reject an otherwise valid template. The raising render API throws on syntax/runtime failures and quota exhaustion;
cancellation remains `CancellationError`. Explicit diagnostic rendering can
recover Liquid runtime errors while retaining every diagnostic; see
[errors and recovery](Errors.md).
These limits are policy, not language invalidity. They do not certify a process
sandbox, wall-clock deadline, or memory ceiling.

The golden suite is evidence of tested behavior, not a formal proof that every
possible Liquid program agrees with Shopify. Known or newly discovered
differences must be documented in [conformance evidence](Conformance.md) and
resolved or explicitly scoped before a stable compatibility claim is released.
