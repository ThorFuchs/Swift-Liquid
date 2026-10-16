# Controlled date-recognition CPU costs

Loose-parser construction and parsing account for the largest observed component
CPU costs in this small input matrix. Fractional ISO full recognition measures
15.243/15.618 microseconds under actor/concurrent callers; grammar construction
and parsing measure 14.199/14.125 microseconds, versus 2.157/2.146 for formatting.
These audited component calls identify a next investigation target while leaving
the historical cross-version date regression unresolved.

The production engine, cancellation checkpoints, root dependency graph, public
execution annotations, API baseline and pinned fixtures remain unchanged.

## Qualification and source identity

[PR #20](https://github.com/ThorFuchs/Swift-Liquid/pull/20) merged as `1ae8df16c6cc02caba75f83d6a46ea52f74a7d56` after all nine gates
passed. The [fresh merged-main run](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38930464473)
also passed all nine gates and Pages. Independent admission checked its 202-file
inventory, raw debug/release/AddressSanitizer streams (81 functions and 2,178
parameter cases each), parallel repeats, ThreadSanitizer, consumers, CLI,
reference outcomes, four compile-only SDK gates and clean archive bytes/checksums.
The public baseline remains 126 declarations. Unavailable canonical-filename
behavior is separate from passed CLI vectors. Test counts are not a complete
conformance claim, and simulator compilation is not device execution.

Its comparison SHA-256 is
`ab19eb2c928aa27fa85e120e21cba2b7b4237e65141f3cc8ece833622cde6826`.
All 50 rows and flags were recomputed and reviewed: nine common median flags,
26 common spread flags, zero metrics median flags and 24 metrics spread flags.
Ordinary date source +13.999% and reuse +12.711% have positive blocks throughout;
retain them alongside the earlier +12.005%/+11.9367% observations. The other common
flags cover interpolation source, all four loop modes, partial source and measured
partial reuse (the last has mixed blocks). Passing mechanical gates does not clear
these adverse observations or identify their cause.

The immutable baseline is 1.3.0
`9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e`. Current A and independently built
current B use the merged revision above and original library fingerprint
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.
`DateParsing.swift`, `RubyDateParser.swift`, `DateFormatting.swift` and
`Renderer+FilterHelpers.swift` remain byte-identical between these versions.

## Frozen diagnostic boundaries

The [corrected frozen protocol](https://github.com/ThorFuchs/Swift-Liquid/blob/c2f9e5cd1ef2df7cab7800043b2e8dfd8807aebe/Documentation/RecognitionStudyPlan.md),
[driver](https://github.com/ThorFuchs/Swift-Liquid/blob/c2f9e5cd1ef2df7cab7800043b2e8dfd8807aebe/Scripts/hosted_recognition_study.py),
[bridge](https://github.com/ThorFuchs/Swift-Liquid/blob/c2f9e5cd1ef2df7cab7800043b2e8dfd8807aebe/Tools/DateRecognitionStudy/LibraryBridge.swift),
[consumer](https://github.com/ThorFuchs/Swift-Liquid/blob/c2f9e5cd1ef2df7cab7800043b2e8dfd8807aebe/Tools/DateRecognitionStudy/RecognitionProbe.swift)
and [input expectations](https://github.com/ThorFuchs/Swift-Liquid/blob/c2f9e5cd1ef2df7cab7800043b2e8dfd8807aebe/Tools/DateRecognitionStudy/inputs.json)
precede timing. Its branch replaces CI for the experiment and must not be merged.

The [first attempt](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38932664709)
built the three baseline binaries, then rejected a valid binary because an
admission assertion searched mangled symbols for a source-level enum name. The
retained table demangles to all seven required methods. No timing run occurred.
The correction changes only that admission check and records the failed setup;
inputs, bridge, consumer, clocks, ordering and sampling remain fixed. It selects
no observed timing result.

The [second attempt](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38933540759)
qualified both source copies, built all nine binaries and passed all twelve
untimed component validations. Eight common-harness runs completed before the
first public probe rejected reversed driver arguments. Preserve these eight
observations as an incomplete cohort; they have no complete three-block
comparison and are not merged with the final experiment. The second correction
changes only public command construction after checking all three argument
contracts. Inputs, bridge/probe bytes, flags, clocks and sample/order policies
remain unchanged. Neither correction selects a favorable timing result.

For each version, the common harness and prior public wall/CPU probe link original
library sources. A third executable links an isolated copy with one additional
diagnostic bridge file; every original library file remains byte-identical.
This bridge is not a production API. Non-inlined synchronous methods expose
checked-Sendable snapshots across the module boundary. Augmentation changes the
compiled module; its absolute times cannot be substituted for production times.

The original current library and augmented current A each passed the development
lane through `Scripts/ci.py` before timing. All nine release executables build
before measurements, with `-Xswiftc -g`. Hosted untimed validation checks every
component record under both callers and both orders for all three versions.
Executables, source inventories, original/augmented fingerprints, compiler flags,
UUIDs, symbols and exact commands are retained. No package dependency is added.

| Stage | Timed scope |
| --- | --- |
| Lowercase | Source lowercasing and string checking/hashing |
| Recognition | `parseLiquidDate` on pre-lowercased input and fixed reference time, including its guards, grammar, defaults, validation and cancellation checks, plus snapshot checking/hashing |
| Grammar | `RubyDateParser` construction/normalization and parse, plus field-snapshot checking/hashing |
| Format | Known-date construction/validation, a fresh invocation-owned budget, `renderStrftime`, and output/seven-step checking/hashing |
| Audit controls | Return the corresponding expected typed value through a non-inlined method and run the same source-level checks/hash |

Inputs are fractional/offset ISO, UTC ISO, an RFC date, an unrecognized string and
a 129-byte guard. Three have known dates/formatted outputs; the invalid string has
an empty grammar result; the guard is tested at recognition admission. The exact
shape is 29 records, with no grammar/format record for the guard and no format
record for the invalid string. These are explicit benchmark shapes, not exclusions
counted as successful renders. The fixtures and reference suite remain separate.
The component clock is fixed and lowercasing is separate. Public source/parsed
rendering still includes the ordinary engine's admission and async execution.

Audit controls help expose measurement work. Optimizer effects and adapters may
differ; do not subtract them as an exact function cost. Recognition contains the
grammar stage, and output representations have different checking costs. Do not
sum stages, divide by ordinary render time, or normalize a version effect using
an identical-source control. No cancellation checkpoint is removed.
These uncancelled timing runs do not measure cancellation response; correctness
is covered separately by the unchanged deterministic tests and source-bound gates.

## Sampling and retained observations

The [complete hosted run](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38935415178)
passed. Independent admission verified the downloaded ZIP digest, all 399 retained
file hashes, nine executable UUIDs/hashes and three matching component dSYMs,
original/augmented source inventories, all twelve untimed validations, exact
commands and order, all 120 runs / 2,736 raw records / 404 comparisons, literal
typed payload checksums, raw sample summaries, six-run distributions and both
flag lists. All 34,800 component CPU samples are retained; none is zero.
Both original and augmented current development streams separately admit 81
functions and 2,178 cases. No failed attempt is counted in these totals.

The host reports macOS 27.0.1 arm64, Apple Swift 6.4
`swiftlang-6.4.0.34.1`, three virtual Apple M1 CPUs and 7 GiB memory. Recorded
one-minute guest loads before runs range from 1.355 to 2.257; these do not
establish physical-host isolation.

- Study JSON SHA-256: `fff780836fdf358dc0dd5d1624bd9c3b5b373d3d8b514ccf077a1bef9c882003`.
- Artifact: `liquid-date-recognition-study`, ID `12060963909`.
- Verified ZIP SHA-256: `f85ce87253014aaca6d55629a4ebf601c1d2ad17f22f2c1b3b5324b57426bd36`.
- Augmented baseline library SHA-256:
  `ad146824854b46f5e1bbffbb2bd90656e7cc0042979f5e1940841c5288703d74`.
- Augmented current A/B library SHA-256:
  `c803f631ae3ce080952963b1178c3ed44feb7f4d34208abb69076ac7e5bf841d`.

Augmented hashes include exactly the bridge addition; original baseline library
SHA-256 is `36c7d4e63db626aa3e85e91bc847cd8237f33b523c4703d8d9efc0fc17d974a3`.
All original files match their immutable version; current A/B's original
fingerprint is the production fingerprint recorded above.

Three serial blocks retain the original 72 common/public runs with unchanged
25-sample, ten-warmup, 100-repetition policies. Components add 48 runs with 25
samples, ten warmups and 500 repetitions. Each version has one forward and one
reverse component record order per block; the second block reverses component
caller phase order. Release and identical-source comparisons each have six runs
per side. All nine binaries and validation receipts precede the first timing.

Each sample is a batch average per call. The report uses the median of six run
medians; neither this nor a retained p95 describes individual-call latency tails.
Warmups consume lazy regex initialization; no cold-start claim follows.
`getrusage(RUSAGE_SELF)` reports whole-process user plus system CPU with microsecond
accounting resolution. It includes checking, hashing, clock work and other process
threads; it is not exclusive engine CPU. CPU minus wall is not wait time. Zero CPU
samples are retained as resolution observations, with a positive median required
for ratios. Main Actor/concurrent batch entry is explicit; synchronous bridge calls
introduce no per-call async boundary. Caller phases are serial, not simultaneous.
Physical-host contention, frequency and thermal isolation remain unknown.

## Observed component CPU costs

These are current A observations from the release phases, in microseconds per audited call. Each cell is the median of six run medians. Audit is the matching expected-value control; lowercase has no matching control. The controls show the scale of measurement work and are not subtracted.

| Input / stage | Actor CPU µs | Actor audit µs | Concurrent CPU µs | Concurrent audit µs |
| --- | ---: | ---: | ---: | ---: |
| iso-fraction-offset / lowercase | 0.186 | — | 0.188 | — |
| iso-fraction-offset / recognition | 15.243 | 0.090 | 15.618 | 0.095 |
| iso-fraction-offset / grammar | 14.199 | 0.225 | 14.125 | 0.227 |
| iso-fraction-offset / format | 2.157 | 0.190 | 2.146 | 0.183 |
| iso-utc / lowercase | 0.122 | — | 0.114 | — |
| iso-utc / recognition | 14.601 | 0.046 | 14.566 | 0.046 |
| iso-utc / grammar | 13.847 | 0.144 | 13.659 | 0.142 |
| iso-utc / format | 2.231 | 0.189 | 2.155 | 0.183 |
| rfc / lowercase | 0.174 | — | 0.172 | — |
| rfc / recognition | 12.003 | 0.045 | 11.990 | 0.046 |
| rfc / grammar | 10.591 | 0.154 | 10.577 | 0.159 |
| rfc / format | 2.154 | 0.175 | 2.182 | 0.176 |
| invalid / lowercase | 0.046 | — | 0.046 | — |
| invalid / recognition | 13.889 | 0.008 | 14.020 | 0.008 |
| invalid / grammar | 14.138 | 0.030 | 13.958 | 0.030 |
| length-guard / lowercase | 0.657 | — | 0.660 | — |
| length-guard / recognition | 0.050 | 0.008 | 0.049 | 0.008 |

For fractional ISO, grammar construction/parsing is observed at 14.199 µs actor
and 14.125 µs concurrent, against field-audit controls of 0.225/0.227 µs. Full
recognition is 15.243/15.618 µs, formatting 2.157/2.146 µs, and lowercasing
0.186/0.188 µs. UTC ISO and RFC grammar observations are also substantially larger
than their formatting observations. This identifies loose-parser work as a useful
next CPU investigation target; it does not assign an exclusive fraction of render
time, or distinguish normalization, individual regular expressions, capture
materialization, field rotations and string mutation within that stage.

The invalid short string still observes 13.889/14.020 µs of recognition work,
whereas the 129-byte recognition guard observes 0.050/0.049 µs. The latter's
lowercasing remains a separate 0.657/0.660 µs observation. The guard case measures
that explicit rejection boundary, not all invalid input behavior. Invalid grammar
can measure above full invalid recognition because the snapshots and audits
have different costs; subtracting those rows would be misleading.

## Complete flag review

The [aggregate appendix](PerformanceReview-DateRecognition-Data.md) records every row, both sides, all three block effects, MAD, ranges and flags. The following counts cover both clocks and all controls; no flagged row is omitted.

| Phase | Rows | Median flags (+/−) | Spread flags |
| --- | ---: | ---: | ---: |
| release-common-ordinary | 26 | 4 (0/4) | 26 |
| identical-common-ordinary | 26 | 1 (1/0) | 26 |
| release-public-actor | 30 | 4 (2/2) | 30 |
| identical-public-actor | 30 | 0 (0/0) | 30 |
| release-public-concurrent | 30 | 3 (3/0) | 10 |
| identical-public-concurrent | 30 | 0 (0/0) | 16 |
| release-component-actor | 58 | 0 (0/0) | 44 |
| identical-component-actor | 58 | 2 (2/0) | 48 |
| release-component-concurrent | 58 | 2 (0/2) | 48 |
| identical-component-concurrent | 58 | 1 (0/1) | 43 |

Total: 17 median flags and 321 spread flags across 404 comparisons. Their interpretation is discussed below.

All 17 median flags are accounted for as follows:

- Common release: all four date modes are lower, with negative blocks throughout
  (source −12.917%, measured source −14.366%, reuse −10.347%, measured reuse
  −10.571%). Every common row has a spread flag. Identical-source measured filter
  source is +14.454% with mixed blocks; all 26 identical common rows also have
  spread flags. These observations do not establish a date speedup or clear the
  opposite fresh-main qualification flags.
- Public actor: measured epoch source is +12.941% CPU/+12.532% wall; measured
  filter source is −11.822% CPU/−10.878% wall. All four have mixed blocks.
  Identical-source actor has no median flags, but every release and identical
  actor row has a spread flag. Ordinary ISO source is +3.890% CPU/+2.478% wall,
  reuse +2.164% CPU/+0.661% wall, with mixed blocks throughout.
- Public concurrent: ordinary filter reuse rises from 3.360 to 3.710 µs CPU
  (+10.417%) and +10.361% wall; measured reuse wall is +10.075%. All three have
  positive blocks and remain adverse control observations. The measured wall
  row has no spread flag; it is not dismissed as variance. Ordinary ISO source
  is +0.597% CPU/+0.636% wall and reuse +1.585% CPU/+1.580% wall, all-positive
  blocks below the median threshold. Their release rows have no spread flag;
  their identical-source counterparts do have spread flags. No equivalence or
  cancellation-cost verdict follows.
- Components: actor release has no median flags. Identical actor fractional ISO
  lowercasing is +11.351% CPU/+11.095% wall, positive in all blocks. Concurrent
  release fractional ISO lowercasing is −13.761% CPU/−13.494% wall, negative in
  all blocks. Identical concurrent guard date-audit CPU is −11.111%, with one
  zero-change block and two negative blocks. That control moves from 0.009 to
  0.008 µs; accounting resolution and auditing limit the interpretation. Retain
  both directions of the identical-source and lowercasing flags without a
  normalization or speedup claim.

Every spread flag is retained in the appendix, including rows below the median
threshold. Large ranges also occur in controls: identical common custom-filter
source reaches 118.071%, and concurrent release invalid date-audit CPU reaches
100% despite zero relative MAD. A small MAD does not erase a distant run.
Component release grammar, full recognition and formatting medians never cross
the 10% median threshold under either caller or clock; their many spread flags
and the small input matrix prevent an equivalence claim. Fractional ISO full
recognition CPU moves −3.635% actor/−1.008% concurrent and grammar CPU
−0.866%/+0.028%. These remain observed costs of unchanged helper sources, not a
causal explanation for previous version differences.

## Decision

Keep the production engine unchanged. Loose-parser construction and parsing are
the next focused CPU target for these inputs, with invalid short-string work
retained alongside successful dates. A subsequent diagnostic experiment can
separate normalization, ordered matching/captures and string mutation before
selecting an optimization. Any production candidate still needs a reproduced
adverse effect, a frozen cross-caller adoption criterion, unchanged semantic and
cancellation evidence, and complete source-bound qualification.

The historical +12.005%/+11.9367% date flags and fresh-main +13.999%/+12.711%
observations remain unresolved. The opposite common date observations in this
study do not clear them. The adverse concurrent filter control also remains
open. This report adopts no cache, fast path, dependency, public API or changed
execution/cancellation policy, and prepares no release.

Raw records, validation receipts, commands, symbols and checksums are retained by
the Actions artifact for 30 days; download it while available. Private records and
build outputs remain outside Git. The immutable protocol and public aggregate
appendix preserve the workload, boundaries, results and every review flag.
