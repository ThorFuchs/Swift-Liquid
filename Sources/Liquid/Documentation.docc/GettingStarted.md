# Getting started

Install one library, supply a typed context and render a Liquid template.

## Add the package

Swift-Liquid requires Swift tools/compiler 6.4 or later and Swift language mode 6.
Add `https://github.com/ThorFuchs/Swift-Liquid.git` to your SwiftPM dependencies,
select a released version and add the `Liquid` product to your target. The root
package has no third-party dependencies. See the
[installation examples](https://github.com/ThorFuchs/Swift-Liquid#installation)
for complete manifest fragments.

The package declares macOS 14, iOS 17, tvOS 17, watchOS 10 and visionOS 1 minimums.
Runtime qualification covers macOS 27; four simulator SDKs have compilation gates.
Device execution, Linux, WASI and browser hosting have separate qualification needs.

## Render typed values

```swift
import Liquid

let output = try await LiquidEngine().render(
    template: "Hello, {{ name | upcase }}!",
    context: ["name": "Swift"]
)
```

``LiquidObject`` and ``LiquidValue`` accept native Swift literals. Only null and
false are falsy. Use ``LiquidTemplate`` to retain a parsed template for repeated
renders. Engines, parsed templates and inputs have checked Sendable conformance;
each invocation creates its own mutable work.

HTML escaping is explicit. Use `escape` or `escape_once` for text inserted into
HTML. Supply partials by name instead of relying on implicit loading. Begin with
<doc:RenderingAndPartials> and <doc:ValuesAndJSON>, then read
<doc:LimitsAndConcurrency> and <doc:ErrorRecovery> before selecting host policies.

## Choose the operation you need

- Render normally for complete output, or opt into recovered diagnostics.
- Configure typed callbacks with <doc:CustomFilters>.
- Inspect syntactic reads with <doc:TemplateInspection>.
- Inspect an explicit partial bundle with <doc:PartialDependencies>.
- Collect elapsed durations and charged counts with <doc:RenderMetrics>.
- Use the same engine from the terminal with <doc:CommandLine>.

The site tracks development on `main`. Each
[release](https://github.com/ThorFuchs/Swift-Liquid/releases) includes a compiled
DocC archive for its exact qualified source.
