# Changelog

## Unreleased

- Adopt the focused 1.1 roadmap and begin typed, engine-scoped custom filters.
- Add immutable Sendable callbacks with positional and ordered named values,
  protected standard names, explicit recoverable failures and cumulative admission.
- Preserve the 1.0 engine initializer, default rendering and pinned core fixtures.
- Add separate host-extension reference cases, public consumers and cancellation,
  admission and concurrent configuration regressions.

## 1.0.0 — 2026-10-14

The first stable release of Swift-Liquid: Shopify Liquid templates in modern
Swift, with a focused public API, a command-line tool, and no SwiftPM dependencies.
Requires Swift tools/compiler 6.4 or later in Swift language mode 6.

### Library and CLI

- One `Liquid` library and one `liquid` executable, extracted from RhoeLiquid
  with retained source attribution and Apache-2.0 licensing. Ruby Date adaptations
  retain their BSD terms; fixture licenses are included.
- Checked Sendable values and engines, immutable reusable templates, ordered
  objects, and invocation-owned rendering state for concurrent use.
- Standard open-source Shopify Liquid tags and filters, lax/strict/strict2 parser
  modes, explicit partials, ordered JSON input, and configurable resource limits.
- Raising rendering and explicit `renderWithDiagnostics` recovery, with error
  order, line numbers, and partial names. Cancellation and operational failures
  remain errors in both APIs.
- Ruby Date/Time recognition and missing-component defaults, deterministic
  reference clocks, fixed offsets, exact parsed decimal fractions, and Liquid
  date formatting.
- CLI rendering and validation, stdin and JSON context support, explicit partial
  directories, diagnostics on stderr, and atomic output-file replacement.
- Compiled DocC API reference and guides, public consumer examples, and documented
  language, error, date, concurrency, and performance contracts.

### Qualification

- All 1,098 pinned Golden Liquid cases preserved without exclusions, plus 221
  authored compatibility probes, 337 Ruby date source-table cases, and 376 public
  date-filter cases.
- The pinned Ruby reference evaluates 2,032 checks: 1,502 successful renders,
  337 parsed grammar cases, 132 expected language errors, 26 recovered errors,
  and 35 explicit supported-year boundary checks. No failures, skips, or reference
  errors are accepted; recovered errors and boundaries are counted separately.
- Debug and release tests, an independent public consumer, CLI behavior checks,
  AddressSanitizer, ThreadSanitizer, and simulator-SDK library compilation.
- Five native release benchmark workloads with output checksums and environment
  receipts. Measurements establish a baseline; no comparative speedup is claimed.
- Reproducible tracked-source archives, a clean extraction rebuilt and tested,
  compiled documentation archives, and SHA-256 checksums.

### Compatibility contract

The target is Shopify's open-source Liquid core, pinned to Liquid 5.14.0, Ruby
4.0.1, Date 3.5.1, and Time 0.4.2. Shopify storefront objects and theme-only tags,
custom tag/filter APIs, Rhoe services, macros, inheritance, and document rendering
are outside this release.

The hosting timezone is UTC; supported calendar years are 1–9999. Values use
bounded `Int` and finite `Double`, with configurable resource budgets and native
Unicode case mapping. These are explicit compatibility boundaries, not proof of
equivalence for every possible Liquid program.

Runtime qualification covers macOS with Swift 6.4. Library compilation covers
the iOS, tvOS, watchOS, and visionOS simulator SDKs at the declared deployment
minimums; device execution and Linux are not qualified by those checks.
