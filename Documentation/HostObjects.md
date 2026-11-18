# Explicit host properties

Applications can expose selected, asynchronously computed properties through
an explicit `LiquidHostObject` supplied to a render. The callbacks return
`LiquidValue` values and are checked Sendable; no reflection, global registry,
implicit file access or additional package dependency is involved.

```swift
import Liquid

let product = LiquidHostObject("product", properties: [
    LiquidHostProperty("title") { "A Swift guide" },
    LiquidHostProperty("price") { 42 }
])
let output = try await LiquidEngine().render(
    template: "{{ product.title | escape }}: {{ product.price }}",
    hostObjects: [product]
)
// A Swift guide: 42
```

Root and property names use exact Unicode-scalar spelling. Duplicate root names,
collisions with the ordinary context, duplicate property names, empty names and
the reserved root `self` are rejected at render entry. A template may access
registered properties through dotted names or dynamic string brackets. An
unregistered property is Liquid null; a callback can explicitly return null.
Only registered properties can be called. Hosts without an indexer continue to
reject non-string keys.

Applications can also register `LiquidHostDynamicProperty` families with a
nonempty, exact UTF-8 prefix and an async callback. Exact properties take
precedence; among matching families the longest prefix wins. An unmatching key
never reaches a callback. The callback receives the complete key and returns
either an admitted `LiquidValue` or nil for a missing property; `.null` is an
explicit null. Empty and duplicate prefixes fail when rendering begins. Prefix
registrations and lookup work are charged to the invocation's existing value
and step capacities. As with exact properties, host code is trusted and must
apply any additional key validation appropriate to its exposed family.

For typed access, a host may explicitly provide a `LiquidHostIndexer`. It receives
`LiquidHostIndexKey.string`, `.integer`, or `.other`; the engine does not
coerce integers into strings or silently convert other key types. Exact and
matching dynamic string properties have precedence. When a dynamic family
matches, a nil result remains missing rather than invoking the indexer. If no
string property matches, the indexer may receive any string key, including an
empty one, so the trusted host must enforce its own access policy. Integer and
other keys reach only an explicitly installed indexer. Indexer registration,
invocation, returned values and cancellation use the same per-render budgets
and boundaries as other host callbacks.

```swift
let dynamic = LiquidHostObject("example", dynamicProperties: [
    LiquidHostDynamicProperty(prefix: "greet_") { key in
        .string("Hello, " + key.dropFirst("greet_".count))
    }
])
let rendered = try await LiquidEngine().render(
    template: "{{ example.greet_Ada }}", hostObjects: [dynamic]
)
// Hello, Ada
```

An indexed object can opt into a direct `render ... with` binding with
`LiquidHostObject("source", partialBindingIndexer: LiquidHostIndexer { key in ... })`.
Only the registered typed-key handler is available in the partial. The object
itself remains unavailable as a Liquid value: output, assignment, `include`
bindings and named-argument bindings do not transfer it. A direct `with` binding
may be forwarded to another rendered partial under the same limits. Objects
created with the ordinary indexer initializer do not opt in. This is not a
recursive host graph or an implicit conversion to a dictionary.

A host can explicitly create `LiquidHostObject("flag", booleanValue: false)` to
expose a boxed Boolean. Conditions, comparisons, output and standard filters use
the supplied Boolean value, including `blank`, `empty`, and `default` semantics.
The binding remains an object for property access and has no exposed properties;
assignment and a selected `default` preserve that boundary. This profile does not
provide arbitrary boxed host values.

A host can also create `LiquidHostObject("count", numberValue: 42)` for a
boxed native-width integer. Numeric operations, comparisons and output use
that integer; zero is truthy. The binding remains an object for property
access, and `size` returns zero rather than the byte size of an ordinary
integer. Assignment and a selected `default` keep the object boundary.
The standard profile does not register `json` as a built-in filter; custom
filters receive the represented integer. The pinned Ruby suite supplies an
additional JSON test filter with a separate object policy, which is not covered
by the targeted NumberDrop qualification.

A boxed string is created with `LiquidHostObject("name", stringValue: "Ada")`;
its represented string drives truthiness, comparison and string filters, while
property access remains missing. A boxed empty string is truthy and remains the
selected object under `default`. Its `size` is zero, `first` and `last` are
missing, and it is not an iterable string. A nil-valued box compares as nil but
fails direct or string-filter conversion with `LiquidError.invalidValue`;
this reports the failure without claiming Ruby's native exception type.
Base64 decoding rejects invalid encoding; a decoded byte sequence that is not
UTF-8 is outside this typed-string contract and reports an invalid-value error.
The standard profile does not register `json` as a built-in filter; custom
filters receive the represented string or null. The pinned suite's additional
JSON test filter uses a different object policy and remains separately unqualified.

For a finite root array containing boxed strings, use
`LiquidHostObject("items", array: [.value("Ada"), .boxedString("Ada")])`.
Each element is admitted and charged for every render; ordinary `.value`
elements can contain ordinary Liquid arrays and objects. Boxed elements are
permitted directly in this root array, not inside arbitrary nested containers or
as callback results. `uniq` compares represented values while retaining the
first element, including its object identity for later access. Array equality
follows Ruby's left-element comparison: a boxed string and an ordinary string
can compare differently when their order is reversed.

A finite host sequence is created with
`LiquidHostObject("items", sequence: ["first", "second", "third"], displayName: "Items")`.
The sequence is an immutable snapshot, not an arbitrary or streaming iterator.
Each render admits every element against its value, depth, byte and work limits
before rendering. The existing loop-iteration limit applies to each emitted loop
iteration, and admission and iteration check task cancellation. `size`, `first`
and `last` are exposed properties and filters. The properties `count`, `min`,
`max`, `sort` and `to_liquid` are also supported; ordering uses the engine's
comparable scalar domain and reports unsupported comparisons as errors. Other
properties are missing. The sequence object remains truthy even when the snapshot is empty, and its
explicit display name is rendered when the object itself is output. Custom
filters receive an ordinary array snapshot. No callback or mutable iterator is
retained by a parsed template or shared between renders.

An explicit opaque object is created with
`LiquidHostObject("item", opaqueDisplayName: "opaque")`. It stays truthy and
neither blank nor empty, even if its display text is empty. Its display text
is used for output and string filters, not equality or numeric conversion.
Only `to_liquid` is exposed and returns the same object; other properties and
indexes are missing. Assignment and `default` retain its identity, and two
separate objects compare unequal even when their display texts agree. It does
not iterate. Collection filters treat it as one element and preserve its
identity without exposing internal properties. Custom typed filters receive the
display text as a string, so this boundary does not preserve object identity. Display bytes and value admission
use the existing invocation limits. This is not an arbitrary-object bridge.

A host can expose a bounded, integer-valued node with explicitly registered
nested properties:

```swift
let node = LiquidHostNode(integerValue: 3, properties: [
    LiquidHostNodeProperty("nested") { .current },
    LiquidHostNodeProperty("square") {
        .node(LiquidHostNode(integerValue: 9))
    }
])
let result = try await LiquidEngine().render(
    template: "{{ item.nested.square }}",
    hostObjects: [LiquidHostObject("item", node: node)]
)
// 9
```

`.current` returns the same node with its properties intact; `.node` returns an
explicitly supplied node, `.value` returns an ordinary admitted Liquid value,
and `.missing` reports a missing property. Every transition is charged against
the render's work, value and nesting limits, including repeated returns of the
same node. Property names are exact and checked for emptiness, duplicates and
byte limits; callbacks and their returned values are checked for cancellation
and resource limits. Other key types do not invoke a property. No callback is
retained by a parsed template. This is not reflection or a general recursive
host graph or container protocol.

The node's native-width integer is its representation for output, comparisons,
truthiness and custom filters. A node remains an object for property access and
assignment. As in Shopify's standard NestedDrop, it does not provide numeric
conversion: built-in arithmetic filters coerce it to zero, including when used
as an argument. The suite's extra JSON test filter is outside this contract.
Hosts must handle integer overflow in their callbacks. Properties can also
return ordinary admitted primitive values, arrays or objects. This does not
implement the complete Shopify Drop contract.

Callbacks are trusted application code and may suspend. Captured state must be
Sendable; the host must synchronize any state shared between concurrent renders.
The engine checks cancellation around each callback and charges the invocation's
existing work and value budgets. A callback that does not cooperate cannot be
preempted. A callback may explicitly throw `LiquidHostFailure` to produce a recoverable
Liquid runtime failure. Throwing render APIs surface it as `LiquidError.rendering`;
`renderWithDiagnostics` overloads accepting `hostObjects` retain its message and
source location as a diagnostic. This applies to exact properties, dynamic
families, indexers and node properties. Cancellation takes precedence, and
quota errors and unexpected callback errors still propagate unchanged.
These limits are logical capacities, not a process-memory or wall-clock guarantee.

The parsed-template overload accepts explicit parsed partials; the source
overload accepts explicit partial sources. Host inputs follow the engine's
existing `render` and `include` scope rules. No host callback is retained in a
parsed template. See the [first-slice contract](LQ1/HOST-OBJECT-FIRST-SLICE.md)
for its boundaries and the [broader proposal](LQ1/STANDARD-DROP-DESIGN-2.1.md)
for deferred behavior.
