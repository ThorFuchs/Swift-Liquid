# ``Liquid``

Shopify Liquid templates for Swift 6.4, with Sendable values and reusable templates.

## Overview

Swift-Liquid exposes a focused engine for Shopify's open-source Liquid core.
Create a ``LiquidEngine``, supply an ordered ``LiquidObject`` context, and render
source directly or keep a parsed ``LiquidTemplate`` for repeated use.
Each invocation owns its variables, scopes, counters, output, and execution budget.

```swift
let output = try await LiquidEngine().render(
    template: "Hello, {{ name | upcase }}!",
    context: ["name": "Swift"]
)
```

The library performs no implicit filesystem or network access. Supply partial
templates explicitly. Output follows Liquid's escaping behavior: use `escape`
or `escape_once` when inserting text into HTML.

## Topics

### Rendering

- ``LiquidEngine``
- ``LiquidTemplate``
- <doc:RenderingAndPartials>
- <doc:Dates>

### Input values

- ``LiquidValue``
- ``LiquidObject``
- ``LiquidJSONError``
- <doc:ValuesAndJSON>

### Operation behavior

- ``LiquidSyntaxMode``
- ``LiquidLimits``
- ``LiquidError``
- <doc:LimitsAndConcurrency>
