# Compatibility evidence

Swift-Liquid targets Shopify's open-source Liquid core. The reference is
Shopify/liquid 5.14.0 at commit `4e39ae4cc3da73921923c0669e0fc84a66b2f696`,
with Ruby 4.0.1, Date 3.5.1, and Time 0.4.2. Reference runs use UTC, line numbers,
and each fixture's lax/strict/strict2 metadata.

## Preserved qualification inputs

| Corpus | Cases | What is checked |
| --- | ---: | --- |
| Golden Liquid | 1,098 | Original outputs and language errors, without exclusions |
| Authored compatibility probes | 221 | Scalars, equality, arithmetic, modes, dates, recovery, and control flow |
| Ruby date source-table cases | 337 | Every calendar/time/zone field consumed by Time.parse, with original completion metadata |
| Public date-filter cases | 376 | Both public render APIs with a fixed clock; 35 explicit supported-year boundaries |

Golden Liquid is pinned at `65c2f76ea64ef20647c295b000df5fcd9fc471cd` and
retained byte-for-byte with its MIT license and original README. Its SHA-256 is
`1a0e763de83d8243915bfb54a40e3b24c47b50b3ff29e94f8cf1110a17a86d1e`.
All original 185 authored probes retain their inputs, expectations, and parser
modes. [ConformancePins.json](ConformancePins.json) records every pin and checksum.

The date corpus is extracted from source tables in Ruby Date 3.5.1. The
unchanged source is retained as inert fixture text under its BSD terms; it is
never evaluated as test code. Original lines, expectation text, and true/false
year-completion metadata remain attached to each extracted case. Time.parse
ignores Date's weekday/commercial-week fields and its broader timezone-offset
lookup; the grammar tests check the fields that Time.parse actually consumes.
The separate public corpus checks the resulting filter outputs and UTC behavior.

## Error and boundary accounting

Valid cases require exact UTF-8 output. Invalid cases require a Liquid language
error; cancellation, quotas, unsupported-value failures, and foreign exceptions
cannot qualify them. Error-free fixtures run through both raising and diagnostic
APIs. Recovered-error fixtures require matching output, diagnostic messages,
order, line numbers and partial names, plus a failure from the raising API.

The original Golden Liquid case `filters, reject, first argument is undefined`
is preserved. Ruby records `Liquid::ArgumentError` inside `assign` and suppresses
its text in lax mode. Swift now raises that runtime error; explicit diagnostic
rendering reproduces recovery and retains the diagnostic. A separately pinned
sidecar records the original case's error expectation. Additional authored cases
qualify strict2, output/echo, captures, partials, multiline liquid tags, and loops.
This closes the previous hidden-error discrepancy without rewriting the fixture
or counting a recovered error as an error-free render.

The supported date domain remains calendar years 1…9999, as specified in the
[language contract](Language.md). All 35 date cases outside that domain are
executed and must produce typed operational failures in Swift. Reference receipts
show them separately as `outsideSupportedDomain`; they are neither successful
compatible renders nor skips. The value model remains bounded Int and finite
Double rather than arbitrary-precision Ruby numbers.

## Reproduction

```sh
python3 Scripts/ci.py --lane native
python3 Scripts/ci.py --lane safety
python3 Scripts/ci.py --lane reference --reference-path /path/to/pinned/Shopify-liquid
python3 Scripts/ci.py --lane platforms
```

Reference receipts separate successful renders, parsed grammar cases, expected
language errors, recovered errors, unsupported-domain checks, mismatches, and
reference failures. Every record is retained. Missing fixtures/partials and
foreign exceptions fail qualification. Counts, hashes, errors, toolchain, source
identity and command exits live under ignored Artifacts directories.

All four fixture suites are required in debug, release, and address-sanitized
runs. ThreadSanitizer checks shared engines/templates, invocation-owned scopes,
and concurrent date parsing. The independent consumer uses only public APIs.
CLI checks cover output channels, stdin, partials, diagnostics, and file atomicity.

## Qualification limits

The Ruby recognition pipeline and Time.parse defaults are now implemented in
Swift, including missing date components and embedded fragments. Compatibility
is supported by source review and evaluated cases, not a formal proof over every
possible Liquid program. UTC, bounded values, finite resource policies, and native
Unicode case mapping remain explicit parts of the contract.

Native execution is qualified on macOS with Swift 6.4. Library compilation also
passes against the iOS, tvOS, watchOS, and visionOS simulator SDKs at the declared
deployment minima. Those compile checks do not certify device execution or Linux.

The 1.0.0 release is qualified through all [release gates](ReleasePlan.md),
including a clean archive rebuild at the tagged commit. Qualification and
benchmark receipts accompany the [release](https://github.com/ThorFuchs/Swift-Liquid/releases/tag/1.0.0).
Test counts alone do not establish complete Shopify conformance.
