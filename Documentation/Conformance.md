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

The runner preserves context member order and honors per-case lax, strict, and
strict2 metadata. Valid cases require the expected output, including accepted
alternative outputs. Invalid cases require an error. Cancellation is not treated
as an expected syntax error. Fixture integrity checks prevent absent or empty
suites from passing unnoticed.

Both the Swift engine and the pinned Ruby reference evaluated all 1,098 cases
successfully on 2026-10-14, with no exclusions or skips. Reference execution uses
Ruby 4.0.1, UTC, line numbers enabled, and per-case syntax modes. Reproduce it with:

```sh
ruby -I /path/to/pinned/Shopify-liquid/lib Scripts/check_reference.rb reference.json
```

## Additional qualification

The separate authored compatibility corpus contains **63 reference-checked
cases** covering code points, canonically equivalent keys, equality and uniq,
negative arithmetic, variable names, condition modes, interrupts, numeric string
coercion, and date directives/offsets. These fixtures are original Apache-2.0 test
inputs whose expectations were obtained from the pinned Shopify implementation.

Public regression tests cover concurrent render isolation, reusable templates,
scope boundaries, literal integers above 2^53, malformed JSON, finite limits,
overflow, cancellation, and rejected platform extensions. The independent consumer
uses public APIs only. CLI tests check stdout/stderr, stdin, explicit partials,
input errors, and output-file failure atomicity.

Debug and release lanes require nonzero reported runs and every fixture. Address
and thread sanitizer lanes retain their actual logs. Generated command, compiler,
source-hash and exit receipts live under Artifacts and are excluded from Git.

## Boundaries and remaining 1.0 work

Passing these suites establishes compatibility for the evaluated cases, not a
proof about every Liquid program. The current value model uses bounded Int and
finite Double. Date parsing accepts ISO and common calendar formats; Ruby's full
permissive Time.parse grammar is not yet reproduced. Native Unicode case mapping
and additional device/Linux qualification need broader review. These boundaries
are explicit in the [language contract](Language.md).

The repository remains at development status. A stable **1.0.0 has not been cut**;
complete the compatibility review and [release gates](ReleasePlan.md) before
making a complete Shopify-conformance or stable-release claim.
