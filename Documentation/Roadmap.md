# Swift-Liquid 1.1 roadmap

## Adopted scope

The maintainer adopted this scope on 2026-10-14. Swift-Liquid 1.1 will add two
capabilities: typed custom filters scoped to an
engine, and read-only template inspection shared by the library and CLI. This
gives applications a small integration surface and better tooling while keeping
Shopify core behavior, reusable templates, and the dependency graph intact.

The [upstream feature review](Architecture/UpstreamFeatureReview.md) records the
features retained in RhoeLiquid and the implementation boundaries behind this
selection. Implementation begins with [typed custom filters](CustomFilters.md).
Read-only inspection is implemented on the development branch with the
[AST summary and CLI JSON contract](Inspection.md). Release qualification remains
a separate step. The scope decision
authorizes these additions under [AGENTS.md](../AGENTS.md); publishing a 1.1 version
still requires a separate release request.

## Package and compatibility constraints

- Keep Swift tools/compiler 6.4 or later, Swift language mode 6, one `Liquid`
  library and one `liquid` executable, with an empty root dependency graph.
- Preserve the 1.0 public API and default Shopify core behavior. Add opt-in
  interfaces without replacing existing initializers or render overloads.
- Keep public configuration, inputs, templates and results checked Sendable.
  Keep scopes, diagnostics, counters and budgets owned by each render.
- Keep template I/O explicit. The library gains no filesystem loader, network
  client, global registry, implicit cache, or dynamic plugin loading.
- Preserve all existing fixture bytes, parser modes, licenses and pins.
  Keep core compatibility results distinct from host-extension tests.

## Typed custom filters

Applications should supply an immutable collection of named filters when they
create an engine. A filter receives `LiquidValue` input, positional values and
named values, and returns a `LiquidValue` asynchronously. Implementations and
closure captures must satisfy checked Sendable rules. Public type names and
signatures remain subject to the API design review.

The default collection is empty. A parsed template can be reused with engines
that supply different filters; it must not retain callbacks or mutable registry
state. Filter lookup must respect exact name semantics and preserve the standard
dispatch path. Reject invalid names, duplicates, and collisions with standard
filter names or aliases at configuration time. Overriding standard filters is
outside the proposed 1.1 scope.

The design review must settle conversion of runtime-only values such as ranges
and `blank`/`empty`, argument evaluation order, and named-argument semantics.
These values must receive documented conversion or a typed failure; they must
not escape as `Any` or change silently through stringification. Returning a
non-finite number or an oversized/deep value must fail admission before further
evaluation. Reuse the invocation's limits rather than resetting nested work.

Define an explicit recoverable filter failure for `renderWithDiagnostics`.
Cancellation, exhausted quotas, invalid values and unexpected host errors must
retain their operational meaning. Check cancellation before and after awaiting
host code. Host callbacks remain trusted application code; logical render limits
cannot bound their I/O, allocations, or uncooperative execution time.

Acceptance requires public consumer cases for positional and named arguments,
nil/false and ordered objects, chained standard/custom filters, partials,
raising versus diagnostic rendering, and two engines rendering the same parsed
template concurrently without configuration leakage. Include suspending
callbacks, cancellation, returned-value admission and name collisions. The CLI
does not load application callbacks or introduce plugin discovery.

## Read-only template inspection

Expose a small checked Sendable summary derived from a parsed template's
internal AST. The first version should report referenced variable roots,
filter names, literal partial references, and whether dynamic partial references
occur. Use deterministic ordering and exact identifier spelling. Treat variable
roots as syntactic references, not a list of required context keys: assignments,
loop scopes and conditional paths affect runtime lookup.

Inspection must use the same parser modes and source/nesting limits as rendering.
It must not evaluate expressions, call filters, open partials, or render output.
Inspect each supplied template independently; automatic traversal of a partial
graph is deferred. Keep the AST private and avoid a general visitor protocol or
an extensible analyzer framework in 1.1.

Add `liquid analyze TEMPLATE` with text output and `--format json`. Parsing and
I/O failures follow existing stderr and exit-code conventions. Document the JSON
schema and its evolution policy before freezing the CLI contract. The library
summary is the sole implementation; source regexes must not supply a parallel
language model.

Acceptance cases must cover raw/comment blocks, whitespace control, multiline
`liquid` tags, captures, assignments, nested loops, bracket access, Unicode
identifiers, filter arguments, and literal/dynamic partial names. A callback that
would fail if invoked should remain untouched during inspection. Compare source
and reused-template inspection and exercise the CLI through public behavior tests.

## Application reuse guidance

Add concise examples showing how an application retains parsed root and partial
templates, constructs ordered context values, and converts its own domain types
at the boundary. Explain cache invalidation by source/configuration changes and
per-invocation limits. An application-owned bounded cache can be illustrated
without introducing a cache product or shared state into the engine.

Keep automatic Encodable conversion, third-party JSON adapters, file/data loader
protocols, and new cache APIs in the later backlog. Ordered keys, numeric range,
date/binary policy and size limits need explicit contracts before adding them.

## Delivery sequence

| Step | Deliverable | Completion condition |
| --- | --- | --- |
| 1 | Scope and API design | Adopt the two-feature scope; specify filter values, arguments, failures and collisions, and inspection/JSON semantics. Review 1.0 source compatibility. |
| 2 | Custom filters | Implement the smallest typed public boundary, renderer dispatch, admission and failure handling; record adaptations and qualify the public consumer and concurrency cases. |
| 3 | Inspection and CLI | Implement one AST traversal, an immutable summary, and text/JSON CLI presentation; qualify syntax modes and cases that defeat source scanning. |
| 4 | Documentation and qualification | Publish examples and contracts; run every release lane, matched baseline measurements, and a clean archive rebuild at the candidate commit. |

No additional feature is a stretch goal for 1.1. If one of these designs requires
a broader runtime contract, defer that capability rather than importing its
upstream subsystem wholesale. Release timing follows the completed gates.

## Release gates

1. The 1.0 public consumer still compiles and behaves as documented. New APIs
   are additive; default rendering matches the preserved core fixtures and the
   pinned Shopify reference with no unexpected failures, exclusions or skips.
2. Custom-filter cases run in a separate extension suite. Use matched Ruby/Swift
   callbacks where semantics are comparable; label Swift host policies separately.
   Recovered errors, reference failures and supported-domain checks remain distinct.
3. Both public render paths, a public consumer and CLI behavior checks cover the
   new capabilities. Check shared templates and engine isolation under
   ThreadSanitizer and all relevant regressions under AddressSanitizer.
4. Run native, safety, reference, platforms, docs and performance lanes through
   `Scripts/ci.py`. Measure the five 1.0 workloads with an empty filter collection
   against 1.0.0 on the same toolchain and host, then add custom-filter and
   inspection workloads. Investigate regressions before claiming an improvement.
5. Keep macOS runtime and four simulator-SDK compile checks. Treat Linux runtime
   qualification and WASI as separate efforts; advertise support only after their
   actual gates exist and pass.
6. Retain licenses and source provenance in the extraction manifest when adapting
   code. Review DocC, README examples, the public inventory, reproducible source
   and documentation archives, checksums and exact-commit CI before publication.
   A 1.1 release still requires an explicit maintainer publication request.

## Later work

Custom tags need a separate parser/content/scope API design. Metrics and exact
provenance need separate observability contracts. Cache APIs and optimizer work
need measured demand beyond parsed-template reuse. Data formats, database/network
loading, DOCX and services belong in integrations that depend on Swift-Liquid.
Inheritance, macros, slots, input declarations and general function registries
remain separate language-scope decisions. None become implicit 1.1 features by
being present in RhoeLiquid.
