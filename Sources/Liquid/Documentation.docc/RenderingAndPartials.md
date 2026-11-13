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
The default engine evaluates a dynamic `include` name before lookup and rejects
non-string names. All supplied source bytes are admitted before rendering; a
selected partial is parsed once per invocation. Unused invalid partials are not
parsed. The optional byte-exact registry retains its separate eager-preparation
and literal-first selection contract.
Named `include` attributes are evaluated in source order, and earlier attribute
values are visible to later ones inside the include's temporary scope.

```swift
let output = try await LiquidEngine().render(
    template: "{% render 'card', title: title %}",
    context: ["title": "Swift"],
    templates: ["card": "<h2>{{ title | escape }}</h2>"]
)
```

`render` retains the original host context inputs and explicit named bindings.
Caller assignments, captures, loop locals and counters stay isolated. A named
binding, including null, shadows a host input only within that partial; nested
render starts again from the original host inputs unless bindings are passed.
`include` follows Liquid's shared-scope behavior. Both operate under the invoking
render's cumulative budget. Host inputs are admitted once for the invocation. Syntax
errors, missing partials, invalid operations, and exhausted budgets throw.
An operation returns one complete String after successful rendering.

Hosts can provide ``LiquidTemplateNameResolver`` to the parsed-root
`partialSources:` diagnostic APIs. The resolver maps a requested name to an
already supplied source name and defines the missing-name message. It cannot
fetch sources or bypass admission. Applications remain responsible for any
filesystem access, path policy and safe error presentation.

## Retain an application bundle

Keep parsed roots and partial maps as immutable application values. Convert your
own domain types explicitly to ``LiquidValue`` and ordered ``LiquidObject`` values.
The filter consumer demonstrates this pattern with repeated renders of one bundle.

If the application uses a parse cache, bound entries and retained source bytes.
Key by exact source, parser mode, parse limits and library/parser version; replace
a bundle when any root or partial source/configuration changes. Parsed templates
retain no filters. Engine configuration, clock and context still affect output
and belong in any separate output-cache policy. Budgets remain per invocation.
