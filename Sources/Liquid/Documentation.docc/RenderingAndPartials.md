# Rendering and partials

Parse once, render repeatedly, and compose sources explicitly.

## Reuse a parsed template

``LiquidTemplate`` retains an immutable internal syntax tree and the original
source. ``LiquidEngine`` creates fresh mutable rendering state for every call.

```swift
let template = try LiquidTemplate("{{ name | escape }}")
let engine = LiquidEngine()
let output = try await engine.render(template, context: ["name": "Ada"])
```

## Supply partials

The source overload accepts a dictionary of partial source strings. The parsed
overload accepts a dictionary of parsed templates. Names are exact, with an
optional `.liquid` suffix fallback. No URL or filesystem lookup occurs.

```swift
let output = try await LiquidEngine().render(
    template: "{% render 'card', title: title %}",
    context: ["title": "Swift"],
    templates: ["card": "<h2>{{ title | escape }}</h2>"]
)
```

`render` isolates local variables. `include` follows Liquid's shared-scope
behavior. Both operate under the invoking render's cumulative budget. Syntax
errors, missing partials, invalid operations, and exhausted budgets throw.
An operation returns one complete String after successful rendering.
