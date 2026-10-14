# Recovering runtime errors

Return output together with diagnostics when recovery is intentional.

## Overview

``LiquidEngine/render(template:context:templates:syntaxMode:)`` throws when a
runtime operation fails. The CLI uses this behavior. For applications that need
Ruby-style recovery, call ``LiquidEngine/renderWithDiagnostics(template:context:templates:syntaxMode:)``:

```swift
let result = try await LiquidEngine().renderWithDiagnostics(
    template: "A{% assign b = items | reject: missing %}B",
    context: ["items": ["x"]]
)
// output: AB; one diagnostic for the undefined property
```

``LiquidRenderResult/diagnostics`` preserves encounter order, available line
numbers, and partial names. A result with diagnostics is not an error-free
render. Each invocation owns its errors and scopes.

Lax/strict assignments suppress error text while recording diagnostics; strict2
emits it. Output expressions and `echo` emit error text. Resource exhaustion,
unsupported values, cancellation and syntax errors still throw.
