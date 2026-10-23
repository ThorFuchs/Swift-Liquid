# Exact registry dependency inspection

Inspect an explicit exact-name registry through
``LiquidEngine/inspectDependencies(template:registry:syntaxMode:analysisLimits:)``
or ``LiquidEngine/inspectDependencies(_:registry:syntaxMode:analysisLimits:)``.
Both methods require the registry and return ``LiquidDependencyInspection``.

```swift
let registry = try LiquidTemplateRegistry([
    .init("é", .raw("A")), .init("e\u{301}", .raw("B"))
])
let graph = try LiquidEngine().inspectDependencies(
    template: "{% include 'é' %}{% include 'e\u{301}' %}", registry: registry)
```

Root plus every entry is admitted, parsed or revalidated before findings,
including unused sources. Parsed inputs retain their AST/mode; `syntaxMode`
applies only to raw content. Registry admission and graph count/name/edge limits
are separate ledgers. Capacity, syntax and cancellation errors return no partial
graph. Cancellation is cooperative; logical quotas are not process-memory bounds.

The shared prepared AST table uses declaration indexes. Output rank is root then
reachable stored names in UTF-8 order. Each literal selection uses the same exact
resolver as rendering, preserving requested/stored spelling and suffix priority.
Edges and iterative SCC groups have deterministic rank order. Canonical siblings
remain separate. Old dictionary methods retain their existing String identity.

Literal first-candidate runtime selection agrees with graph selection. Findings
also include unexecuted branches; dynamic includes and context-string retries
are not predicted. No values, filters, callbacks, context or I/O are evaluated.
Opaque names are not paths or authorization. CLI/Vapor migration, release and
later conformance gates remain separate owner decisions.
