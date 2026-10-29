# Exact registry rendering — development U2

The eight additive `registry:` render APIs use the existing evaluator and one
invocation-owned budget. Each family accepts a raw or parsed root: `render`,
`renderWithDiagnostics`, `renderWithMetrics`, and
`renderWithDiagnosticsAndMetrics`. The registry argument is required; calls using
the older `templates:` dictionaries keep their signatures, defaults and canonical
Swift String lookup behavior. No released version or Vapor dependency change is
implied by this local feature checkpoint.

```swift
import Liquid

let registry = try LiquidTemplateRegistry([
    .init("é", .raw("first")),
    .init("e\u{301}", .parsed(try LiquidTemplate("second")))
])
let output = try await LiquidEngine().render(
    template: "{% include 'é' %}|{% render 'e\u{301}' %}", registry: registry)
// first|second
```

The [executable public consumer](../Examples/ExactRegistryConsumer) exercises all
eight APIs, mixed source, function references, original-byte identities, typed
failures and timing presence. Existing dictionary consumers remain unchanged.

## Atomic preparation and lookup

Every invocation checks cancellation, validates runtime limits, and admits root
plus **all** entry source UTF-8 bytes, including unused entries. Source admission
uses remaining-capacity subtraction with cancellation polling and rejects before
parsing or callbacks. A root also registered as a partial is deliberately charged
twice. Registry name capacities remain separate from engine source capacities.

Next it parses the raw root, then raw entries in declaration order. Parsed inputs
retain their original AST/parser mode and are revalidated under the executing
engine's current nesting profile after the raw parses, root first then entries.
An invalid unused source/AST blocks the invocation before context admission or
host callbacks. `syntaxMode = .lax` applies to raw content only, including raw
entries under a parsed root. Preparation syntax errors retain the existing
anonymous `LiquidError.syntax` line/column; the public parsed-template constructor
does not attach an entry name. No extra source provenance is fabricated.

The prepared table contains one AST per original registry entry. Each candidate
calls `registry.resolve` once and uses its stored index directly, without a
String-keyed AST dictionary or a second resolution. Exact name wins before
literal `.liquid` append. Runtime diagnostics use the selected stored spelling.
Canonical siblings remain distinct throughout nested include/render.

Include preserves literal-first lookup and existing binding evaluation order.
Only a genuine missing literal candidate permits a context-string retry through
the same resolver. Overlong names, cancellation and unexpected errors propagate.
Shared include scope, isolated render scope, iteration/cycle/interrupt state and
immediate-template dispatch are the existing runtime paths. Variable-form render
grammar remains unsupported. Public include bindings accept primary expressions,
not filter pipelines, and include-for has its existing default alias; render-for
supports its existing explicit alias. No syntax is added to broaden these forms. Exact registry dependency inspection is available in the local U3 checkpoint;
the CLI and Vapor still use their existing APIs.

## Successful-only metrics, errors and bounds

For registry calls, `parseDuration` sums actual raw `LiquidTemplate` construction
intervals, including their normal parser/validation work. It is non-nil if any raw
root or entry was parsed, even an unused empty entry under a parsed root. It is
nil only when every input is already parsed. Separate parsed-AST revalidation and
source admission are outside that field but inside `totalDuration`, which starts
before preparation and includes runtime/host suspension through final admission.
There are no timing thresholds or performance claims.

`sourceBytes` is root plus every entry. Output, step, loop and value observations
come from the single existing runtime budget after successful output admission.
Only existing recoverable runtime failures become diagnostics. Syntax/admission,
quota, cancellation and unexpected host errors throw without returning partial
output, diagnostics or metrics. U1 `AdmissionError` name-capacity errors remain
typed and terminal in every family.

These are logical quotas, not RSS or wall-time bounds. Strings, ASTs, retained
registry inputs, parser tokens and output may overlap. Standard-library UTF-8
view materialization, hashing/equality and COW are synchronous; cancellation is
cooperative. Names are opaque identities, not authorization or filesystem paths.
The host controls access and safe error/log presentation. No I/O, cache, escaping
policy, grammar, dependency or deployment-floor change is introduced.
