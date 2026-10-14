# Reuse templates in an application

Keep parsed roots and partials as application values. A `LiquidTemplate` is
immutable and Sendable; each render still creates fresh scopes, counters,
diagnostics and budgets. An engine's filter collection is immutable too.

```swift
let page = try LiquidTemplate("{% render 'card', article: article %}", syntaxMode: .strict2)
let partials = [
    "card": try LiquidTemplate("<h2>{{ article.title | escape }}</h2>", syntaxMode: .strict2)
]
let engine = LiquidEngine()

struct Article: Sendable {
    let title: String
    var liquidValue: LiquidValue { .object(["title": .string(title)]) }
}
let article = Article(title: "Swift & Liquid")
let context: LiquidObject = ["article": article.liquidValue, "published": true]
let html = try await engine.render(page, context: context, templates: partials)
// <h2>Swift &amp; Liquid</h2>
```

Object literals retain insertion order, including the `article`, `published`
context entries above. Convert domain types explicitly at the boundary: choose
how dates become strings/epochs, which numbers require exact string storage, how
optional values map to `.null`, and which fields are available to templates.
There is no implicit Encodable conversion or data-source lookup.

The [filter consumer](../Examples/FiltersConsumer) compiles this pattern with an
application filter, ordered context, and repeated rendering of one root/partial
bundle. The [inspection consumer](../Examples/InspectionConsumer) shows how the
same parsed template can support tooling without invoking filters.

## Invalidation and capacity

For a small fixed collection, retain one immutable root/partial bundle and replace
it when its sources change. If an application needs a cache, bound its entry count
and retained source bytes, choose eviction in the application, and synchronize
only the cache's mutation. Rendering shared template values needs no global lock.

A parsed-template cache key must distinguish exact source bytes, parser mode,
parse-limit profile, and library/parser version. Reparse when these inputs change.
Include partial names and each partial's source/configuration when caching an
assembled bundle; a root summary does not traverse or validate a dependency graph.
Do not key solely on a filename or assume a timestamp captures every content change.

Parsed templates retain no application filters. One parsed value can be rendered
with different engines, but engine filter configuration, strict-filter policy,
reference clock, context values and partial maps still affect output. Keep those
inputs separate from a parse cache. An output cache would need its own complete
key and invalidation policy and is outside the library contract.

Every invocation enforces its engine's finite source, input, rendering and filter
admission capacities. Parsed reuse does not replenish nested budgets or bypass
source admission. Reparse under the chosen limits when changing a bundle's parse
policy. Logical capacities do not establish a process-memory or wall-clock bound.
