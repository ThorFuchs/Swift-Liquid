# Runtime errors and explicit recovery

`render` throws when a runtime operation fails, following Shopify's raising
render API. Parsing, cancellation, unsupported values, and exhausted budgets
also throw. The CLI uses this behavior and preserves an existing output file
when rendering fails.

Ruby's non-raising renderer can recover an error and continue. Output alone is
insufficient to distinguish that behavior from an error-free render. Use
`renderWithDiagnostics` when recovery is part of your application:

```swift
let result = try await LiquidEngine().renderWithDiagnostics(
    template: "A{% assign b = items | reject: missing %}B",
    context: ["items": ["x"]]
)
// result.output == "AB"
// result.diagnostics[0].message == "cannot select the property ''"
// result.diagnostics[0].line == 1
```

Diagnostics retain encounter order, line numbers where available, and partial
names. Each invocation owns its diagnostic array. Reusing an engine or parsed
template does not carry errors into later renders.

Unexpected-character syntax errors can retain a verified original source excerpt
and construct/header position. These positions use one-based LF lines and Unicode
scalar columns; Ruby column parity is not claimed. Ambiguous, rewritten and inner
`liquid` contexts keep their existing failure when an original context cannot be
established. Syntax errors still throw through every rendering policy. See the
[internal source-origin contract](LQ1-R5/INTERNAL_SOURCE_ORIGIN.md) for coverage and
the distinction between source, construct and offending-character positions.

In lax and strict modes an error inside `assign` is recorded while its rendered
text is suppressed. Strict2 emits its error text. Output variables and `echo`
emit error text; captures and explicit partials retain the same boundaries.
Unknown filters with strict filtering record an error without emitting error
text. Failed assignments leave the previous variable value intact.

Recovery applies to Liquid runtime errors. It never converts cancellation,
syntax failures, unsupported numeric/date values, security failures, or resource
exhaustion into successful output. An application must inspect diagnostics
before treating a recovered result as error-free.

Application filters opt into this recovery only by throwing `LiquidFilterFailure`.
Unexpected host errors propagate unchanged, and cancellation is checked again
after awaiting a callback. See [custom filters](CustomFilters.md) for value
admission, shared budgets and the 1.1 extension contract.

The 1.2 APIs `renderWithMetrics` and
`renderWithDiagnosticsAndMetrics` preserve these respective throwing/recovering
policies. Failed invocations return no metrics or wrapped error. See
[metrics](Metrics.md).

The independent corpus's unchanged `reject: missing` case is qualified against
both its empty output and its recorded error. Its sidecar annotation is pinned
separately and checked by both runtimes. Reference receipts count recovered
errors separately from successful renders; no fixture is excluded or rewritten
to disguise the error.
