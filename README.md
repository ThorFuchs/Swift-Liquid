# Swift-Liquid

**Shopify Liquid templates for modern Swift. One library, one CLI, no package dependencies.**

Render HTML, email, Markdown and configuration files with typed values, reusable
parsed templates and Swift 6 concurrency. Supply partials and application filters
explicitly, inspect templates before rendering, and opt into timing and budget
metrics when you need them. Each operation owns its mutable state.

[![CI](https://github.com/ThorFuchs/Swift-Liquid/actions/workflows/ci.yml/badge.svg)](https://github.com/ThorFuchs/Swift-Liquid/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ThorFuchs/Swift-Liquid)](https://github.com/ThorFuchs/Swift-Liquid/releases/latest)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

[Read the documentation →](https://thorfuchs.github.io/Swift-Liquid/)

Maintained by [Thorsten Fuchs](https://github.com/ThorFuchs). The latest stable
release is [1.3.0](https://github.com/ThorFuchs/Swift-Liquid/releases/tag/1.3.0).
Use a released version for applications; `main` and the documentation site track
ongoing development. Release assets include the source, compiled DocC reference,
qualification evidence and SHA-256 checksums for that exact version.

## Why Swift-Liquid?

- **A focused language target.** Shopify's open-source Liquid core, with standard
  tags, filters, parser modes and explicit error recovery.
- **Parse once, share safely.** Engines, templates, inputs and results have checked
  `Sendable` conformance. Variables, counters, diagnostics and budgets belong to
  one invocation.
- **Explicit composition.** Pass partials by name and configure typed custom
  filters on an immutable engine. The library performs no implicit file or network I/O.
- **Useful inspection.** Analyze the actual AST, then inspect an explicit partial
  bundle for literal dependencies, missing references, dynamic includes and cycles.
- **Finite, observable work.** Cumulative quotas and cooperative cancellation are
  part of the operation contract. Metrics are opt-in.
- **Evidence you can inspect.** Pinned independent fixtures, comparisons with Ruby
  Liquid, public consumers, Swift Testing, sanitizers and retained release measurements.

## Requirements and products

| Requirement | Baseline |
| --- | --- |
| Swift tools and compiler | 6.4 or later |
| Swift language mode | 6 |
| Declared Apple minimums | macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1 |
| Runtime qualification | macOS 27 with Swift 6.4; four simulator SDK compilation gates |
| Package products | `Liquid` library and `liquid` executable |
| Root package dependencies | None; Foundation comes from the platform SDK |
| License | Apache-2.0 original code, with retained upstream notices |

Simulator compilation is separate from device execution. Linux, WASI and browser
hosting have no runtime qualification claim. The standalone schema qualification
tool uses [Swift-JSON](https://github.com/ThorFuchs/Swift-JSON); applications linking
`Liquid` acquire no package dependencies.

## Installation

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/ThorFuchs/Swift-Liquid.git", from: "1.3.0")
```

Then add the library product to your target:

```swift
.product(name: "Liquid", package: "swift-liquid")
```

For clean CLI checkout instructions, published-URL qualification and index status,
see [package discovery](Documentation/PackageDiscovery.md).

See the complete [public consumer package](Examples/Consumer). The executable
examples below are also [compiled and run in CI](Examples/READMEConsumer).

## Render a template

```swift
import Liquid

let engine = LiquidEngine()
let output = try await engine.render(
    template: "Hello, {{ name | upcase }}!",
    context: ["name": "Swift"]
)
print(output) // Hello, SWIFT!
```

Context values use Swift literals: strings, integers, finite floating-point
numbers, booleans, arrays, objects and `nil`. Only `nil` and `false` are falsy;
zero, empty strings and empty arrays are truthy. Object literals retain insertion
order and the exact Unicode scalar spelling of keys.

## Parse once, render many times

```swift
import Foundation
import Liquid

let engine = LiquidEngine()
let template = try LiquidTemplate("{% for item in items %}{{ item }} {% endfor %}")
let output = try await engine.render(template, context: ["items": ["one", "two"]])
print(output.trimmingCharacters(in: .whitespaces)) // one two
```

Keep parsed templates in your application and share them across tasks. Each render
gets independent state. There is no implicit global cache or mutable registry.
See [limits and concurrency](https://thorfuchs.github.io/Swift-Liquid/documentation/documentation/limitsandconcurrency/).

## Compose templates explicitly

```swift
import Liquid

let output = try await LiquidEngine().render(
    template: "{% render 'card', title: title %}",
    context: ["title": "Swift & Liquid"],
    templates: ["card": "<h2>{{ title | escape }}</h2>"]
)
print(output) // <h2>Swift &amp; Liquid</h2>
```

`render` isolates local variables; `include` follows Liquid's shared-scope behavior.
Supply partials as sources or parsed templates. HTML escaping is explicit: use
`escape` or `escape_once` when inserting text into HTML. Read the
[rendering and partials guide](https://thorfuchs.github.io/Swift-Liquid/documentation/documentation/renderingandpartials/).

## Supply JSON and custom filters

```swift
import Liquid

let value = try LiquidValue(json: #"{"name":"Ada"}"#)
if case .object(let context) = value {
    let engine = try LiquidEngine(filters: [
        LiquidFilter("greet") { value, _, _ in
            guard case .string(let name) = value else {
                throw LiquidFilterFailure("Expected a name")
            }
            return .string("Hello, " + name)
        }
    ])
    print(try await engine.render(template: "{{ name | greet | escape }}", context: context)) // Hello, Ada
}
```

The input JSON bridge rejects malformed input, duplicate keys, trailing data and
non-finite numbers. It uses `Int` and finite `Double`; supply strings for decimal
data that must remain exact. Custom filters receive typed values and belong to
one engine. Standard filters are protected. See [values and JSON](https://thorfuchs.github.io/Swift-Liquid/documentation/documentation/valuesandjson/)
and the [custom-filter contract](Documentation/CustomFilters.md).

## Inspect source and partial dependencies

```swift
import Liquid

let engine = LiquidEngine()
let summary = try engine.inspect(template: "{{ user[key] | escape }}{% render 'card' %}")
print(summary.variableRoots.joined(separator: ",")) // key,user

let graph = try engine.inspectDependencies(
    template: "{% include 'card' %}",
    templates: ["card": "{% include 'badge' %}"]
)
print(graph.nodes.count) // 2
print(graph.missingReferences.map(\.requestedName).joined(separator: ",")) // badge
```

Inspection traverses the AST without evaluating expressions, calling filters or
loading files. Reads include local variables and retained branches; they do not
constitute a required-input schema. Dependency inspection admits the whole supplied
bundle under explicit bounds and follows the renderer's name lookup rules. Missing
references and cycles are findings; they do not prove render failure or success.
Read the [inspection](Documentation/Inspection.md) and [dependency](Documentation/Dependencies.md) contracts.

## Measure a render

```swift
import Liquid

let measured = try await LiquidEngine().renderWithMetrics(
    template: "Hello, {{ name }}!", context: ["name": "Swift"]
)
print(measured.output) // Hello, Swift!
print(measured.metrics.outputBytes) // 13
```

Metrics report monotonic elapsed durations and charged operation counts. Parsed
calls omit parse duration. Ordinary rendering collects no timing; the measured
APIs share its execution and error behavior. Logical quotas are not process-memory
or wall-clock guarantees. See [metrics](Documentation/Metrics.md) and
[errors and recovery](Documentation/Errors.md).

## Use the CLI

```sh
swift run -c release liquid render greeting.liquid --data context.json
swift run -c release liquid render page.liquid --data context.json --partials ./partials --output page.html
swift run -c release liquid validate page.liquid
swift run -c release liquid analyze page.liquid --format json
swift run -c release liquid analyze page.liquid --dependencies --partials ./partials --format json
```

The CLI writes rendered bytes to stdout or the requested file, diagnostics to
stderr, and a nonzero exit status on operational failure. `--metrics PATH` writes
an independent JSON metrics file. See [CLI usage and schemas](Documentation/CLI.md).

## Compatibility and independent evidence

The language authority is [Shopify's Liquid reference implementation](https://github.com/Shopify/liquid)
and its [core language documentation](https://shopify.github.io/liquid/).
Swift-Liquid targets that open-source core. Storefront objects, theme-only tags,
inheritance, macros, platform data loaders, document rendering and hosting services
remain outside this package's [language contract](Documentation/Language.md).

The independent [Golden Liquid test suite](https://github.com/jg-rp/golden-liquid),
maintained by James Prior, contributes all **1,098 cases** from a
[pinned revision](https://github.com/jg-rp/golden-liquid/tree/65c2f76ea64ef20647c295b000df5fcd9fc471cd).
The complete fixture bytes, original license, checksum and parser-mode metadata
are retained. This corpus is separate from
[Shopify's own upstream tests](https://github.com/Shopify/liquid/tree/4e39ae4cc3da73921923c0669e0fc84a66b2f696/test).

Release qualification also compares authored probes and date grammar behavior
with pinned Ruby Liquid. Receipts distinguish successful renders, parsed cases,
expected and recovered errors, supported-year boundaries and reference failures.
Swift Testing exercises public contracts, quotas, cancellation, concurrent reuse
and graph relationships; independent consumers and CLI/schema checks cover package
integration. AddressSanitizer and ThreadSanitizer qualify separate safety concerns.
Test counts alone do not establish complete conformance. See the
[conformance record and pins](Documentation/Conformance.md).

```sh
python3 -B Scripts/ci.py --lane native
python3 -B Scripts/ci.py --lane safety
python3 -B Scripts/ci.py --lane docs
```

Performance evidence retains workloads, sample distributions, checksums, compiler
and source identity. Review [methodology](Documentation/Performance.md) and the
[released qualification archives](https://github.com/ThorFuchs/Swift-Liquid/releases).
No inherited speedup, zero-overhead or process-memory claim is made.

## Documentation and community

- [Documentation site](https://thorfuchs.github.io/Swift-Liquid/), [API reference](https://thorfuchs.github.io/Swift-Liquid/documentation/liquid/) and [guide index](Documentation/README.md)
- [Contributing](CONTRIBUTING.md), [community standards](CODE_OF_CONDUCT.md), [support](SUPPORT.md) and [private security reporting](SECURITY.md)
- [Contribution isolation](Documentation/ContributionIsolation.md) and [package discovery](Documentation/PackageDiscovery.md)
- [Adversarial testing and structured evidence](Documentation/Testing.md)
- [Architecture and provenance](Documentation/Architecture/README.md), [documentation tooling](Documentation/DocumentationTooling.md) and [quality sprints](Documentation/QualityRoadmap.md)
- [Changelog](CHANGELOG.md), [release process](RELEASING.md) and [adopted feature roadmaps](Documentation/README.md)

## License and credits

Original Swift-Liquid contributions are [Apache-2.0](LICENSE). The engine is adapted
from [RhoeLiquid](https://github.com/RhoePlatform/RhoeLiquid); upstream Apache notices
are preserved. Golden Liquid fixtures retain their MIT license, and Ruby Date/Time
adaptations retain the applicable BSD terms. See [NOTICE](NOTICE),
[third-party notices](THIRD_PARTY_NOTICES.md) and the
[extraction manifest](Documentation/Architecture/ExtractionManifest.json).
