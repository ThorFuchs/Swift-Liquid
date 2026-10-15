# Bounded partial-dependency inspection

The Swift-Liquid 1.3 candidate adds opt-in inspection of an explicit template bundle.
The 1.0–1.2 rendering, filters, single-template inspection and metrics APIs keep
their behavior. No dependency, context, callback or I/O is added to the core.

```swift
import Liquid

let engine = LiquidEngine()
let source = "{% include 'card' %}{% include selected %}"
let partials = ["card.liquid": "{{ title | escape }}{% include 'missing' %}"]
let graph = try engine.inspectDependencies(
    template: source, templates: partials, syntaxMode: .strict2
)
// Nodes: root, partial("card.liquid").
// Literal edges: root requests "card" -> "card.liquid";
// partial("card.liquid") requests "missing" -> nil.
// Dynamic references: root. No cycles.

let root = try LiquidTemplate(source, syntaxMode: .strict2)
let parsed = try partials.mapValues { try LiquidTemplate($0, syntaxMode: .strict2) }
let reused = try engine.inspectDependencies(root, templates: parsed)
assert(graph == reused)
```

Both methods return an immutable, checked Sendable `LiquidDependencyInspection`.
The source overload applies one selected parser mode to all sources; the parsed
overload retains each template's original parse without reparsing. The AST stays
private. Every supplied template is admitted and inspected, including unused
partials. An unused syntax error fails the source operation; a previously parsed
unused template must satisfy the current source and syntax-depth limits.

## Findings and identity

`nodes` contains the root first, followed by partials reachable through literal
references in ascending UTF-8 key order. Each `LiquidDependencyNode` has an `id`
and the existing `LiquidTemplateInspection` summary. `LiquidDependencyNodeID.root`
is distinct from every `.partial(String)`, even a supplied key named `root`.
Unused supplied templates are absent from the result.

`edges` contains one `LiquidDependencyEdge` for each distinct literal spelling
from a reachable origin. It retains `origin`, `requestedName`, and optional
`resolvedName`. Edges follow node order, then ascending UTF-8 request order.
Repeated identical requests in one template share an edge; two aliases resolving
to the same partial remain distinct requests. These are not occurrence counts.

Lookup follows the renderer: first the requested key, then the requested key plus
`.liquid`. There is no relative-path or filesystem normalization. The `[String: …]`
input dictionary uses Swift's canonical-equivalence equality, so it cannot store
canonically equivalent keys as separate entries. A request may match a differently
spelled supplied key. The edge keeps both exact spellings, and the node uses the
actual stored dictionary key. Names, identities, edge equality and result ordering
retain exact UTF-8 spelling. Permuting the same accepted entries yields the same
result; constructing a map that collapses distinct spellings is caller preparation.

`missingReferences` selects edges with a nil resolved name. `dynamicReferences`
selects nodes whose inspection reports a dynamic include. No expression is
evaluated to invent an edge for a dynamic name. Dynamic `render` names retain
the existing syntax rejection. `cycles` contains strongly connected groups with
more than one member, plus singleton self-loops. Members follow node order and
groups are ordered by their first member. Shared dependencies expand once, and
cycle detection uses iterative worklists rather than recursion or path enumeration.

Missing references, cycles and dynamic includes are successful findings. All
retained branches and loops contribute, even if they would never execute. Raw,
comment and discarded parser tokens do not. A report does not prove which
partials execute, that context inputs are sufficient, or that rendering succeeds.
There is no validity verdict or automatic rejection policy.

## Capacities, failures and cancellation

`LiquidDependencyLimits` supplies three independent finite capacities:

| Field | Default | Charging rule | Failure name |
| --- | ---: | --- | --- |
| `templates` | 4,096 | Root plus every supplied map entry, including empty and unused sources | `dependencyTemplates` |
| `nameBytes` | 262,144 | Sum of UTF-8 bytes of actual supplied partial keys, including unused keys; root has no name | `dependencyNameBytes` |
| `edges` | 65,536 | Each unique literal request from a reachable origin, including missing requests; alias requests charge separately | `dependencyEdges` |

The template capacity must be positive; name and edge capacities may be zero.
Negative values are invalid. Each operation validates this profile and the
engine's `LiquidLimits`. Counts are admitted with checked comparisons and
subtraction before graph storage; empty source cannot bypass template capacity.
Literal spelling storage is also bounded by admitted source. The entire bundle
shares the engine's `sourceBytes` capacity; every AST must pass `nestingDepth`.
Graph chain length and cycles do not spend syntax depth. `renderSteps`,
`loopIterations`, `contextValues` and `outputBytes` are not consumed or reset.
Capacities are logical bounds, not RSS, wall-clock or allocation promises.

Invalid profiles throw `LiquidError.invalidValue`; exceeded capacities throw
`LiquidError.limitExceeded` with the names above or existing `sourceBytes` /
`nestingDepth` names. Syntax errors retain their existing identities. When several
inputs are invalid, which admission error is encountered first is unspecified.
Cancellation is checked at admission, AST traversal, graph expansion, SCC passes
and result assembly and remains `CancellationError`. Failure returns no partial
graph. Engines and parsed templates retain no mutable analysis state.

## CLI and dependency-report JSON schema 1

```sh
liquid analyze page.liquid --dependencies --partials ./partials --format json
printf "{% include 'card' %}" | liquid analyze - --dependencies
```

Only `analyze --dependencies` accepts a partial directory. Omitting it supplies an
empty map. `--syntax-mode` and `--format text|json` retain their meaning; context,
filters, metrics and output-file options are rejected. Without `--dependencies`,
ordinary analysis retains its original accepted options and schema 1.

The CLI discovers regular `.liquid` files recursively in the explicit directory,
skipping hidden entries and child symlinks. Keys are relative paths with the
final `.liquid` suffix removed. Containment is checked before reading a partial.
The root and all partials share the default source capacity. Template count and
name bytes are admitted before retaining each partial; parsing follows complete
bundle admission. Canonically equivalent discovered keys cause an error instead
of replacement. Filesystem normalization may prevent such paths from coexisting;
the library's dictionary behavior remains as described above. Discovery errors
are failures, not a successful empty map. No implicit partial search is performed.

JSON is one UTF-8 object and a newline. Every field below is required:

| Field | Type and meaning |
| --- | --- |
| `kind` | String `liquid.dependencies`, distinct from single-template inspection |
| `schemaVersion` | Integer 1 |
| `nodes` | Ordered array of `{ "id": ID, "inspection": SUMMARY }` |
| `edges` | Ordered array of `{ "origin": ID, "requestedName": STRING, "resolvedName": STRING_OR_NULL }` |
| `missingReferences` | Ordered subset of `edges` with null `resolvedName` |
| `dynamicReferences` | Ordered IDs of nodes containing dynamic includes |
| `cycles` | Ordered arrays of IDs for the cycle groups |

An ID is `{ "kind": "root" }` or `{ "kind": "partial", "name": STRING }`.
A summary has the existing four fields `variableRoots`, `filterNames`,
`literalPartialNames` (string arrays) and `hasDynamicPartials` (boolean), without
an embedded schema version. Empty arrays are always arrays; unresolved names
are explicitly null. Reports contain supplied names but no added absolute input
paths or timestamps. Object keys are sorted on emission; formatting and escape
choices are not a consumer contract.

The machine-readable [Draft 2020-12 schema](Schemas/dependencies-v1.json) specifies
shape and discriminators. Graph relationships, ordering and exact-spelling
semantics are verified by API/CLI tests rather than inferred from schema validity.
Consumers ignore unknown optional fields and reject unknown report kinds or
schema versions. Changes to required fields, types or meanings require a new
version. Text uses labeled nodes/edges and JSON notation for arbitrary names;
text labels and whitespace remain presentation details.

Successful reports go to stdout and exit 0, including missing references, dynamic
includes and cycles. Usage, syntax, input, capacity and cancellation failures emit
no report, write a `liquid:` diagnostic to stderr and exit 1.

## Swift-JSON integration and qualification

The standalone [schema qualification package](../Tools/SchemaQualification) uses
the published [Swift-JSON 1.3.0](https://github.com/ThorFuchs/Swift-JSON/releases/tag/1.3.0)
`JSON` and `JSONSchema` products to compile the report schema offline and validate
actual CLI output plus negative shape/version vectors. It does not implement a
second schema evaluator. Operational compilation/evaluation errors propagate as
failures, separate from completed negative verdicts.

This tooling package requires macOS 27 (Swift-JSON's declared minimum); it does
not change Liquid's deployment minimums, products or empty dependency graph.
It qualifies the JSON report contract, not a required-context schema or schema-
based inference of Liquid execution. The separate [public consumer](../Examples/DependencyConsumer)
exercises both Liquid entry points and Sendable results. Run the affected gates
through `python3 -B Scripts/ci.py --lane native` and `--lane docs`; the safety
lane includes mixed graph/render/metrics concurrency. Graph evidence is separate
from pinned Shopify rendering fixtures and counts.
