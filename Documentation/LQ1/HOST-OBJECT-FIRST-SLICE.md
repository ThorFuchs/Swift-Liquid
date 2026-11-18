# Host objects: first-slice contract

Status: implementation design. This contract defines a deliberately narrow
first slice; it is not a claim that Shopify Drop objects are already supported.
It refines [the broader proposal](STANDARD-DROP-DESIGN-2.1.md).

## Shape

Use an additive, explicitly supplied host environment rather than adding a case
to the public `LiquidValue` enum. A host object exposes only explicitly registered
properties. Each property is an exact, case-sensitive Unicode-scalar name and an
`@Sendable` asynchronous callback returning a `LiquidValue`. The callback may
suspend, as existing custom filters can. The engine never reflects arbitrary
Swift or Ruby objects and never constructs host operations from fixture text.

For the first slice, objects are named root bindings and their properties return
ordinary Liquid values. The returned value can itself contain admitted arrays
and objects, but cannot contain another host object. Both dotted and dynamic
string-bracket lookup use the same registered property. A missing property
produces Liquid null; a callback may return explicit null as a value. Neither
case changes the existing missing-variable policy. Integer-keyed host access,
iteration, object identity, recursive host values, object-level coercion and
Shopify's complete Drop semantics are deliberately outside this slice.

The later dynamic-family extension adds explicitly registered nonempty UTF-8
prefixes. Exact properties win, then the longest matching prefix; unmatched
keys do not call host code. Each prefix and lookup is charged to the invocation
budget, and a nil callback result means missing. This enables bounded string-key
property families; it does not add unrestricted reflection or the other Drop
capabilities above.

A subsequent explicit indexer extension accepts typed string and integer keys
and groups all other key types as `.other`. Existing hosts retain their prior
string-only behavior. Exact and dynamic string properties win over the indexer;
a matching callback returning nil does not trigger a second callback. Hosts
deliberately installing an indexer control the exposure policy for all keys it
receives. This extension adds no object materialization, iteration, recursive
host objects or implicit reflection.

Using the host object itself as an output, condition, filter input, assignment
or other value must fail explicitly until object-level behavior is specified.
An implementation must not expose Swift's `Mirror`, type names or callback
storage through the existing fallback paths. It must not silently coerce the
object to a primitive to make individual fixture examples pass.

## Ownership and boundaries

Bindings and callbacks are checked Sendable; the engine and parsed template
remain reusable and do not retain invocation state. Each render validates its
own bindings and shares its existing context-value, step, output and nesting
budgets across callback results. Reject duplicate root bindings, collisions with
ordinary context roots, duplicate exact property names, invalid/nonfinite or
oversized return values and exhausted limits. Check cancellation immediately
before and after each awaited callback, including when the callback throws.
Unexpected callback errors propagate; they are not converted to normal output.

Host code is trusted application code. Cancellation cannot preempt a callback
that does not cooperate, and logical budgets are not a wall-clock or memory
guarantee. No implicit filesystem or network access, global cache, shared mutable
registry, dynamic plugin or additional root package dependency is introduced.

## Evaluator constraints

The current renderer has optimized paths for static variable access, immediate
templates, filter arguments and append operations. A host-enabled render must
route those paths through the same checked property lookup and direct-object
rejection. Ordinary renders must retain their current behavior. Explicitly test
`self`, assignment, condition, filter, loop and partial boundaries so that a
host object cannot escape into a fallback `String(describing:)` or `Mirror`
path. Protect the invocation-owned scope and partial visibility rules.

## Qualification

Use public API tests for source and parsed templates, all parser modes, exact
name spelling, dynamic keys, null/missing, callback errors, cancellation,
capacity exhaustion, concurrent renders, reuse and scope isolation. Preserve
the pinned fixtures, comparator, parser metadata and exclusion ledger. The
first slice exercises real host callbacks but does not by itself admit the 56
standard-drop variants: boxed-value coercion, identity, iteration and error
semantics still need their own reference-backed contracts.

Final source qualification must include the affected `Scripts/ci.py` lanes,
public consumer checks, documentation and the extraction adaptation record.
Timing remains a separately admitted measurement; no performance verdict follows
from a functional test.

## Boxed Boolean extension

An explicit Boolean host binding preserves the Boolean value for Liquid value
operations while keeping property access on the host-object boundary. This is a
bounded extension, not support for arbitrary nested or boxed Drop values.

## Boxed integer extension

An explicit native-width integer binding uses its integer for arithmetic and
comparison while retaining the object boundary through assignment, property
access, `size` and a selected `default`. It does not add nested host objects or
arbitrary Ruby integer support.

## Boxed string extension

An explicit string or nil box preserves object-specific access, iteration,
filter and `default` behavior while using its represented value for truthiness
and comparison. A separately admitted finite root array permits ordinary
values and direct boxed-string elements; it is not a general nested host graph.
Nil string conversion reports `LiquidError.invalidValue`, without claiming to
reproduce Ruby exception classes.

## Finite host sequence extension

An explicitly supplied immutable sequence snapshot is admitted per invocation
against existing value, depth, byte, work and cancellation limits. Loop
iterations use the existing iteration quota. Size, first, last, count, min,
max, sort and to_liquid are exposed without reflection; ordering uses the
engine's comparable scalar domain. This bounded snapshot is not a streaming or arbitrary
`AsyncSequence` bridge, and it does not add nested host objects.


## Explicit integer-valued nested nodes

A separate opt-in `LiquidHostNode` capability supports exact named callbacks
returning the current node, an explicitly constructed node, an admitted ordinary
value or missing. Each transition uses invocation-owned work, value and nesting
budgets, including cycles, with cancellation checked around callbacks. Integer
materialization does not grant numeric conversion to built-in arithmetic filters.
This narrow capability does not expose arbitrary objects or nested host values in
ordinary containers. Existing fixture, conformance and release holds remain.


## Explicit opaque host objects

A root-level opaque host object supplies display text without materializing a
primitive value. It is truthy, non-iterable and compared by identity;
`to_liquid` preserves that identity. A typed custom filter receives display
text, which deliberately ends the opaque-object boundary. This does not
provide reflection, arbitrary Drop RPC or nested opaque host graphs.
