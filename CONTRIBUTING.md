# Contributing to Swift-Liquid

Start with a small, reproducible problem or a focused proposal. Use
[Issues](https://github.com/ThorFuchs/Swift-Liquid/issues) to discuss behavior and
open a pull request against `main` when the change is ready to review. The project
is maintained by [Thorsten Fuchs](https://github.com/ThorFuchs).

## Set up the package

Use Swift tools/compiler 6.4 or later in Swift language mode 6. Complete native
qualification currently runs on macOS 27 with the supported Xcode SDKs. The
package's declared deployment minimums remain those in [Package.swift](Package.swift).
No dependency install is required for the library or CLI. The isolated schema
qualification package resolves a pinned Swift-JSON release.

Read [AGENTS.md](AGENTS.md), the [architecture](Documentation/Architecture/README.md)
and the relevant [behavior contract](Documentation/README.md) before changing
semantics. Choose the intended Xcode with `DEVELOPER_DIR` when needed.

## Make an observable change

Include the smallest template, typed context and expected output that demonstrate
the issue. Write Swift Testing regressions through public APIs; exercise parsed
and source entry points when both are affected. Use deterministic seeds for
property tests and retain failing inputs. Shared engines and templates must remain
checked Sendable, with mutable work owned by each invocation.

Keep one `Liquid` library, one `liquid` executable and an empty root dependency
graph. Language extensions, new platforms and hosting integrations need a scope
decision. Do not add unsafe concurrency annotations or change fixture expectations
to accommodate an implementation failure.

## Run the affected qualification lanes

Run commands from the repository root:

```sh
python3 -B Scripts/ci.py --lane native
python3 -B Scripts/ci.py --lane safety
python3 -B Scripts/ci.py --lane docs
```

| Change | Additional evidence |
| --- | --- |
| Parser, standard filters or recovery | `reference` against the clean pinned Shopify checkout |
| Runtime or performance | `performance`, then matched comparisons on an idle host when evaluating a regression |
| Apple platform surface | `platforms` simulator compilation |
| Release preparation | All eight lanes, reviewed measurements and a clean `archive` rebuild |

The [conformance guide](Documentation/Conformance.md) explains the Ruby reference
setup. [Performance methodology](Documentation/Performance.md) defines comparable
measurements. Receipts and logs go under ignored `Artifacts/`; report actual
commands, results and limitations, including any unavailable checks. A missing
fixture, skipped check or reference-runtime error is never a successful render.

Structured Swift Testing admission uses the reviewed
[`Tests/TestInventory.json`](Tests/TestInventory.json). Update its function and
parameter counts with intentional test changes; qualification never regenerates it.
Disabled tests, known issues, empty collections and filtered omissions fail the gate.
See [adversarial testing and evidence](Documentation/Testing.md) for seeds, cancellation
barriers, raw receipts and the Swift 6.4 case-metadata adapter.

## Keep documentation executable

Document public declarations with a useful summary and named parameters. Explain
returns, errors, cancellation and limits where they affect callers. Add a focused
DocC guide when semantics span several APIs. The docs lane rejects missing public
comments, stale README examples and broken local site routes.

README examples are compiled by a separate public consumer. After changing a
Swift fence, regenerate its source and run the docs lane:

```sh
python3 -B Scripts/documentation_catalog.py --write-readme-examples
python3 -B Scripts/ci.py --lane docs
```

See [documentation tooling](Documentation/DocumentationTooling.md) for outputs,
local previews and coverage policy. Documentation must distinguish released
behavior, development work, measured observations and qualified platform scope.

## Preserve provenance and privacy

Original contributions use Apache-2.0. Retain licenses and modification notices
on adapted files and record adaptations in the
[extraction manifest](Documentation/Architecture/ExtractionManifest.json).
Fixture updates require the complete license, immutable pin, checksum, evaluated
count, parser metadata and reference review. Keep credentials, reference clones,
private application data and generated output outside Git and source archives.

Describe the trigger, resulting behavior, tests run and material limitations in
your pull request. Follow the [community standards](CODE_OF_CONDUCT.md). Use
[private vulnerability reporting](SECURITY.md) for security-sensitive defects.
Publication requires passed release gates and an explicit maintainer request;
see [RELEASING.md](RELEASING.md).
