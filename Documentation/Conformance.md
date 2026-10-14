# Compatibility evidence

Swift-Liquid targets the standard open-source Shopify Liquid language. The
reference is Shopify/liquid 5.14.0 at commit
`4e39ae4cc3da73921923c0669e0fc84a66b2f696`.

## Independent corpus

All **1,098** cases from jg-rp/golden-liquid commit
`65c2f76ea64ef20647c295b000df5fcd9fc471cd` are retained byte-for-byte, together
with the MIT license and original corpus README. The corpus SHA-256 is
`1a0e763de83d8243915bfb54a40e3b24c47b50b3ff29e94f8cf1110a17a86d1e`.
[ConformancePins.json](ConformancePins.json) records all pins and counts.

The Swift runner preserves context member order and honors per-case lax, strict,
and strict2 metadata. Valid cases require exact UTF-8 output, including accepted
alternatives. Invalid cases require a Liquid syntax/rendering error. Cancellation,
quota exhaustion, unsupported-value failures, and foreign errors cannot qualify
an invalid fixture. Integrity checks prevent absent or empty suites from passing.

The Swift engine evaluates all 1,098 corpus cases and **185 authored probes**.
The latter include 122 date cases covering input coercion, complete calendar
forms, RFC/asctime, exact decimal fractions, offsets, flags, normalization, and
Gregorian and ISO week boundaries. The original 63 probes retain their inputs,
parser modes, and expectations. They cover Unicode scalar spelling, structural
equality, arithmetic, variables, conditions, and interrupts.

## Reference execution and discovered failure

Reference execution uses Ruby 4.0.1, UTC, line numbers, each fixture's syntax mode,
and a clean checkout at the pinned commit. Run:

```sh
python3 Scripts/ci.py --lane reference --reference-path /path/to/pinned/Shopify-liquid
```

The receipt records each output/error and distinguishes successful renders,
expected Liquid errors, mismatches, and reference failures. Missing fixtures,
missing partials, foreign exceptions, and errors recovered by Ruby's non-raising
renderer do not count as successful renders. The lane exits nonzero on any
reference failure and retains the full receipt under Artifacts/reference.

The 2026-10-14 run evaluated all **1,283** cases: **1,150 successful renders**,
**132 expected errors**, **one reference error**, and **zero skips**. All 185
authored probes passed their reference expectations. The error is the unchanged
Golden Liquid case `filters, reject, first argument is undefined`. Ruby records
`Liquid::ArgumentError` (`cannot select the property ''`) inside `assign`, then
continues with the expected empty output. The previous runner checked only the
output and incorrectly counted this recovered error as a successful render.
That accounting has been corrected; the reference lane currently fails.

Before 1.0, qualify how the Swift public API handles Shopify's recovered filter
errors, with an explicit error/recovery contract and regression evidence. Retain
this fixture and its original metadata; do not hide the error or waive the gate
by changing the expected result.

## Public qualification

Regression tests cover concurrent render isolation, reusable templates, scopes,
integers above 2^53, malformed JSON, finite limits, overflow, cancellation, rejected
extensions, and bounded date failures. An independent consumer uses public APIs.
CLI tests check stdout/stderr, stdin, explicit partials, input errors, and output
failure atomicity.

Debug and release lanes require nonzero reported runs and every fixture. Address
and thread sanitizer lanes retain actual logs. Generated command, compiler,
source-hash and exit receipts live under Artifacts and are excluded from Git.

## Boundaries and remaining 1.0 work

These suites are evidence for evaluated cases, not proof about every Liquid
program. The value model uses bounded Int and finite Double. The
[date guide](Dates.md) records supported complete forms and the remaining heuristic
Time.parse grammar. Native Unicode case mapping and device/Linux qualification
need broader review. See the [language contract](Language.md).

The repository remains at development status. A stable **1.0.0 has not been cut**.
Complete the recovered-error review, compatibility review, and
[release gates](ReleasePlan.md) before making a complete Shopify-conformance or
stable-release claim.
