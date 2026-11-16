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
Only registered properties can be called. Integer keys on host objects are not
supported by this profile.

Properties can return admitted primitive values, arrays or objects. This first
profile does not return nested host objects and does not define the host object's
own truthiness, stringification, iteration, filter behavior or identity. Using
the host object itself as a value fails rather than silently flattening it. It
does not implement the complete Shopify Drop contract.

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
