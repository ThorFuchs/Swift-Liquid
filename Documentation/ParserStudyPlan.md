# Controlled date-parser operation study

Freeze this protocol, suffix, consumer, literal input expectations and driver
before any hosted timing. Use immutable 1.3.0
`9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e`, merged PR #21 main
`e058abb790427cbef51c988297c214d6f8594dc5`, and independently built identical current B. The original
current library fingerprint remains
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.
No production optimization is proposed. Diagnostic CI branches must not be merged.

## Source and executable boundaries

For each version, build the unchanged 1.3.0 common public consumer against original
library sources. Build a second component consumer against a separate archived
copy with a diagnostic suffix appended to RubyDateParser.swift. The original
parser bytes are an exact prefix; every other original library file stays
byte-identical. No existing helper body is edited, no cancellation check is
removed and no dependency is added. Retain original and augmented inventories,
fingerprints, suffix bytes, six binary hashes/UUIDs and three component dSYMs.
The augmentation and extra checked conformances can change code layout; its
absolute costs cannot replace original production measurements.

All six binaries build before timing. Qualify original current A and augmented
current A through Scripts/ci.py development before creating additional consumer
packages or replacing their common harness; retain raw Swift Testing streams.
Validate all 100 component records under both callers and both record orders for
all three component binaries before the first timed run.

DateFragments and RubyDateParser receive compiler-checked diagnostic Sendable
conformances in the suffix. Public diagnostic plans/values are checked Sendable.
A local compiler preflight correctly rejected storing NSTextCheckingResult in a
Sendable plan. The final plan holds immutable NSRange snapshots instead. Match
objects stay local; no unchecked conformance or locking workaround is used.
The final consumer passed all 400 untimed local validations. These local calls
contain no timing loop; no local performance observation is admitted.

## Operations and explicit inputs

Five normalization inputs cover fractional/offset ISO, UTC ISO, RFC, an invalid
short string and a normalization stress string with Unicode/whitespace. The first
four also have literal whole-grammar field expectations. These yield 28 records:
normalization and construction with matching audits for all five; grammar and
field audits for four. There is no grammar record for normalization stress.

Nine matching inputs cover ISO time, time fields, calendar and weekday miss;
RFC weekday, time and calendar; invalid time; and a synthetic non-BMP-prefix
calendar range. Each has match, captures, original find and original take plus
matching audits: 72 records. Total component shape is exactly 100 records.
The non-BMP prefix is an explicit UTF-16 boundary control. Normalization would
remove it; it is not claimed as normal parser post-normalization text. Literal
matched substrings, optional captures, UTF-16 locations/lengths, capture counts
and remaining strings are fixed before timing. The post-consumption RFC strings
preserve spaces; they are not normalized again during preparation.

| Stage | Timed boundary |
| --- | --- |
| normalize | Preselected original immutable normalizer regex, full-source NSRange, replacement, and typed result audit |
| construct | Actual RubyDateParser initializer, including compiled-pattern lookup/normalization, normalized text projection and audit |
| grammar | Actual initializer and complete parse plus field projection and audit |
| match | Original pattern dictionary lookup and firstMatch expression, full-input NSRange, three-integer match span/capture-count projection and audit |
| captures | Precomputed immutable range snapshots, Range validation, String materialization, optional capture array and audit; no match or NSTextCheckingResult range lookup |
| find | Actual private find helper, its dictionary lookup/match/result range access/capture materialization, group projection and audit |
| take | Fresh value copy of prepared parser, actual private take helper, match/capture/removal, remaining text/group projection and audit |
| audit | Non-inlined identity call returning the matching expected typed value, with the same source-level equality/hash code |

Prepared state, regex selection and capture-range snapshots are outside timed
batches. An invocation owns all prepared plans. Actual find/take execute original
helper bodies; match-only reproduces the original guard without materializing
captures. Capture-only isolates materialization from range snapshots rather than
pretending the Foundation result object is Sendable. Take includes copying and
copy-on-write behavior; it is not a pure text-mutation timer.

Non-inlined synchronous bridge calls have no per-call async boundary. Each batch
runs through an explicit @MainActor or @concurrent entry. All outputs, optional
values, fields, matched ranges and remaining strings are checked and hashed inside
the timed loop using a fixed canonical typed payload. Dynamic JSON input and
literal expectations prevent a constant-input source benchmark. Source-level
checks may optimize differently across controls; do not subtract audit values as
exact costs or add these stages into a whole-parser/render latency decomposition.
No pattern-frequency or production call-count claim follows from selected inputs.

## Order, clocks and admission

One finite hosted macOS 27 / Swift 6.4 job builds all six release binaries with
-Xswiftc -g. Three serial blocks run common release ABBA then common identical
ABBA; component release/identical ABBA under each caller follow. Block two reverses
component caller order. Component record order alternates forward/reverse by
position and reverses in block two; every version has one of each per block.

Common policy stays unchanged: ten warmups, 25 samples, 100 repetitions. Its 24
runs produce 624 raw records and 52 comparisons. Component policy is ten warmups,
25 samples, 500 repetitions. Its 48 runs produce 4,800 raw records and 800
comparisons across wall and process CPU. Total: 72 runs, 5,424 raw records and 852
comparison rows. Retain every observation; no timing-driven retry, discard or
normalization. Stop on failed execution or admission and retain the failure.

ContinuousClock and getrusage(RUSAGE_SELF) user+system bracket synchronous batches.
CPU is whole-process accounting with microsecond granularity, including audit,
clock work and runtime threads; it is not exclusive parser CPU. CPU minus wall is
not wait time. Retain/count zero individual CPU samples, require a positive
median for ratios. Each sample/p95 describes batch averages per call, not an
individual-call latency tail. Preparation and warmups consume regex initialization;
no cold-start claim. Physical-host contention, thermal/frequency state and idle
isolation are unknown; guest loads do not resolve these limits.

Independently admit every original/suffixed source inventory, binary/dSYM UUID,
probe/input hash, command argument/order, typed payload/checksum, raw sample
summary, six-run median, block effect, MAD/range and both 10% flag lists. Keep all
median and spread flags in the public aggregate appendix, including adverse
controls and identical-source effects. The study can locate observed operation
costs without identifying the cause of historical date-rendering flags, proving
equivalence or adopting a speedup. Cancellation correctness remains separately
qualified by unchanged tests/source; uncancelled timings do not measure response.
