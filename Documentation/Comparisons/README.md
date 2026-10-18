# Liquid APIs: a task-oriented crosswalk

Swift-Liquid 1.3 provides immutable, checked-Sendable engines and parsed templates,
async rendering, typed inputs, explicit partial maps and finite invocation-owned
budgets. This guide maps familiar peer concepts to those contracts. A similar
method name does not establish identical language behavior: the broader
[LQ1 conformance gate currently fails](../LQ1/README.md).

## Find the equivalent entry point

| Engine and audited source | Configure / parse once | Render and extend | Difference to plan for |
| --- | --- | --- | --- |
| [Ruby Liquid 5.14.0](https://github.com/Shopify/liquid/blob/4e39ae4cc3da73921923c0669e0fc84a66b2f696/lib/liquid/environment.rb) | `Environment.build`, `Template.parse` with environment/options | `Template#render` or `render!`; environment filter modules and tag classes | Ruby context/registers, Drops, arbitrary integers and mutable template error state have no general Swift value-model equivalent. `render!` is the closer raising policy. |
| [LiquidJS 10.30.0](https://github.com/harttle/liquidjs/blob/920166e3f5bf14412fad2dc4c6be687ecb5f7f60/src/liquid.ts) | `new Liquid(options)`, `parse` | async `render`, `registerFilter`, `registerTag`; sync and Node stream alternatives | JavaScript object/Drop access, filesystem adapters and mutable registries are separate hosting choices. Swift exposes neither sync rendering nor a stream sink. |
| [Python Liquid 2.3.4](https://github.com/jg-rp/liquid/blob/0e1b4e24312364085c72875179a98a80ce35853a/liquid/environment.py) | `Environment`, `from_string` → `BoundTemplate` | `render` / `render_async`; `add_filter`, `add_tag` | Configurable Undefined types, loaders and optional HTML autoescape are peer policies. They do not change Swift's default missing-value behavior or explicit escaping. |
| [Rust Liquid 0.26.11](https://github.com/cobalt-org/liquid-rust/blob/55768356999c35e50fbc88885e407ddd1f941fbe/src/parser.rs) | `ParserBuilder::with_stdlib().build()`, `Parser::parse` | `Template::render` / `render_to`; builder filter/tag/block parsers | `ObjectView`/`ValueView` and partial compilers are explicit Rust extension contracts. Swift has typed values and engine-scoped filters, with no tag/block plugin API. |
| [Fluid development snapshot](https://github.com/sebastienros/fluid/blob/cc036bfc7d9dcd2418fefa4bb07d7913ce3eb072/Fluid/FluidParser.cs) | `FluidParser`, `TryParse`; `TemplateOptions` built from `TemplateOptionsBuilder` | `IFluidTemplate.RenderAsync`, sync extension; options filters and parser tag/block registration | This pin documents Fluid **3 under development**, not stable 2.41.0. Its immutable options, async provider/output and member-access APIs must not be attributed to stable 2.x from this evidence. |
| Swift-Liquid 1.3 contract | `LiquidEngine`, `LiquidTemplate` | `try await engine.render(parsed, context:templates:)`; `LiquidFilter` | Retain the engine/template in the application; pass a fresh typed context per call. No global registry or implicit loading. |

## Move an application task

| Task | Swift-Liquid contract and limits |
| --- | --- |
| Parse once, render repeatedly | Construct `LiquidTemplate(source, syntaxMode:)` once, then await the engine's parsed-template render overload. Engines/templates are Sendable; counters, variables, diagnostics and budgets are per invocation. Default parser mode stays `lax`. |
| Add an application filter | Construct a typed, async `LiquidFilter` and supply it when creating an immutable engine. Standard names/aliases are protected. [Arguments and failures](../CustomFilters.md) remain typed; there is no custom tag/block registration API. |
| Resolve partials | Pass `[String: String]` or `[String: LiquidTemplate]` explicitly. Ruby `Environment.file_system`, LiquidJS filesystem/root options, Python loaders, Rust partial compilers and Fluid providers serve a different hosting boundary. No library filesystem/network loader is inferred. |
| Expose application data | Map data into `LiquidValue`/`LiquidObject`. Only the enum's declared value domain enters rendering. There is no arbitrary native-model member discovery, Ruby Drop bridge or CLR-style member-access registry. |
| Handle failure | Raising render throws Liquid errors and operational failures. Explicit `renderWithDiagnostics` returns recovered output **and** diagnostics; nonempty diagnostics are not error-free rendering. Parser lax/strict/strict2 and runtime raising/recovery are independent axes. [Error contract](../Errors.md). |
| Validate template inputs | Current inspection reports syntactic variable roots, including local reads and retained branches. It is not a required-input schema. No strictVariables option is currently exposed. Peer strict/undefined policies require a separate semantic decision, not a parser-mode setting. |
| Inspect source | `inspect` traverses the AST without evaluation. `inspectDependencies` examines an explicit bundle and reports literal/dynamic references, missing names and cycles. LiquidJS analysis helpers, Python `BoundTemplate.analyze` and Fluid AST visitors have different result models; no structural equivalence is claimed. |
| Observe work | Opt-in `renderWithMetrics` reports durations and charged logical budgets. Quotas are not RSS or wall-clock guarantees. Peer profiling/limit units are not interchangeable. LQ1 performs no competitive timing. |
| Deliver output | The public render result is a complete String; no synchronous or streaming render API. Streaming adapters need cancellation, backpressure and output-completion contracts before adoption. |
| Insert untrusted text into HTML | Use `escape` or `escape_once` for the intended HTML context. Output is not autoescaped; filters are not a universal sanitizer for URL, JavaScript or CSS contexts. Ruby/Python/LiquidJS/Fluid encoding options do not establish a shared default security policy. |
| Deploy Swift code | Tools/compiler 6.4+, language mode 6; macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1 minima. Native qualification is macOS 27, with four simulator compilation gates. Device execution, Linux and WASI runtime support are not established by this wave. |

## Read the evidence grade

[FEATURE_MATRIX.json](FEATURE_MATRIX.json) attaches a grade and source to each
claim: **source-confirmed** means inspected pinned implementation;
**upstream-documentation** means an upstream documentation claim;
**native-test-confirmed** means exercised in this Swift qualification;
**not-established** means no sufficient evidence; **explicitly-deferred** means
an intentional scope decision. Peer runtimes were not executed here. The matrix
is an API/hosting comparison, not a conformance score or a ranking. Inheritance,
macros, theme objects, loaders and other peer extras are not automatically
Shopify open-source core omissions.

Additional pinned sources:
[Ruby Template](https://github.com/Shopify/liquid/blob/4e39ae4cc3da73921923c0669e0fc84a66b2f696/lib/liquid/template.rb),
[LiquidJS options](https://github.com/harttle/liquidjs/blob/920166e3f5bf14412fad2dc4c6be687ecb5f7f60/src/liquid-options.ts),
[Python BoundTemplate](https://github.com/jg-rp/liquid/blob/0e1b4e24312364085c72875179a98a80ce35853a/liquid/template.py),
[Python Undefined](https://github.com/jg-rp/liquid/blob/0e1b4e24312364085c72875179a98a80ce35853a/liquid/undefined.py),
[Rust Template](https://github.com/cobalt-org/liquid-rust/blob/55768356999c35e50fbc88885e407ddd1f941fbe/src/template.rs),
[Fluid options](https://github.com/sebastienros/fluid/blob/cc036bfc7d9dcd2418fefa4bb07d7913ce3eb072/Fluid/TemplateOptions.cs),
[Fluid version notice](https://github.com/sebastienros/fluid/blob/cc036bfc7d9dcd2418fefa4bb07d7913ce3eb072/README.md).
