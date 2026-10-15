# Inspect partial dependencies

Build a bounded syntactic graph from an explicit root and supplied partial map.

## Overview

The 1.3 dependency API uses the existing AST inspection without evaluating
expressions, invoking callbacks or loading files:

```swift
let engine = LiquidEngine()
let source = "{% include 'card' %}{% include selected %}"
let partials = ["card.liquid": "{% include 'missing' %}{{ title | escape }}"]
let graph = try engine.inspectDependencies(template: source, templates: partials)
let parsed = try partials.mapValues { try LiquidTemplate($0) }
let reused = try engine.inspectDependencies(LiquidTemplate(source), templates: parsed)
assert(graph == reused)
```

``LiquidDependencyInspection`` retains reachable ``LiquidDependencyNode`` values,
``LiquidDependencyEdge`` requests and strongly connected cycle groups. Nodes keep
single-template summaries. ``LiquidDependencyNodeID`` separates the root from any
partial key. Missing references and dynamic includes are successful findings.
Every retained branch contributes; a graph does not predict execution or required
context. Unknown filters stay inspectable. Dynamic render names remain invalid.

All supplied sources, including unused partials, must pass cumulative source and
syntax-depth admission. Source bundles use the chosen parser mode; parsed bundles
keep their original parsing. Literal lookup tries the requested key, then the key
plus `.liquid`, using the renderer's Swift String dictionary equality. The graph
retains exact requested spelling and actual stored key spelling separately.

Nodes are root first and then UTF-8 key order; edges follow origin order and then
UTF-8 requested-name order. Repeated requests from one origin share an edge.
Cycles contain sorted members and are ordered by their first member, without
path enumeration or recursive traversal. Result equality uses exact UTF-8 names.

## Capacities and failure

``LiquidDependencyLimits`` defaults to 4,096 supplied templates including the root,
262,144 total supplied partial-key bytes, and 65,536 retained reachable literal
edges including missing requests. Empty and unused sources still spend admission
capacity. Template capacity must be positive; name/edge capacities may be zero.
Invalid profiles throw the existing invalid-value error; exhaustion uses
`dependencyTemplates`, `dependencyNameBytes`, or `dependencyEdges` limit names.

The engine's cumulative source and per-template syntax-depth limits also apply.
Render steps, output, loop and context capacities are not consumed. Cancellation
checks cover admission, AST traversal, expansion, cycle passes and assembly;
`CancellationError` is preserved. Failures return no partial result. The input,
engine, parsed templates and result types have checked Sendable conformance;
all mutable work belongs to the invocation.

## Command line and JSON

```sh
liquid analyze page.liquid --dependencies --partials ./partials --format json
```

Dependency mode alone accepts an optional explicit partial directory. The CLI
skips hidden files and child symlinks, checks containment, admits cumulative
source/count/name capacity, and rejects ambiguous dictionary keys. With no
directory, the partial map is empty. Ordinary analysis retains its existing schema.

Dependency JSON schema 1 has `kind: liquid.dependencies`, integer `schemaVersion`,
`nodes`, `edges`, `missingReferences`, `dynamicReferences` and `cycles`. Root IDs
are objects with `kind: root`; partial IDs have `kind: partial` and a string `name`.
Nodes contain `id` and the four existing inspection fields under `inspection`.
Edges contain `origin`, string `requestedName`, and string-or-null `resolvedName`.
All arrays are present even when empty. There are no added absolute input paths
or timestamps. Consumers ignore optional unknown fields and reject unknown kinds
or versions; changed required types or meanings need a new schema version.

Reports go to stdout and exit 0, including missing/dynamic/cycle findings.
Operational failures emit no graph and use the existing stderr/exit-1 convention.
The standalone schema qualification package uses published Swift-JSON's
JSONSchema validator for actual CLI reports and negative vectors. The Liquid
library and CLI retain their empty root dependency graph and deployment minimums.
