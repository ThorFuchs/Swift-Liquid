# Adapter limits and semantic boundary

The adapter is development tooling, qualified on macOS. It imports Foundation,
Darwin and the public Liquid module, with no `@testable` access. Its isolated
SwiftPM path dependency adds nothing to the root dependency graph.

## Wire and lifecycle

Only `initialize`, `compile`, `render` and `quit` are implemented, using newline
JSON-RPC 2.0 and liquid-spec protocol 1.0. Stdout is protocol only. Notifications
have no response. EOF releases state; quit clears the slot and exits. A compile
must precede render. Each compile invalidates the previous slot even on failure;
monotonic IDs never retrieve an older template's state within that process.
The Ruby bridge starts a fresh process after a failed transport exchange, without
retrying the failed case. The final trace records clean process exit.

| Capacity | Admission |
| --- | --- |
| Request frame | 1,048,576 bytes, bounded while reading |
| Active compiled templates | One parsed root and its explicitly supplied partial-source bundle |
| Retained source | 262,144 UTF-8 bytes across root, partial names and partial bodies |
| Partial count | 256 |
| Output and completed intermediate output | 1,048,576 UTF-8 bytes |
| Logical steps / loop iterations / context visits | 1,000,000 / 100,000 / 100,000 per render |
| Syntax/admitted-value depth | 64; public JSON parsing has its separate finite 128-container bound |
| Active rendering depth | 384 under the adapter's standard-profile initializer |
| Context transport depth | 64 |
| Process requests / successful compile IDs | At most 200,000 each |
| Runner exchange deadline | 10 seconds, process termination on timeout; operational stability only |

These bounds limit admitted and retained logical state; they are not an OS-enforced
RSS ceiling, filesystem sandbox or wall-clock rendering guarantee. A caller cannot
ask the adapter to open files or make network requests. The externally supplied
source paths and development gems belong to the driver, not template execution.

## Parse and render policies

Compile parses the root using the declared `lax`, `strict` or `strict2` mode and
admits the complete supplied partial-source map against its source limits.
During rendering, a selected partial is parsed on first use with the root's
syntax mode; an unused invalid partial is not eagerly parsed. Omission preserves
the library default `lax`.
The suite's mode-expansion helper selects highest supported strict mode for
unannotated cases; this test configuration does not change library defaults.
Explicit `warn` variants are retained as unsupported, never silently dropped.
Partial-source admission still charges all supplied names and bodies, including
unused sources. This finite adapter capacity and the selected-name resolver are
hosting policies and must be assessed separately from language semantics.

Render builds a fresh `LiquidEngine(referenceTime:)`. Only
`options.registers.current_time` supplies the invocation clock; it is never added
to assigns. Missing clock uses the suite's fixed 2024-01-01T00:01:58Z reference.
`strict_errors: true` or omission uses raising render; false explicitly uses
`renderWithDiagnostics`. Nonempty diagnostics are recovered-error outcomes,
including when output matches. Unknown options and host registers are rejected explicitly.

Compile Liquid errors use `result.error` with null template ID. Raising render
errors use `result.error` with null output; recovery uses exact output and
`result.errors`. Public line/column information is forwarded where available;
missing locations are not invented. Invalid wire JSON, methods and parameters
use regular JSON-RPC error codes. Quotas and unexpected host failures stay
operational errors, not accepted Liquid language errors or empty output.

## Values, partials and exclusions

Primitive JSON maps directly into typed `LiquidValue`: native signed 64-bit Int on
this host, finite binary Double, ordered string-keyed objects, arrays, booleans,
null and UTF-8 strings. Integer lexemes outside Int are rejected before engine admission. The public
reader may already have decoded one through its documented finite-Double fallback;
that rounded value is never passed to rendering. No arbitrary
Double conversion, Ruby object inspection, model reflection or second engine
interprets values. Decimal/exponent numbers use the declared binary Double domain;
Ruby arbitrary integers, BigDecimal, nonfinite floats, symbols, cycles, binary
strings and runtime objects are not represented faithfully. Preflight records
them as unsupported-by-domain or transport-inapplicable. Template numeric literals
and arithmetic still have the engine's bounded domain; a mismatch is retained
until reviewed, not automatically excluded by a numeric-looking case name.

The adapter's explicit name resolver lowercases requested and supplied names,
adds `.liquid` when absent, and uses case-insensitive comparison to select a
supplied entry. Its missing-name message depends on whether a filesystem map was
supplied. It does not open files, perform ambient lookups or install a default
loader. Ruby's general host error callback and template factories remain
transport-inapplicable. Differences in host naming and loading policy must not be
disguised as core conformance fixes.

[Pins and suite policy](../../Tools/LiquidSpecAdapter/Pins.json) define five suites.
`missing_features` is fully exported in `SPEC_RUNS.json`, with per-row reasons.
Drop callbacks (`drop_get`, `drop_call`, `drop_iterate`) are not advertised; a JSON
marker cannot substitute for a typed host-object interface. Hosted Shopify tags,
filters, objects and policy flags are outside scope. Resource-score fixtures are
unsupported because Ruby scores have no verified Swift quota mapping. There is
no blanket `:core` exclusion. Production recordings and Dawn need a separate
portability review; the benchmark suite is excluded from this wave.

Binary expectation bytes for excluded cases are preserved only in evidence, as
labelled encoding/byte-count/base64/SHA-256 objects. This is report serialization,
not a Liquid value converter. Repeated runs retain previous reports and logs in
a timestamped `history/` directory; stale successful reports cannot qualify a
new failed run.

The broad upstream `ruby_types` tag is reviewed per case, not globally disabled:
primitive-JSON cases remain eligible, including object/array formatting probes.
Actual Ruby classes, symbol keys, cycles and numeric-domain violations receive
specific preflight reasons. `SPEC_RUNS.json.featurePolicies` records this choice;
it does not advertise general Ruby runtime type support.
