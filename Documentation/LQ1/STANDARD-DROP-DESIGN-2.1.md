# Typed host objects: 2.1 design proposal

Status: **design only**. This proposal does not add a public API, change the
adapter or admit a conformance case. The [capability study](STANDARD-DROPS-2.1.md)
found that replacing boxed Shopify test drops with ordinary primitive values
changes observable Ruby behavior. A representation must retain the object and
its operation-specific behavior through evaluation.

## Goal and boundary

Give an application an explicit, typed way to supply selected host-owned values
to Liquid, while preserving the existing `LiquidValue` input, rendering APIs,
default behavior and empty root dependency graph. The first evaluation target
is Shopify's pinned standard test-drop library, including boxed values, property
and index access, iteration, nested objects and errors. This is not a promise of
Ruby object compatibility or a general Ruby object bridge.

The existing `LiquidValue` is a public, checked-Sendable and Equatable enum.
Adding a host-object case directly could break exhaustive client switches and
would force an object equality rule into that type. Prefer investigating a new,
additive input wrapper and explicit rendering overload; do not change
`LiquidValue` merely to increase suite coverage. The exact Swift names and
signatures below are **not yet selected**.

## Proposed representation

Study an immutable checked-Sendable host environment containing primitive
`LiquidValue` values, nested containers and explicitly registered host-object
handles. A handle describes a bounded set of allowed operations. It is supplied
by the application, not looked up by class name, reflection, or a template's
arbitrary method name. Swift closures, any captured state and returned inputs
must satisfy checked Sendable requirements. Parsed templates remain independent
of a particular invocation and must not retain mutable host state.

Separate capabilities are necessary because materialization alone does not
define every operation:

- **Access:** accept typed string and integer keys without coercing distinct
  keys; distinguish a missing member from an explicit Liquid null.
- **Materialization and truthiness:** define when a host object provides a
  primitive value, whether it is empty or blank, and how an opaque object behaves.
- **Rendering and filters:** define object stringification, numeric coercion,
  equality and filter-specific behavior without replacing the object globally.
- **Iteration:** use a finite, charged interface with deterministic ordering;
  specify cancellation, lazy failure, nested values and whether a sequence can
  be consumed more than once.
- **Nested objects:** preserve explicit identity and access restrictions when a
  host operation returns another object or itself. Reusing an identity must not
  turn a cyclic object graph into an unbounded traversal.
- **Failure:** distinguish recoverable Liquid errors from cancellation, limits
  and unexpected host failures. Preserve the public raising and diagnostic
  contracts and source/partial locations.

All state that tracks access, scopes, iteration, diagnostics and quotas remains
owned by one render. The host controls its own external state; shared host
callbacks are trusted application code and cannot be made preemptible merely by
an engine quota. The engine must check cancellation and charge the existing
budgets at defined boundaries, admit returned values before using them and avoid
an unbounded queue or implicit cache. No file, network or database access is
provided by the engine.

## Decisions before implementation

1. Whether host operations are synchronous, asynchronous, or separate typed
   capabilities; evaluate renderer architecture and cost before selecting one.
2. The finite access and iteration limits, including repeated access, reentrancy,
   identity, nested values and cancellation while host code is suspended.
3. Exact Shopify reference rules for boxed Boolean, number, string and nil
   values across `empty`, `blank`, comparison, `size`, `first`, `last`, numeric
   filters, rendering and iteration. Probe output agreement alone is insufficient.
4. How checked host errors map to raise/inline diagnostics without catching
   cancellation or turning an operational limit into output.
5. Whether the JSON-RPC adapter uses native standard test objects or adds the
   pinned protocol's `drop_get`, `drop_call` and `drop_iterate` callbacks for
   separately supported host-owned objects. Bidirectional calls need request
   identity, framing, deadlock, lifetime and failed-exchange tests.
6. Source and binary compatibility, public naming, documentation and downstream
   integration. Any broader runtime feature requires explicit scope review.

## Qualification plan

Start with public consumer regressions for real host objects, not fixture-specific
output substitution. Cover all ten standard drop classes and the known negative
controls; both source and parsed templates; all supported parser and render
modes; nested partials; callback errors; cancellation; quotas; concurrent renders;
and isolation between two engines and two invocations. Preserve Swift 6 checked
Sendable diagnostics, fixture bytes and licenses, parser-mode metadata, unchanged
comparison rules and the zero-dependency package boundary.

Before admitting each excluded fixture, bind its exact pinned identity, input,
fixture digest and full transport requirements to a reference run. Retain raw
and reviewed outcomes independently, including failures and newly uncovered
barriers. A dynamic lookup must actually be resolved by the implementation during
rendering; neither inspecting the template to manufacture a lookup result nor
hard-coding an expected output is acceptable.

Measure the unchanged default primitive path and the new opt-in path separately.
Keep the existing canonical matched-performance lane and its historical baseline;
new workload or overhead measurements require their own reviewed protocol. No
claim of complete conformance, performance neutrality or a release follows from
this proposal.
