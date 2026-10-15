# Swift-Liquid

**Shopify Liquid templates, written in modern Swift.**

Render HTML, Markdown, configuration files, and plain text with a focused Liquid
engine and a command-line tool. Swift-Liquid provides typed Sendable input values,
immutable reusable templates, explicit partials, and Swift 6 concurrency. The
SwiftPM dependency graph is empty; platform support comes from Foundation.

[![CI](https://github.com/ThorFuchs/Swift-Liquid/actions/workflows/ci.yml/badge.svg)](https://github.com/ThorFuchs/Swift-Liquid/actions/workflows/ci.yml)
[![Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

**Swift-Liquid 1.2.0 release candidate** adds opt-in render metrics and separate
CLI JSON metrics while preserving the 1.0/1.1 APIs and dependency-free core.
The latest published version is 1.1.0. See the
[1.2.0 release notes](Documentation/Releases/1.2.0.md)
and [compatibility evidence](Documentation/Conformance.md). Maintained by
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

Add Swift-Liquid to your package dependencies:

```swift
.package(url: "https://github.com/ThorFuchs/Swift-Liquid.git", from: "1.1.0")
```

This selects the published release line. The 1.2 metrics APIs below require the
candidate source until 1.2.0 is published.

Add the library to your target:

```swift
.product(name: "Liquid", package: "swift-liquid")
```

The package declares macOS 14, iOS 17, tvOS 17, watchOS 10, and visionOS 1 as its
Apple deployment minimums. Qualification currently runs on macOS 27 with Swift 6.4.
The library also compiles against all four declared simulator SDKs. These checks
are separate from device execution qualification. The
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

## Add application filters (1.1)

```swift
let engine = try LiquidEngine(filters: [
    LiquidFilter("greet") { value, _, _ in
        guard case .string(let name) = value else { throw LiquidFilterFailure("Expected a name") }
        return .string("Hello, " + name)
    }
])
let greeting = try await engine.render(template: "{{ name | greet | escape }}", context: ["name": "Ada"])
// Hello, Ada
```

Callbacks receive typed values and belong to one immutable engine configuration.
Standard filters are protected; defaults retain Shopify core behavior. See
[custom filters](Documentation/CustomFilters.md) and [application reuse](Documentation/Reuse.md).

## Inspect templates (1.1)

The 1.1 API inspects source or a parsed template without evaluating expressions,
calling filters, or loading partials:

```swift
let summary = try engine.inspect(template: "{{ user[key] | escape }}{% render 'card' %}")
// Roots: key, user; filters: escape; literal partials: card.
```

`liquid analyze page.liquid --format json` exposes the same AST summary. Roots
include local reads and conditional paths; they are not a required-input schema.
See the [inspection contract and JSON schema](Documentation/Inspection.md).
The filter and inspection APIs are available from 1.1.0; existing 1.0 render
call sites need no migration.

## Measure a render (1.2)

```swift
let measured = try await engine.renderWithMetrics(
    template: "Hello, {{ name }}!", context: ["name": "Swift"]
)
print(measured.output)
print(measured.metrics.totalDuration)
```

Source and parsed-template entry points return immutable timing and budget
observations. Use `renderWithDiagnosticsAndMetrics` for explicit recovered errors.
Ordinary render APIs collect no timing. The CLI's `--metrics PATH` writes separate
JSON while keeping rendered stdout intact. See the [metrics contract](Documentation/Metrics.md)
for timing boundaries, counter meanings and failure behavior.

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
remain outside the package. See the [language contract](Documentation/Language.md) and
[date guide](Documentation/Dates.md).

The repository vendors all **1,098 cases** from a pinned Golden Liquid corpus,
with its original license and checksum. The test runner checks successful
outputs and expected errors, preserves fixture object order, and passes parser
mode metadata to the engine. The fixture integrity test prevents an absent or
empty corpus from passing unnoticed. Fixture expectations and reference-runtime
comparisons are distinct evidence; both are documented. An additional **221
reference-checked probes** cover Unicode scalars and keys, structural equality,
negative arithmetic, parser modes, loop interruption, and date parsing/formatting.
The Ruby Date/Time grammar is additionally checked with 337 source-table cases
and 376 public date-filter cases. Reference receipts separate successful renders,
expected errors, recovered errors, supported-year boundaries, and reference failures.

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
- [Adopted 1.2 roadmap](Documentation/Roadmap-1.2.md), [adopted 1.1 roadmap](Documentation/Roadmap.md), and [RhoeLiquid feature review](Documentation/Architecture/UpstreamFeatureReview.md)

Swift-Liquid is adapted from [RhoeLiquid](https://github.com/RhoePlatform/RhoeLiquid),
with a focused public API and independent qualification. Original contributions
are licensed under [Apache-2.0](LICENSE). Upstream source attribution and fixture
licenses are retained in [NOTICE](NOTICE), [third-party notices](THIRD_PARTY_NOTICES.md),
and the [extraction manifest](Documentation/Architecture/ExtractionManifest.json).
