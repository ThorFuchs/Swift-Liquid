# Exact registry dependency inspection

The local U3 checkpoint adds two required-`registry:` overloads of
`LiquidEngine.inspectDependencies`. They return the existing immutable
`LiquidDependencyInspection`; they share U2's prepared AST table and U1's exact
UTF-8 resolver. Existing `templates:` graph and render calls keep canonical Swift
String lookup. The CLI still uses its existing dictionary API. No release or
Vapor dependency update follows from this checkpoint.

```swift
import Liquid

let registry = try LiquidTemplateRegistry([
    .init("é", .raw("A")),
    .init("e\u{301}", .parsed(try LiquidTemplate("B")))
])
let source = "{% include 'é' %}{% render 'e\u{301}' %}"
let engine = LiquidEngine()
let graph = try engine.inspectDependencies(template: source, registry: registry)
let reused = try engine.inspectDependencies(
    LiquidTemplate(source), registry: registry, syntaxMode: .strict2)
assert(graph == reused)
// Nodes: root, partial("e\u{301}"), partial("é"), in UTF-8 order.
// Two separate literal edges retain their requested and stored spellings.
```

The parsed-root method retains its AST and parser mode. `syntaxMode` applies only
to raw registry entries under that root. Both methods require `registry`, keeping
the defaults and overload resolution of existing calls unambiguous.

## Whole-bundle admission and error order

Each invocation checks cancellation, validates `LiquidLimits`, validates
`LiquidDependencyLimits`, then requires `registry.count < analysisLimits.templates`.
This counts the separate root without unchecked addition. It admits root source
bytes first; in declaration order, it charges each stored name against graph
`nameBytes`, then the entry's raw or parsed source against cumulative
`sourceBytes`. All entries, including empty and unused sources, count. Checks use
remaining-capacity subtraction and cooperative cancellation polling.

The shared U2 helper next parses a raw root and raw entries once in declaration
order, retaining parsed ASTs. It then revalidates parsed root and entries under
the executing engine's nesting profile, root first and entries in declaration
order. Only after every input succeeds does graph summarization begin. Invalid
unused input throws without findings. Parsing errors keep the existing anonymous
syntax line/column provenance; no stored-name attribution is fabricated.

Graph ledgers are independent of registry name admission and runtime budgets.
Zero graph name/edge capacity is valid; template capacity must be positive.
Root source is charged separately even if identical content is also registered.
`Int.max` capacities use the same checked comparisons and subtraction. These are
logical work/storage limits, not RSS, interruption-latency or wall-clock bounds.

## One selection authority, two index orders

Prepared AST slots retain U1 declaration `entryIndex`. Graph rank is a separate
local integer mapping: root first, then stored names sorted by UTF-8 bytes. All
ASTs are summarized, but only literal-reachable nodes are returned. Each unique
literal request from a reachable origin spends one edge allowance, including
missing requests. Unreachable origins spend no edge allowance.

After charging an edge, U2's unchanged selector calls `registry.resolve` once.
Its stored spelling and index determine the edge and target rank. No canonical
String-keyed lookup, duplicate resolver or second AST selection occurs. Exact
base wins, then literal `.liquid` append; canonical siblings never substitute.
An overlong request throws the original typed registry capacity error. An
exhausted edge capacity is checked before lookup and therefore wins if both
fail. Only a genuine resolver miss produces `resolvedName == nil`.

Nodes, per-origin edges, SCC members and SCC groups follow deterministic UTF-8
rank order. Identical requests deduplicate per origin; canonical siblings do not.
The existing iterative SCC traversal is retained. Its internal cancellation
check is injectable for deterministic tests; public methods always use the task
check and expose no callback. Per-invocation buffers and immutable inputs permit
concurrent graph inspection and rendering on a shared engine/registry.

## Static findings and runtime parity

For actually executed literal references resolved on their first candidate,
U2 rendering and U3 graphs retain the same requested bytes, stored name and
entry index. Static analysis also retains literals in branches that never run.
It does not evaluate conditions, filters, context or callbacks, or predict a
missing-literal context-string retry. Dynamic includes report their reachable
origin without guessing a target. Variable-form render remains unsupported.

Missing references, dynamic origins and cycles are successful findings, not
render-safety or authorization verdicts. Empty, NUL-containing and pathlike names
remain opaque caller-supplied identities. No loader, cache, I/O, escaping policy,
language feature, graph result type, dependency or platform change is added.
Hosts retain responsibility for private error text and safe HTTP/log handling.

The new tests include the seven supplied byte oracles, permutation checks,
2,001-entry cyclic/wide graphs, exact capacity/error precedence, deterministic
internal cancellation checkpoints, and concurrent U2 rendering. Native receipts
and the independent import-only consumer live in the dated return, separately
from historical U1/U2 receipts. U4/U5 and Vapor D0/D1 require separate dispatch.
