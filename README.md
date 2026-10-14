# Swift-Liquid

**Shopify Liquid templates, written in modern Swift.**

Render HTML, Markdown, configuration files, and plain text with a focused Liquid
engine and a command-line tool. Swift-Liquid provides typed Sendable input values,
immutable reusable templates, explicit partials, and Swift 6 concurrency. The
package has no third-party runtime dependencies.

[![CI](https://github.com/ThorFuchs/Swift-Liquid/actions/workflows/ci.yml/badge.svg)](https://github.com/ThorFuchs/Swift-Liquid/actions/workflows/ci.yml)
[![Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

**1.0 is being qualified.** The API and compatibility contract may change until
the first version tag. See the [release gates](Documentation/ReleasePlan.md) and
[compatibility evidence](Documentation/Conformance.md). Maintained by
[Thorsten Fuchs](https://github.com/ThorFuchs).

## Start with a template

```swift
import Liquid

let engine = LiquidEngine()
let output = try await engine.render(
    template: "Hello, {{ name | upcase }}!",
    context: ["name": "Swift"]
)
print(output) // Hello, SWIFT!
```

Context values use Swift literals: strings, integers, floating-point numbers,
booleans, arrays, objects, and `nil`. Object literals retain member order; keys
retain their Unicode scalar spelling, including canonically equivalent forms.
Liquid truthiness is preserved: only `nil` and `false` are falsy; empty strings,
empty arrays, and zero are truthy.

## Installation

Swift tools/compiler **6.4 or later**, in Swift language mode 6.

Until a version is released, use a pinned commit or the development branch:

```swift
.package(url: "https://github.com/ThorFuchs/Swift-Liquid.git", branch: "main")
```

Add the library to your target:

```swift
.product(name: "Liquid", package: "swift-liquid")
```

The package declares macOS 14, iOS 17, tvOS 17, watchOS 10, and visionOS 1 as its
Apple deployment minimums. Qualification currently runs on macOS 27 with Swift 6.4.
Platform declarations alone are not evidence of device qualification. The
[consumer example](Examples/Consumer) is a separate package using only public APIs.

## Parse once, render many times

```swift
let template = try LiquidTemplate("{% for item in items %}{{ item }} {% endfor %}")
let result = try await engine.render(template, context: ["items": ["one", "two"]])
print(result) // one two
```

Templates and engines are Sendable. Each render owns its variables, scopes,
iteration counters, and temporary output. Share a parsed template across tasks
without sharing mutable rendering state. Caching is explicit: keep the template
value in your application rather than relying on a global cache.

## Compose templates explicitly

```swift
let page = try await engine.render(
    template: "{% render 'card', title: title %}",
    context: ["title": "Liquid in Swift"],
    templates: ["card": "<h2>{{ title | escape }}</h2>"]
)
print(page) // <h2>Liquid in Swift</h2>
```

`render` isolates local variables; `include` follows Liquid's shared-scope
behavior. Partial sources are supplied by name. The library performs no implicit
filesystem or network access. Use `escape` or `escape_once` for HTML content:
Liquid does not automatically escape output.

## Read JSON without losing object order

```swift
let value = try LiquidValue(json: #"{"name":"Ada","roles":["author","editor"]}"#)
if case .object(let context) = value {
    print(try await engine.render(template: "{{ name }}", context: context))
}
```

The JSON bridge rejects malformed input, duplicate keys, trailing data, and
non-finite numbers. Numbers use `Int` and finite `Double`; use strings for exact
large decimal data. This bridge is intended for template inputs. The sibling
[Swift-JSON](https://github.com/ThorFuchs/Swift-JSON) provides an exact JSON data model.

## Command-line rendering

```sh
swift build -c release
.build/release/liquid render greeting.liquid --data context.json
.build/release/liquid render page.liquid --data context.json --partials ./partials --output page.html
printf 'Hello, {{ name }}!' | .build/release/liquid render - --data context.json
.build/release/liquid validate page.liquid
```

The CLI writes rendered bytes to stdout or the requested output file and sends
diagnostics to stderr. It exits with a nonzero status on failure. See the
[CLI reference](Documentation/CLI.md) for options and examples.

## Compatibility, tests, and performance

The language target is Shopify's **open-source Liquid core**, including its
standard tags and filters. Shopify storefront objects, theme tags, Rhoe data
loaders, template inheritance, macros, DOCX rendering, services, and WASM hosting
are outside the 1.0 package. See the [language contract](Documentation/Language.md) and
[date guide](Documentation/Dates.md).

The repository vendors all **1,098 cases** from a pinned Golden Liquid corpus,
with its original license and checksum. The test runner checks successful
outputs and expected errors, preserves fixture object order, and passes parser
mode metadata to the engine. The fixture integrity test prevents an absent or
empty corpus from passing unnoticed. Fixture expectations and reference-runtime
comparisons are distinct evidence; both are documented. An additional **185
reference-checked probes** cover Unicode scalars and keys, structural equality,
negative arithmetic, parser modes, loop interruption, and date parsing/formatting.
The reference receipt separates successful renders, expected errors, and reference
failures; one recovered Ruby filter error remains an open release gate.

```sh
python3 Scripts/ci.py --lane native
python3 Scripts/ci.py --lane docs
python3 Scripts/ci.py --lane performance
```

Performance uses a separate release-mode benchmark package. Measurements report
workloads, sample counts, latency distributions, output checksums, toolchain, and
source identity. Swift-Liquid makes no inherited speedup or process-memory claim.
See [performance](Documentation/Performance.md).

## Documentation and contributing

- [API reference and guides](https://thorfuchs.github.io/Swift-Liquid/documentation/liquid/)
- [Documentation index](Documentation/README.md) and [DocC catalog](Sources/Liquid/Documentation.docc)
- [Language and behavior](Documentation/Language.md), [CLI](Documentation/CLI.md), and [architecture](Documentation/Architecture/README.md)
- [Contributing](CONTRIBUTING.md), [support](SUPPORT.md), and [security reporting](SECURITY.md)
- [Release process](RELEASING.md) and [changelog](CHANGELOG.md)

Swift-Liquid is adapted from [RhoeLiquid](https://github.com/RhoePlatform/RhoeLiquid),
with a focused public API and independent qualification. Original contributions
are licensed under [Apache-2.0](LICENSE). Upstream source attribution and fixture
licenses are retained in [NOTICE](NOTICE), [third-party notices](THIRD_PARTY_NOTICES.md),
and the [extraction manifest](Documentation/Architecture/ExtractionManifest.json).
