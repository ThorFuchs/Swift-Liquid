# RhoeLiquid feature review

The strongest candidates for Swift-Liquid 1.1 are scoped custom filters and
read-only template inspection. Both fit the existing `Liquid` library and
`liquid` executable without package dependencies. The remaining RhoeLiquid
features generally introduce language extensions, shared state, I/O, or separate
application products.

This review compares [Swift-Liquid 1.0.0](https://github.com/ThorFuchs/Swift-Liquid/tree/1.0.0)
with the extraction source, [RhoeLiquid at `9e524926`](https://github.com/RhoePlatform/RhoeLiquid/tree/9e52492671bc31741932811fe689a86fed76be69).
The source repository's HEAD still matched that commit on 2026-10-14. Feature
names below describe the reviewed implementation; they do not transfer its
qualification or performance claims to Swift-Liquid.

## Feature disposition

| RhoeLiquid capability | Swift-Liquid disposition | Reason |
| --- | --- | --- |
| Registry-backed custom filters | Propose for 1.1 with a typed, immutable configuration | Useful host integration through existing Liquid filter syntax; replace the `Any` boundary and mutable registration API. |
| Supplemental collection filters such as `group_by`, `sort_by`, `pluck`, `limit` and `offset` | Leave as application filters or later opt-in examples | A custom-filter API can support these without adding Rhoe filter names to the default Shopify surface. |
| Template analysis and manifests | Propose a small AST-derived summary for 1.1 | Useful for tooling without rendering, data loading, or exposing the internal AST. |
| CLI `analyze` | Propose for 1.1 using the same library inspection | Reuse parser semantics; replace regex counts and heuristic complexity labels. |
| Runtime custom tags and parser adapters | Defer to a separate API design | Parsing, nested content, scope mutation, lifecycle hooks, and budgets substantially widen the extension boundary. |
| AST cache, compiled templates, optimizer, renderer pooling | Keep application reuse recipes in 1.1; defer new runtime machinery | Public Sendable `LiquidTemplate` already supports parse-once reuse. Shared caches and unsafe representations need separate correctness and measurement work. |
| Render metrics, provenance, interactive debugging | Defer | Timing, allocation accounting, exact output provenance, and debugger state are distinct contracts. Existing recovered diagnostics already address runtime error reporting. |
| File-backed template loader | Keep file access in the CLI or host application | The library's explicit partial maps already support composition without ambient filesystem access. |
| JSON, CSV/TSV, Markdown, YAML, TOML, XML, SQLite, GraphQL loaders and data filters | Keep outside the core; consider future integration packages | Format dependencies, URL access, query execution, caches, and format-specific values require independent policies and qualification. Ordered JSON input is already available. |
| Inheritance, macros, imports, block calls, slots, fills, input contracts | Defer as a separate dialect decision | These belong to Rhoe's authoring language rather than the selected Shopify core contract. |
| HTTP service, job storage, auditing, service launcher | Keep in application integrations | Hosting and operational policy do not belong in the template runtime. |
| DOCX package, XML, ZIP, media and document pipelines | Keep in a separate document product | Document packaging and rendering have their own correctness and security contracts. |
| WASM wrapper and capability metadata | Defer to a platform qualification effort | A wrapper target does not establish Swift 6.4 WASI compilation or runtime compatibility. |
| CLI batch, init and benchmark commands, shell completions and man page | Defer broader commands; revisit documentation conveniences independently | Keep 1.1 concentrated on rendering, validation and inspection. The separate release benchmark package already supplies measured performance evidence. |
| Automatic HTML escaping configuration | Preserve explicit Liquid escaping | Changing escaping policy would change template output. Applications can use the standard `escape` and `escape_once` filters. |
| Pipeline tag and general function registries | Leave out | The upstream language manifest marks pipeline archived and general functions remain deferred. |

## Implementation findings

### Filters need a public value boundary

Rhoe's [CustomFilter protocol](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/LiquidCore.swift)
is Sendable but accepts and returns `Any`, including arrays and dictionaries of
untyped arguments. Its [FilterRegistry](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidFilters/FilterRegistry.swift)
is a mutable actor with registration and removal operations. The engine snapshots
registered filters when rendering.

Swift-Liquid retains an internal callback seam, but it is not a public extension
API. The current fallback passes an empty named-argument dictionary. A public
API therefore needs evaluated positional and named arguments, admitted
`LiquidValue` results, a defined error contract, and immutable engine
configuration. Exposing the retained internal protocol would miss those requirements.

Shopify's pinned [Environment implementation](https://github.com/Shopify/liquid/blob/4e39ae4cc3da73921923c0669e0fc84a66b2f696/lib/liquid/environment.rb)
provides scoped registration. The proposed Swift design follows that isolation
principle while retaining the existing value-type engine and invocation-owned
rendering state.

### Inspection needs one parser authority

Rhoe has two different analysis paths. The library's
[LiquidEngineAnalysis](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/RhoeLiquid/Platform/LiquidEngineAnalysis.swift)
traverses parsed templates but also coordinates file loading, authoring contracts,
macros, and an unchecked wrapper around an `Any` context. The CLI's
[AnalyzeCommand](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCLICore/Commands/AnalyzeCommand.swift)
independently scans source with regexes and derives its nesting estimate from tag
counts.

A focused inspection feature should traverse the standard parser's internal AST
and return immutable summary values. Raw text and comments must not introduce
false dependencies. Variable references cannot certify required inputs or the
templates that a dynamic name might select.

### Cache and provenance claims need separate contracts

The upstream [TemplateCache](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/Cache/TemplateCache.swift)
owns AST entries, LRU state, TTLs, estimated sizes, and statistics. Swift-Liquid
already provides reusable immutable templates without that shared policy. A
future cache would need explicit ownership and keys covering source bytes,
parser mode, parse limits, and any parse-affecting configuration. Cached templates
must still pass each invocation's admission checks.

The upstream [ProvenanceBuilder](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/Provenance/ProvenanceBuilder.swift)
correlates source constructs with output text after rendering. Exact provenance
through repeated values, loops, captures, whitespace control and partials needs
renderer instrumentation and a defined UTF-8 range model. It should not be
presented as exact source mapping by copying that implementation.

### Integration boundaries include more than package dependencies

Rhoe's [package manifest](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Package.swift)
declares Yams, Hummingbird, Swift Collections, Swift Log, Argument Parser and a
DocC plugin. Some other integrations use Foundation directly. The
[data loader registry](https://github.com/RhoePlatform/RhoeLiquid/blob/9e52492671bc31741932811fe689a86fed76be69/Sources/LiquidCore/DataSource/DataSource.swift)
also owns URL dispatch and caching, and exposes a global registry instance.

Future integration packages should depend on Swift-Liquid. Swift-Liquid should
retain an empty package dependency list, one public library, one executable,
and host-owned I/O. The [1.1 roadmap](../Roadmap.md) defines the proposed work and
its acceptance gates.
