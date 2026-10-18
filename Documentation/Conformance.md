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

### Host extensions

The 1.1 custom-filter API has 15 separately pinned cases using matching
Ruby/Swift callbacks. Reference receipts retain these under `hostExtensions`;
the existing 2,032 core checks and their accounting remain unchanged. Additional
public tests qualify Swift name validation, value conversion, cumulative budgets,
explicit failure recovery, cancellation and concurrent engine isolation. Those
host policies do not add Shopify core conformance cases. See [custom filters](CustomFilters.md).

### Inspection API

Eight authored inspection cases run in lax, strict and strict2 modes. Additional
public regressions cover exact Unicode ordering/equality, callback nonexecution,
parser errors, source/depth limits, cancellation and concurrent rendering with
inspection. A separate public consumer and CLI checks exercise the released-style
module boundary and versioned JSON. These are Swift API contracts; they add no
Shopify render-conformance cases and change none of the pinned corpora.

### Core and platform boundaries

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

The 1.1.0 release applies the same core accounting and adds separate filter and
inspection qualification, matched 1.0.0 benchmarks and all eight release lanes.
Exact-commit receipts, benchmark review, source inventory and clean archive
rebuilding evidence accompany the
[1.1.0 release](https://github.com/ThorFuchs/Swift-Liquid/releases/tag/1.1.0).
The 1.0.0 tag and assets remain unchanged.

### 1.3 tooling qualification

Bounded [dependency inspection](Dependencies.md) reuses the AST authority and
adds whole-bundle admission, renderer-compatible lookup, missing/dynamic findings,
iterative cycle groups and concurrent render/metrics reuse. Eleven regression
functions and a fifth independent public consumer cover this separate API scope.
The CLI adds 24 cases; published Swift-JSON qualifies six positive and nineteen
negative JSON Schema vectors in isolated tooling. These add no core render cases.
Canonical duplicate filenames cannot coexist on the qualification macOS volume,
so that conditional CLI vector is unavailable rather than counted as passed.
API tests cover exact spellings, equality and canonical lookup independently.

Swift-Liquid 1.3 retains all 116 public 1.2 declarations and every prior fixture
pin. Final gate receipts, source/DocC archives and matched 1.2.0 measurements
accompany the [1.3.0 release](https://github.com/ThorFuchs/Swift-Liquid/releases/tag/1.3.0);
see the [release notes](Releases/1.3.0.md).

## LQ1 independent track

The separate [LQ1 qualification](LQ1/README.md) uses Shopify/liquid-spec at
`84bf25e0edbca5f7e530574788b0f875ab331f50`, alongside the same pinned Ruby source.
Its broader corpus exposes unresolved rendering and parser-diagnostic differences.
The independent lane currently fails; original release inputs and receipts remain
immutable. Eligibility, recovered errors, operational limits and transport
exclusions have separate records. See the [adapter contract](LQ1/ADAPTER_LIMITS.md)
and [mismatch review](LQ1/MISMATCHES.md) before making compatibility claims.

## Reconciled candidate status on 17 October 2026

This historical status is bound to the PF1-002 candidate
`b14d91bde71270fdded001775ed99d0e4d99f65a`, tree
`dd8196c1d57cd364f19707f0cdf2d6a9d79e862a`. Its ordered parents preserve PR19
`8bceeb8f6568a32d49d4290d752eb76ec7e5894d` and main
`1c37b11f1487453772aaae9e6be0cfd75ab2af01`. PR23 remains separate.

The retained independent matrix has SHA-256
`c9b170036ff2cf1eceb0b4c4a36f02d1b5329f8d167aa856bad9340c4ce4a1df`.
Of 5,112 variants, 4,624 are selected and 488 excluded. Qualified outcomes are
2,736 matched, 1,878 mismatched and ten operational errors; raw comparison reports
2,763 matched and 1,861 mismatched. The 27 raw matches rejected by qualification
comprise 25 expected parse errors observed as successful renders and two expected
disabled-include render errors observed as successful renders. Ten reference
qualification concerns remain recorded separately. All ten operational outcomes
report `Limit exceeded: nestingDepth`; these observations do not prove their
precise execution boundary or authorize removing resource limits.

PF1-007 assigns all 1,888 selected failures to 49 groups with original case rows
preserved. Grouping establishes neither root cause nor accepted compatibility
deviations. The nineteen expected-token diagnostic cases remain outstanding;
related source-origin and lexer work does not close that parser presentation
scope. The independent lane remains failed and was not rerun by PF1-007.

Historical non-timing qualification on clean b14 comprises native, safety,
reference, platforms and installation in PF1-002, followed by docs and strict
archive in PF1-003. The original PF1-002 docs failure and archive block remain
part of the record. Installation checks published 1.3.0 at
`9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e`; it does not install this candidate.
Platform compile checks do not certify device, minimum-OS runtime or Linux
execution. A changed successor requires its own exact-source receipts.

Performance remains `HOLD_PERFORMANCE_PENDING_QUIET_WINDOW`. PF1-005 and PF1-006
are terminal; this status creates no new timing window. Exact-source internal
development acceptance, whole-PR acceptance, merge and release remain pending.
Original release fixtures, pins, versions, budgets and provenance limits remain
in force; no complete-core compatibility claim follows from this status.


## Current independent development snapshot (PF1-013)

One unchanged full functional observation on R6 commit
`37feae748de8f3acd4f30f63b1b47e523c4dfabe`, tree
`514557d7aee3835df39a95864d984fbd8ec32add`, completed with a **failed** independent
gate. Its matrix SHA-256 is
`c583ad7892d7f532ad49bb2a93ac73a76d86a249eb6fca0b2239a5a0f673609f`.
Both upstream pins and all fixture/comparator/adapter policies are unchanged.
New normal private checkouts were recovered from the retained pinned objects;
the broken original spec metadata was preserved.

The population remains 5,112 expanded variants, 4,624 selected and 488 excluded.
Qualified outcomes are 2,756 matched, 1,858 mismatched and ten operational errors.
Raw upstream comparison reports 2,783 matches; the 27 raw matches disqualified by
phase/admission policy remain failures. Ten reference concerns are retained.
These counts combine distinct outcomes, not successful render counts.

Against the source-bound historical matrix (`c9b170036ff2cf1eceb0b4c4a36f02d1b5329f8d167aa856bad9340c4ce4a1df`),
20 qualified verdicts improve, including all nineteen R6 identities and one
separate strict lookup case. No qualified match becomes a failure; 5,092 qualified
verdicts stay unchanged, including exclusions. This does not mean identical
observations: 26 diagnostic observations change, including six still-failed lax
lookup cases. Their syntax rejection persists with typed reason/context/location;
this is no lax acceptance-parity claim. Full case joins and original/new rows are
retained externally. Historical 1,888 failures/49 groups are never rewritten or
reduced by arithmetic subtraction.

This records the exact R6 observation, not a new compatibility run on later
policy-only commits. Such a commit needs an explicit unchanged runtime, adapter,
fixture and pin bridge. Maintainer acceptance of the current limitations and
whole integration line remains a separate decision. Performance stays held; no
complete-conformance, release or speedup claim follows.
