# RhoeLiquid feature review

Swift-Liquid 1.2.0 ships scoped typed custom filters, AST inspection and opt-in
render metrics, including separate CLI JSON metrics. The adopted 1.3 scope
is bounded partial-dependency inspection over explicitly supplied templates,
with an opt-in CLI mode. Other remaining capabilities add language, shared state,
I/O or hosting policies that need independent scope decisions.

This review compares [Swift-Liquid 1.2.0](https://github.com/ThorFuchs/Swift-Liquid/tree/1.2.0)
at `8676da8059e71905632c233cffb438f8edbf51d2`
with the extraction source, [RhoeLiquid at `9e524926`](https://github.com/RhoePlatform/RhoeLiquid/tree/9e52492671bc31741932811fe689a86fed76be69).
The source repository's remote HEAD still matched that commit on 2026-10-15. Feature
names below describe the reviewed implementation; they do not transfer its
qualification or performance claims to Swift-Liquid.

The [adopted 1.3 roadmap](../Roadmap-1.3.md) records the adopted scope.
The adopted [1.2](../Roadmap-1.2.md) and [1.1](../Roadmap.md) roadmaps retain their
shipped scope and acceptance criteria. The maintainer adopted the 1.3 roadmap
on 2026-10-15; remaining extensions need independent scope decisions.

## Feature disposition after 1.2

| RhoeLiquid capability | Swift-Liquid disposition | Reason |
| --- | --- | --- |
| Registry-backed custom filters | Shipped in 1.1 with a typed, immutable configuration | `LiquidValue` callbacks, ordered arguments and explicit admission/failure semantics replace the `Any` boundary and mutable registration API. |
| Supplemental collection filters such as `group_by`, `sort_by`, `pluck`, `limit` and `offset` | Leave as application filters or later opt-in examples | A custom-filter API can support these without adding Rhoe filter names to the default Shopify surface. |
| Template analysis and manifests | Shipped a small AST summary in 1.1; adopt bounded dependency inspection for 1.3 | Follow literal references through caller-supplied partials; report missing/dynamic references and cycle groups without evaluating templates. |
| CLI `analyze` | Shipped in 1.1; adopt explicit dependency mode for 1.3 | Preserve ordinary analysis and its schema while presenting the new library result with explicit CLI file inputs. |
| Runtime custom tags and parser adapters | Defer to a separate API design | Parsing, nested content, scope mutation, lifecycle hooks, and budgets substantially widen the extension boundary. |
| AST cache, compiled templates, optimizer, renderer pooling | Reuse guide shipped in 1.1; defer runtime machinery | Public Sendable `LiquidTemplate` supports parse-once reuse. Eviction, identity, promotion and shared state need separate correctness and measurement work. Some optimizer/cache settings are archived compatibility shims. |
| Render metrics | Shipped in 1.2 as opt-in source/parsed APIs and a CLI JSON file | Snapshot invocation counters with a monotonic clock; ordinary calls collect no timing. Cache statistics, storage estimates and a parallel measured renderer remain excluded. |
| Provenance and interactive debugging | Defer to separate execution contracts | Exact source/output attribution, suspension, captured values and bounded session state go beyond aggregate metrics. |
| File-backed template loader | Keep file access in the CLI or host application | The library's explicit partial maps already support composition without ambient filesystem access. |
| JSON, CSV/TSV, Markdown, YAML, TOML, XML, SQLite, GraphQL loaders and data filters | Keep outside the core; consider future integration packages | Format dependencies, URL access, query execution, caches, and format-specific values require independent policies and qualification. Ordered JSON input is already available. |
| Automatic Encodable conversion and third-party value adapters | Keep explicit application mapping | Numeric range, key order, dates, binary values and admission need deliberate conversion contracts. |
| Inheritance, macros, imports, block calls, slots, fills, input contracts | Defer as a separate dialect decision | These belong to Rhoe's authoring language rather than the selected Shopify core contract. |
| HTTP service, job storage, auditing, service launcher | Keep in application integrations | Hosting and operational policy do not belong in the template runtime. |
| DOCX package, XML, ZIP, media and document pipelines | Keep in a separate document product | Document packaging and rendering have their own correctness and security contracts. |
| WASM wrapper and capability metadata | Defer to a platform qualification effort | A wrapper target does not establish Swift 6.4 WASI compilation or runtime compatibility. Linux runtime support also needs actual gates. |
| CLI batch, init and benchmark commands, shell completions and man page | Independent backlog | Batch discovery, scheduling and output policies are broader than metrics. The separate release benchmark package already supplies measured evidence. |
| Automatic HTML escaping configuration | Preserve explicit Liquid escaping | Changing escaping policy would change template output. Applications can use the standard `escape` and `escape_once` filters. |
| Pipeline tag and general function registries | Leave out | The upstream language manifest marks pipeline archived and general functions remain deferred. |

## Implementation findings

### The 1.1 additions replace upstream boundaries

Rhoe's [CustomFilter protocol](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/LiquidCore.swift)
is Sendable but accepts and returns `Any`, including arrays and dictionaries of
untyped arguments. Its [FilterRegistry](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidFilters/FilterRegistry.swift)
is a mutable actor with registration and removal operations. The engine snapshots
registered filters when rendering.

Swift-Liquid 1.1 removed the unused internal callback seam. Its
[typed public filter boundary](../CustomFilters.md) evaluates positional and
ordered named arguments, admits `LiquidValue` results against shared budgets,
defines explicit recoverable failures and keeps engine configuration immutable.
It does not expose Rhoe's protocol or registration actor.

Shopify's pinned [Environment implementation](https://github.com/Shopify/liquid/blob/4e39ae4cc3da73921923c0669e0fc84a66b2f696/lib/liquid/environment.rb)
provides scoped registration. The shipped Swift design follows that isolation
principle while retaining the existing value-type engine and invocation-owned
rendering state.

### Inspection retains one parser authority

Rhoe has two different analysis paths. The library's
[LiquidEngineAnalysis](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/RhoeLiquid/Platform/LiquidEngineAnalysis.swift)
traverses parsed templates but also coordinates file loading, authoring contracts,
macros, and an unchecked wrapper around an `Any` context. The CLI's
[AnalyzeCommand](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCLICore/Commands/AnalyzeCommand.swift)
independently scans source with regexes and derives its nesting estimate from tag
counts.

Swift-Liquid 1.1 [inspection](../Inspection.md) traverses the standard parser's
internal AST and returns immutable summaries. Raw text and comments do not
introduce false dependencies. Variable references cannot certify required inputs
or the templates that a dynamic name might select.

### Bounded dependency inspection is the adopted 1.3 feature

Rhoe's `buildManifest` and AST walker collect a direct `referencedTemplates` set.
Its broader analysis also resolves files and validates macro/input contracts.
Those paths are not a bounded Shopify-core graph over host-supplied partials.
The adopted 1.3 scope extends Swift-Liquid's own inspection with that smaller model;
it does not import the upstream analysis subsystem or its heuristic scores.

The existing [partial resolver](../../Sources/Liquid/Support/TemplateLoader.swift)
looks for a supplied name, then that name plus `.liquid`. A graph must retain that
lookup behavior, distinguish requested spelling from the actual map key, and
keep the root identity separate from every partial name. Existing String-keyed
maps cannot hold canonically equivalent keys as separate entries; exact-spelling
inspection lists do not create a different rendering name-resolution contract.

Follow reachable literal references after admitting and inspecting the supplied
bundle. Report missing names and dynamic includes as observations, and report
cycles as finite strongly connected groups. Conditional branches and unresolved
dynamic names prevent a static report from certifying execution or renderability.
Count supplied entries, name bytes and edges, check cancellation and avoid
enumerating every path or simple cycle. The [roadmap](../Roadmap-1.3.md) makes
those contracts, the separate CLI schema and acceptance cases explicit.

### The 1.2 metrics reuse invocation state

Rhoe's [renderWithMetrics](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/RhoeLiquid/RhoeLiquid.swift)
has its own cache/parse/render orchestration. It times phases with
`Date().timeIntervalSinceReferenceDate`, snapshots registries and cache statistics,
and calculates AST and string-storage observations. The
[TemplateMetricsAnalyzer](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/Performance/TemplateMetricsAnalyzer.swift)
walks tokens and AST values to collect `InlineString` observations. Its
[metrics tests](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Tests/RhoeLiquidTests/PerformanceMetricsTests.swift)
check node counts, observed string storage and cached renders. These observations
are specific to upstream storage/caching, not process allocation accounting for
Swift-Liquid's native strings.

Swift-Liquid's [engine](../../Sources/Liquid/LiquidEngine.swift) creates a renderer
per invocation, admits typed values and checks final output. Its
[RuntimeBudget](../../Sources/Liquid/LiquidLimits.swift) already tracks steps,
iterations and admitted values across nested work. The shipped 1.2 implementation
snapshots those counters after final output admission and measures monotonic
elapsed time through the same render path, without importing upstream metrics
code. Source and parsed throwing/diagnostic entry points retain error identity
and invocation ownership. The [metrics contract](../Metrics.md) and
[1.2.0 release notes](../Releases/1.2.0.md) define clocks, timing boundaries,
logical counts, recovery and CLI schema 1. The remaining upstream cache/storage
observations do not become additional metrics commitments for 1.3.

### Custom tags widen the host boundary

Rhoe's [CustomTag](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidTags/CustomTag.swift)
supports parse/execute methods, simple/block/conditional/loop shapes and lifecycle
hooks. Its execution context exposes scope mutation, filter application, body
nodes and data loading. Parsing/execution contexts use unchecked Sendable wrappers
around `Any` values and callbacks; unsupported parameter values may stringify
during conversion. The
[parser descriptor](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidParser/CustomTagDescriptor.swift)
recognizes names and closing tags, while the
[actor registry](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidTags/TagRegistry.swift)
owns registration and lifecycle.

A Swift-Liquid design needs typed values, checked Sendable boundaries, parsed
configuration identity, nested-content/scope semantics, shared budgets and
cancellation. The 1.1 filter scope does not authorize those runtime controls or
additional grammar.

### Cache and provenance claims need separate contracts

The upstream [TemplateCache](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/Cache/TemplateCache.swift)
owns AST entries, LRU state, TTLs, estimated sizes, and statistics. Swift-Liquid
already provides reusable immutable templates without that shared policy. A
future cache would need explicit ownership and keys covering source bytes,
parser mode, parse limits, and any parse-affecting configuration. Cached templates
must still pass each invocation's admission checks.

[CompiledTemplateCache](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidRenderer/CompiledTemplateCache.swift)
and [ASTOptimizer](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidRenderer/ASTOptimizer.swift)
retain compatibility settings around the live compiler/optimized-renderer path.
Compression, dependency tracking and numeric optimizer controls include archived,
deprecated settings. Copying the whole surface would import historical API
obligations. Optimization also needs parity for errors, filter order, reference
clocks, budgets and cancellation, measured beyond parsed-template reuse.

The upstream [ProvenanceBuilder](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/Provenance/ProvenanceBuilder.swift)
correlates source constructs with output text after rendering. Exact provenance
through repeated values, loops, captures, whitespace control and partials needs
renderer instrumentation and a defined UTF-8 range model. It should not be
presented as exact source mapping by copying that implementation.

[DebugContext](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/Debug/DebugContext.swift)
is an actor owning breakpoints, watches, traces, call frames and execution state.
[DebugConfiguration](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/Debug/DebugConfiguration.swift)
adds handlers and stepping. A future debugger needs bounded invocation storage,
captured-value/privacy policy and cancellation while suspended. Aggregate counts
and durations do not supply that contract.

### Integration boundaries include more than package dependencies

Rhoe's [package manifest](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Package.swift)
declares Yams, Hummingbird, Swift Collections, Swift Log, Argument Parser and a
DocC plugin. Some other integrations use Foundation directly. The
[data loader registry](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/DataSource/DataSource.swift)
also owns URL dispatch and caching, and exposes a global registry instance.
The [template loader](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidExtensions/TemplateLoader.swift)
adds filesystem resolution and parsing. The
[batch CLI](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCLICore/Commands/BatchCommand.swift)
adds discovery, context lookup, concurrency and output-file policy. Dependency-free
code can still introduce ambient I/O or application policy.

Future integration packages should depend on Swift-Liquid. Swift-Liquid should
retain an empty package dependency list, one public library, one executable,
and host-owned I/O. The [1.3 roadmap](../Roadmap-1.3.md) adopts one tooling feature
and its acceptance gates; no other upstream subsystem is a stretch goal.
