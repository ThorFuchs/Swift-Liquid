# RhoeLiquid feature review

Swift-Liquid 1.1.0 ships scoped typed custom filters and AST inspection shared by
the library and CLI. The strongest remaining candidate for 1.2 is opt-in render
metrics, reduced to elapsed durations and existing invocation budget consumption.
Most other upstream features add language, storage, I/O or hosting policies that
need independent scope decisions.

This review compares [Swift-Liquid 1.1.0](https://github.com/ThorFuchs/Swift-Liquid/tree/1.1.0)
at `1107ec865b9ae7ed35e1245386ba882db3abd93d`
with the extraction source, [RhoeLiquid at `9e524926`](https://github.com/RhoePlatform/RhoeLiquid/tree/9e52492671bc31741932811fe689a86fed76be69).
The source repository's remote HEAD still matched that commit on 2026-10-15. Feature
names below describe the reviewed implementation; they do not transfer its
qualification or performance claims to Swift-Liquid.

The maintainer adopted the [1.2 roadmap](../Roadmap-1.2.md) on 2026-10-15; its
[metrics contract](../Metrics.md) defines the development API. The
[adopted 1.1 roadmap](../Roadmap.md) records the previous scope decision.

## Feature disposition after 1.1

| RhoeLiquid capability | Swift-Liquid disposition | Reason |
| --- | --- | --- |
| Registry-backed custom filters | Shipped in 1.1 with a typed, immutable configuration | `LiquidValue` callbacks, ordered arguments and explicit admission/failure semantics replace the `Any` boundary and mutable registration API. |
| Supplemental collection filters such as `group_by`, `sort_by`, `pluck`, `limit` and `offset` | Leave as application filters or later opt-in examples | A custom-filter API can support these without adding Rhoe filter names to the default Shopify surface. |
| Template analysis and manifests | Shipped a small AST-derived summary in 1.1; defer recursive graphs | Syntactic references support tooling without data loading or exposing the AST. Dynamic partials and local reads do not certify dependencies or required inputs. |
| CLI `analyze` | Shipped in 1.1 using the library inspection | One parser authority replaces regex counts and heuristic complexity labels. |
| Runtime custom tags and parser adapters | Defer to a separate API design | Parsing, nested content, scope mutation, lifecycle hooks, and budgets substantially widen the extension boundary. |
| AST cache, compiled templates, optimizer, renderer pooling | Reuse guide shipped in 1.1; defer runtime machinery | Public Sendable `LiquidTemplate` supports parse-once reuse. Eviction, identity, promotion and shared state need separate correctness and measurement work. Some optimizer/cache settings are archived compatibility shims. |
| Render metrics | Adopted for 1.2 development as a narrow library API and CLI JSON file | Reuse invocation counters and a monotonic clock; exclude cache statistics, storage estimates and a parallel measured renderer. |
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
or the templates that a dynamic name might select. Recursive partial graphs need
explicit input maps, dynamic-reference semantics, cycles and graph limits.

### Metrics can reuse invocation state

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
iterations and admitted values across nested work. The adopted 1.2 design
snapshots those counters and measures elapsed time through the same render path,
without importing upstream metrics code. The [metrics contract](../Metrics.md)
defines clocks, source/reused timing, recovery and failure semantics.

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
and host-owned I/O. The [1.2 roadmap](../Roadmap-1.2.md) defines the adopted work
and its acceptance gates.
