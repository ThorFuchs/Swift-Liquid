# Date-parser normalization, matching and captures

For the selected time-pattern inputs, matching observes more process CPU than
capture materialization from saved ranges. Fractional ISO matching is
2.787/2.565 microseconds under actor/concurrent callers, versus 0.422/0.391 for
capture materialization; ISO normalization is 1.033/0.960 microseconds. RFC
normalization is 2.763/2.505 microseconds. These locate useful next investigation
targets while retaining substantial variability: all 852 comparisons have spread
flags, including identical-source controls. No production optimization is adopted.

The production engine, public APIs, checked Sendable inputs, invocation-owned
state, cancellation checkpoints, budgets, fixture bytes and root dependency graph
remain unchanged. These are observed operation costs on a small fixed input
matrix, with explicit adapters and auditing.

## Qualification and immutable sources

[PR #21](https://github.com/ThorFuchs/Swift-Liquid/pull/21) merged as
`e058abb790427cbef51c988297c214d6f8594dc5` after all nine CI lanes passed.
Independent admission checked every source hash in its 204-file inventory, raw
debug/release/AddressSanitizer streams (81 functions / 2,178 cases each), repeated
adversarial/cancellation profiles, ThreadSanitizer, consumers, CLI, separate
reference outcomes, four compile-only SDK builds and clean source archive bytes
and checksums. The public baseline remains 126 declarations. Canonical-filename
behavior unavailable on the qualification filesystem remains separate from passed
CLI vectors. Neither test counts nor simulator compilation establish complete
conformance or device execution.

Its bound comparison SHA-256 is
`819de4959d9f6bc224ba88e6e1af7b2f44525c18d1a007f55b593bc645617109`.
All 50 rows were recomputed and reviewed: zero median flags in either phase,
24 common spread flags and 23 metrics spread flags. Ordinary date source
+1.055% and reuse +0.867% have mixed blocks. These quieter observations do not
clear historical date flags or prove equivalence or a speedup.

The [fresh merged-main run](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38941215638)
also passed all nine lanes and Pages. Independent admission checked the same
204-file inventory, raw test streams, archive bytes/checksums and public contracts;
its benchmark review remains separate from the PR comparison.

Fresh-main comparison SHA-256 is
`fafcfcb4ce87dfda4117008b77b690ac30e4d6946c8a4081720c0f0e29c184e8`.
All 50 rows were independently recomputed and reviewed: two common median flags,
26 common spread flags, three metrics median flags and 24 metrics spread flags.
Common measured date source is +10.181% (blocks +17.68/+1.22/+6.75); ordinary
interpolation reuse is +10.436% with mixed blocks. Metrics date reuse −10.895%
and loop source −12.624% have negative blocks throughout; diagnostic interpolation
reuse +14.922% has mixed blocks. These opt-in observations do not establish a
speedup or zero overhead. Ordinary date source −1.705% and reuse +2.627% have
mixed blocks; measured reuse is +9.864% with positive blocks below the threshold.
All adverse observations and historical date flags remain open.

The immutable baseline remains 1.3.0
`9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e`; current A and independently built
current B use the merged revision above. Their original library fingerprint is
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.
The original RubyDateParser.swift bytes remain identical between these versions.

## Frozen operation boundaries

The [protocol](https://github.com/ThorFuchs/Swift-Liquid/blob/3946d4e744732046bb952cd85c9a56bee07b57e6/Documentation/ParserStudyPlan.md),
[driver](https://github.com/ThorFuchs/Swift-Liquid/blob/3946d4e744732046bb952cd85c9a56bee07b57e6/Scripts/hosted_parser_study.py),
[suffix](https://github.com/ThorFuchs/Swift-Liquid/blob/3946d4e744732046bb952cd85c9a56bee07b57e6/Tools/ParserCostStudy/ParserCostSuffix.swift),
[consumer](https://github.com/ThorFuchs/Swift-Liquid/blob/3946d4e744732046bb952cd85c9a56bee07b57e6/Tools/ParserCostStudy/ParserProbe.swift)
and [literal expectations](https://github.com/ThorFuchs/Swift-Liquid/blob/3946d4e744732046bb952cd85c9a56bee07b57e6/Tools/ParserCostStudy/inputs.json)
were frozen before hosted timing. The diagnostic branch replaces CI solely for
this finite experiment and must not be merged.

For each version, the unchanged 1.3.0 common harness links original library sources.
A separate component consumer links an archived copy with a diagnostic suffix
appended to RubyDateParser.swift. Every original parser byte is preserved as an
exact prefix; every other original library file stays byte-identical. The suffix
adds accessors and compiler-checked diagnostic Sendable conformances. It does not
edit an original helper body or remove a cancellation checkpoint. Module code
layout and optimization can change, so augmented absolute costs cannot replace
original production measurements.

A local compiler preflight rejected storing Foundation's non-Sendable
NSTextCheckingResult in a Sendable plan. The final plan retains immutable NSRange
snapshots instead; Foundation match objects remain local. No unchecked conformance,
lock or dependency was introduced. The checked consumer passed 400 untimed local
validations. No local timing observation is admitted.

The [complete hosted run](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38941424336)
passed. Independent admission verified the downloaded ZIP digest, all 290 retained
file hashes, six executable hashes/UUIDs and three matching component dSYMs,
original and exact-prefix/suffix source inventories, all twelve untimed validations,
all 72 command arguments/order, all 5,424 raw records / 852 comparisons, literal
typed checksums, raw sample summaries, six-run distributions, block effects and
both flag lists. All 120,000 component CPU samples are retained; none is zero.
Original and augmented current development streams separately admit 81 functions
and 2,178 cases. No hosted run failed or measured observation was discarded.

The host reports macOS 27.0.1 arm64, Swift 6.4 `swiftlang-6.4.0.34.1`, three
virtual Apple M1 CPUs and 7 GiB memory. One-minute guest loads before runs range
from 1.478 to 2.828; this does not establish physical-host isolation.

- Study JSON SHA-256: `b4252ca2afeea4002d0c80c83e9fdc9ce8bf0c603d1217d961cbce29d5bbf05a`.
- Artifact: `liquid-parser-operation-study`, ID `12064780032`.
- Verified ZIP SHA-256: `0e2638d1ef309f2e0989112e5666e3adf5458b4a782c8f78513aaa042380c025`.
- Augmented baseline library SHA-256:
  `d7c2c4a2f319f8c8d57c4a1e54b2b25a305df35aa25ea6019ebc249d0b4c46cf`.
- Augmented current A/B library SHA-256:
  `55fa7d835d4f19194175865e66ab1f3813d0f6abc330a7699eb6f37e8e14875b`.

The augmented fingerprints include exactly the appended suffix. Original baseline
library SHA-256 is `36c7d4e63db626aa3e85e91bc847cd8237f33b523c4703d8d9efc0fc17d974a3`;
current A/B retain the original production fingerprint above. All six release
binaries use `-Xswiftc -g` and build before timing; both source qualifications and
all hosted untimed validations precede measurements.

| Stage | Timed scope |
| --- | --- |
| normalize | Preselected original normalizer regex, full-source NSRange, replacement and normalized text audit |
| construct | Actual RubyDateParser initializer, including compiled-pattern lookup/normalization, text projection and audit |
| grammar | Actual initializer and complete parse, field projection and audit |
| match | Original dictionary lookup/firstMatch expression and full-input NSRange, match location/length/group-count array projection and audit |
| captures | Precomputed range snapshots, Range validation, optional String/array materialization and audit; excludes matching and Foundation result range access |
| find | Actual original private find helper, including lookup/matching/result range access/capture materialization, group projection and audit |
| take | Fresh copy of prepared parser, actual original private take, remaining text/group projection and audit; includes copy-on-write behavior |
| audit | Non-inlined identity call returning the matching expected typed value, with the same source-level checking/hash |

Prepared plans, regex selection and capture-range snapshots are outside timing.
The original find/take helpers remain combined operations. Match-only reproduces
the original guard without materializing captures; capture-only isolates range
snapshot materialization. Take is not a pure text-mutation timer. Output adapters
and allocation patterns differ, and controls can optimize differently. Do not
subtract audits, add stages or infer an exact fraction of whole-parser/render
latency. The selected pattern inputs do not establish production call frequencies.

Five normalization inputs cover fractional/offset ISO, UTC ISO, RFC, an invalid
short string and Unicode/whitespace stress. Four have complete grammar field
expectations; stress has no grammar record by explicit shape. Nine matching
inputs cover ISO time/time-fields/calendar/weekday miss, RFC weekday/time/calendar,
invalid time and a synthetic non-BMP-prefix calendar range. Their matched text,
optional captures, UTF-16 locations/lengths/group counts and remaining text are
fixed and checked. Post-consumption RFC spaces are preserved without normalizing
again. The non-BMP input is a range-boundary control: normalization would remove
its prefix, so it is not normal post-normalization parser text.

## Sampling and admission

Three serial blocks run common release and identical-source ABBA, followed by
component release and identical-source ABBA under both callers. Block two reverses
component caller order. Component record order alternates forward/reverse and
inverts in block two; every version has one of each order per block. All six
binaries and all untimed validations precede timing, with no intervening builds.

Common policy stays at ten warmups, 25 samples and 100 repetitions; 24 runs yield
624 raw records and 52 comparisons. Components retain ten warmups, 25 samples and
500 repetitions; 48 runs yield 4,800 raw records and 800 wall/CPU comparisons.
Totals are 72 runs, 5,424 raw records and 852 comparisons. No timing-driven retry,
trimming or normalization of version effects is admitted.

Each sample is a batch average per call; p95 is not an individual-call latency
tail. ContinuousClock and getrusage(RUSAGE_SELF) user+system bracket batches.
CPU is whole-process accounting with microsecond granularity, including audit,
clock work and other process threads. It is not exclusive parser CPU, and CPU
minus wall is not wait time. Zero individual CPU samples are retained and counted;
a positive median is required for ratios. Regex preparation and warmups exclude
cold-start claims. Non-inlined synchronous calls add no per-call async boundary
inside explicit Main Actor/concurrent batch entries. Caller phases run serially.
Uncancelled timings do not measure cancellation response; correctness remains
separately qualified. Physical-host contention, frequency and thermal state are
unknown; guest load observations do not establish isolation.

## Current component CPU observations

Values are microseconds per audited call, each the median of six run medians from the release phases. Actor/concurrent columns remain separate. Audit is the matching expected-value control; it is not subtracted. These scopes are not additive and the capture snapshot boundary excludes Foundation result range access.

| Input / stage | Actor CPU µs | Actor audit µs | Concurrent CPU µs | Concurrent audit µs |
| --- | ---: | ---: | ---: | ---: |
| iso-fraction-offset / normalize | 1.033 | 0.124 | 0.960 | 0.116 |
| iso-fraction-offset / construct | 1.090 | 0.121 | 1.001 | 0.120 |
| iso-fraction-offset / grammar | 14.378 | 0.329 | 13.309 | 0.300 |
| iso-utc / normalize | 0.894 | 0.097 | 0.787 | 0.088 |
| iso-utc / construct | 0.959 | 0.095 | 0.861 | 0.090 |
| iso-utc / grammar | 13.976 | 0.238 | 12.676 | 0.228 |
| rfc / normalize | 2.763 | 0.119 | 2.505 | 0.110 |
| rfc / construct | 2.846 | 0.116 | 2.517 | 0.114 |
| rfc / grammar | 10.772 | 0.265 | 9.723 | 0.246 |
| invalid / normalize | 1.406 | 0.081 | 1.196 | 0.068 |
| invalid / construct | 1.465 | 0.073 | 1.271 | 0.071 |
| invalid / grammar | 14.563 | 0.125 | 12.821 | 0.119 |
| normalization-stress / normalize | 1.882 | 0.097 | 1.577 | 0.084 |
| normalization-stress / construct | 2.048 | 0.088 | 1.676 | 0.087 |
| iso-time / match | 2.787 | 0.082 | 2.565 | 0.076 |
| iso-time / captures | 0.422 | 0.153 | 0.391 | 0.148 |
| iso-time / find | 3.158 | 0.155 | 2.901 | 0.149 |
| iso-time / take | 3.382 | 0.193 | 3.098 | 0.178 |
| iso-time-fields / match | 0.893 | 0.077 | 0.820 | 0.076 |
| iso-time-fields / captures | 0.434 | 0.150 | 0.426 | 0.148 |
| iso-time-fields / find | 1.313 | 0.153 | 1.185 | 0.148 |
| iso-time-fields / take | 1.505 | 0.165 | 1.364 | 0.160 |
| iso-calendar / match | 0.760 | 0.077 | 0.666 | 0.076 |
| iso-calendar / captures | 0.318 | 0.116 | 0.307 | 0.114 |
| iso-calendar / find | 0.989 | 0.116 | 0.900 | 0.114 |
| iso-calendar / take | 1.149 | 0.136 | 1.021 | 0.136 |
| iso-weekday-miss / match | 0.529 | 0.056 | 0.520 | 0.058 |
| iso-weekday-miss / captures | 0.054 | 0.056 | 0.054 | 0.058 |
| iso-weekday-miss / find | 0.527 | 0.057 | 0.513 | 0.058 |
| iso-weekday-miss / take | 0.629 | 0.120 | 0.615 | 0.119 |
| rfc-weekday / match | 0.677 | 0.077 | 0.631 | 0.076 |
| rfc-weekday / captures | 0.211 | 0.081 | 0.206 | 0.080 |
| rfc-weekday / find | 0.851 | 0.079 | 0.764 | 0.081 |
| rfc-weekday / take | 1.037 | 0.129 | 1.004 | 0.130 |
| rfc-time / match | 2.353 | 0.077 | 2.283 | 0.076 |
| rfc-time / captures | 0.293 | 0.114 | 0.298 | 0.116 |
| rfc-time / find | 2.522 | 0.114 | 2.512 | 0.119 |
| rfc-time / take | 2.759 | 0.146 | 2.764 | 0.148 |
| rfc-calendar / match | 1.030 | 0.074 | 1.020 | 0.076 |
| rfc-calendar / captures | 0.320 | 0.116 | 0.323 | 0.116 |
| rfc-calendar / find | 1.278 | 0.115 | 1.264 | 0.116 |
| rfc-calendar / take | 1.444 | 0.138 | 1.405 | 0.142 |
| invalid-time / match | 0.340 | 0.054 | 0.341 | 0.060 |
| invalid-time / captures | 0.052 | 0.054 | 0.054 | 0.058 |
| invalid-time / find | 0.338 | 0.054 | 0.338 | 0.060 |
| invalid-time / take | 0.385 | 0.068 | 0.381 | 0.077 |
| utf16-calendar / match | 0.812 | 0.074 | 0.788 | 0.076 |
| utf16-calendar / captures | 0.354 | 0.112 | 0.358 | 0.116 |
| utf16-calendar / find | 1.087 | 0.116 | 1.110 | 0.118 |
| utf16-calendar / take | 1.309 | 0.138 | 1.301 | 0.138 |

For fractional ISO, preselected normalization is observed at 1.033 µs actor and
0.960 µs concurrent, and actual construction at 1.090/1.001 µs. The corresponding
text-audit controls are approximately 0.12 µs. Complete grammar remains
14.378/13.309 µs. RFC normalization is larger at 2.763/2.505 µs, against
0.119/0.110 µs audits. These are different inputs and scopes; neither subtraction
nor a percentage of complete grammar time is justified.

The ISO time-pattern match observes 2.787/2.565 µs, versus 0.422/0.391 µs for
capture materialization from precomputed ranges. Actual original find observes
3.158/2.901 µs and take 3.382/3.098 µs. RFC time shows 2.353/2.283 µs matching
and 0.293/0.298 µs captures. This makes matching and input normalization useful
next investigation targets before a capture-only rewrite for these inputs. It
does not isolate exclusive ICU search time: matching includes dictionary lookup,
NSRange, result/span projection and auditing; capture-only excludes Foundation
result range lookup. Take additionally includes copying and string mutation.

Misses still perform matching: the ISO weekday miss is 0.529/0.520 µs and invalid
time miss 0.340/0.341 µs. Their capture-only paths return the empty result, observing
roughly the audit floor; they do not materialize a successful capture list. The
invalid string's whole grammar remains 14.563/12.821 µs. A single failed pattern
does not explain the ordered parser's full rejection cost. No production pattern
frequency or additive cost decomposition follows.

The wide spreads remain material. In current A's release phases, ISO time matching
run medians range 2.548–3.430 µs actor and 2.550–3.288 µs concurrent; capture ranges
are 0.376–0.482 and 0.384–0.472 µs. The observed scale separation for this case is
visible across those runs, while precise version percentages remain uncertain.
Actor and concurrent phases are serial and their output adapters differ by stage;
the lower concurrent medians are not an executor-overhead measurement.

## Complete flag review

The [aggregate appendix](PerformanceReview-ParserOperations-Data.md) records every row, both sides, all three block effects, MAD, ranges and flags. The following counts cover both clocks and all controls; no flagged row is omitted.

| Phase | Rows | Median flags (+/−) | Spread flags |
| --- | ---: | ---: | ---: |
| release-common-ordinary | 26 | 6 (6/0) | 26 |
| identical-common-ordinary | 26 | 1 (1/0) | 26 |
| release-component-actor | 200 | 22 (22/0) | 200 |
| identical-component-actor | 200 | 67 (0/67) | 200 |
| release-component-concurrent | 200 | 2 (0/2) | 200 |
| identical-component-concurrent | 200 | 9 (9/0) | 200 |

Total: 107 median flags and 852 spread flags across 852 comparisons. Their interpretation is discussed below.

All 852 rows have a spread flag; all 107 median flags are retained. The public
appendix records every row's medians, three block effects, MAD, ranges and flags.
The following review accounts for all seven common and 100 component median flags.

Common release has six positive median flags. Filter source +28.376%, measured
interpolation source +12.745% and loop source +10.192% have mixed blocks. Measured
filter source +16.189%, interpolation reuse +11.797% and partial source +13.021%
have positive blocks throughout. Identical-source measured interpolation reuse
is +12.927%, also positive in every block. Ordinary date source +4.239% and reuse
+6.912% have mixed blocks; both measured date modes are below the median threshold
and also mixed. None clears prior adverse date or filter observations.

The component median flags break down as follows. Each count includes both clocks
when both are flagged; “audit” rows remain separate from their operations. Release
actor flags are all positive, identical actor all negative, release concurrent
all negative and identical concurrent all positive.

| Stage | Release actor + | Identical actor − | Release concurrent − | Identical concurrent + |
| --- | ---: | ---: | ---: | ---: |
| normalize | 4 | 0 | 0 | 2 |
| construct | 4 | 2 | 2 | 3 |
| grammar | 2 | 2 | 0 | 2 |
| match | 2 | 10 | 0 | 0 |
| captures | 1 | 5 | 0 | 0 |
| find | 2 | 16 | 0 | 0 |
| take | 2 | 14 | 0 | 0 |
| normalize audit | 3 | 1 | 0 | 2 |
| match audit | 0 | 1 | 0 | 0 |
| captures audit | 0 | 6 | 0 | 0 |
| find audit | 0 | 4 | 0 | 0 |
| take audit | 2 | 6 | 0 | 0 |
| Total | 22 | 67 | 2 | 9 |

Actor release includes 17 operation and five audit flags: invalid normalization,
construction and grammar; stress normalization/construction; ISO calendar matching
and take; ISO time captures; RFC weekday find; and the corresponding flagged audit
records. Seventeen flags have strictly positive blocks; five have mixed or
zero-containing blocks. Invalid grammar is +13.322% CPU/+13.360% wall with positive
blocks, and invalid normalization +16.584%/+16.471% is also positive throughout.
Stress construction +19.208% CPU/+18.950% wall and ISO time captures +10.183% CPU
have mixed blocks. The latter's wall row is below the median threshold; both are
retained. Stress normalization-audit CPU has a zero-change block.

Identical actor has 49 operation and 18 audit flags, all negative. Fifty-seven
have strictly negative blocks and ten have mixed or zero-containing blocks.
They span construction, grammar, matching, captures, find, take and audits as
listed above; they are not a speedup. For example, ISO time find is −13.777% CPU
and −13.702% wall with negative blocks throughout, despite identical source.
Invalid construction has mixed blocks, and invalid grammar CPU has a small
positive first block. These controls prevent treating actor release flags as a
stable normalization/capture regression merely because its helpers are unchanged.

Concurrent release has only RFC construction's two negative median flags:
−10.745% CPU/−10.778% wall. Both reverse direction in block three
(+26.66%/+28.60%). Concurrent identical has seven operation and two audit positive
flags: invalid construction wall, RFC normalization/construction/grammar under
both clocks, and RFC normalization audits under both clocks. Only invalid
construction wall is positive in every block; the eight RFC flags have mixed
blocks. RFC normalization is +21.555% CPU/+23.399% wall and grammar
+12.983%/+13.222% despite identical source. Do not normalize the release result
using these controls or treat the quieter concurrent release matrix as equivalence.

All spread flags remain relevant even below the median threshold. Identical actor
ISO time-fields matching CPU reaches a 198.549% six-run range; concurrent release
synthetic UTF-16 find wall reaches 243.473%. Small MADs do not erase distant runs:
concurrent release ISO time take CPU has relative MAD 0.646% but a run-median range
from 3.072 to 5.490 µs. The cohorts retain those observations without trimming,
retiming, imputing scheduler causes or promoting a selected fast observation.

## Decision and remaining uncertainty

Keep production code unchanged. The isolated calls make ordered matching and
normalization the next focused investigation targets for these inputs; capture
materialization from saved ranges is smaller in the time-pattern cases. A future
candidate needs a predeclared adoption criterion, complete original semantics,
unchanged cancellation/budget evidence and matched qualification under both callers.
Preserve the parser's recognition order, optional captures, Unicode boundaries,
field rotations and fallback behavior when evaluating any change.

This study does not identify a stable causal cross-version date-parser regression.
Every comparison has observed spread, and identical-source controls contain
material changes in both directions. Historical +12.005%/+11.9367% date flags,
the earlier fresh-main +13.999%/+12.711% observations, current measured date-source
+10.181%, and the prior adverse concurrent filter-reuse controls remain unresolved.
There is no speedup, equivalence, cold-start, memory or release-performance claim,
and no production API, dependency, cache, execution annotation or checkpoint change.

Raw records, validation receipts, exact commands, sources, symbols and checksums
remain outside Git and in the 30-day Actions artifact. The immutable protocol and
complete public aggregate appendix preserve the workload boundaries and every
review flag. No runtime optimization or release follows from mechanical success.
