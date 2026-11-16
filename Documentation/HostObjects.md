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

A host can explicitly create `LiquidHostObject("flag", booleanValue: false)` to
expose a boxed Boolean. Conditions, comparisons, output and standard filters use
the supplied Boolean value, including `blank`, `empty`, and `default` semantics.
The binding remains an object for property access and has no exposed properties;
assignment and a selected `default` preserve that boundary. This profile does not
provide arbitrary boxed host values or return nested host objects.

Properties can return admitted primitive values, arrays or objects. Other host
objects are not ordinary values and must be accessed through their explicitly
registered properties. This does not implement the complete Shopify Drop contract.

Callbacks are trusted application code and may suspend. Captured state must be
Sendable; the host must synchronize any state shared between concurrent renders.
The engine checks cancellation around each callback and charges the invocation's
existing work and value budgets. A callback that does not cooperate cannot be
preempted. Unexpected callback errors propagate rather than becoming output.
These limits are logical capacities, not a process-memory or wall-clock guarantee.

The parsed-template overload accepts explicit parsed partials; the source
overload accepts explicit partial sources. Host inputs follow the engine's
existing `render` and `include` scope rules. No host callback is retained in a
parsed template. See the [first-slice contract](LQ1/HOST-OBJECT-FIRST-SLICE.md)
for its boundaries and the [broader proposal](LQ1/STANDARD-DROP-DESIGN-2.1.md)
for deferred behavior.
