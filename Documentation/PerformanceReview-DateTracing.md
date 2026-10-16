# Date latency: CPU and executor tracing

The historical date regression remains unresolved. This investigation preserves
actual CPU stacks and executor events, alongside all untraced measurements and
failed recording attempts. No production optimization is justified by these
observations. The library, cancellation checkpoints, budgets, invocation ownership,
public declarations and dependency graph remain unchanged.

## Qualified starting point

PR #18 merged as `1313f82ac03b6f51224d6c4219fc26ad0a598ddf` after all nine
qualification lanes passed. The [fresh merged-main run](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38889324829)
also passed all nine lanes and Pages publishing. Independent admission checked
201 source files, raw debug/release/AddressSanitizer streams (81 test functions,
2,178 parameter cases each), two 18-function/64-case parallel repeats, seven
ThreadSanitizer functions, public consumers, reference outcomes, CLI behavior,
four simulator SDK compilation gates, documentation and clean source archives.
These are separate checks, not a count-based conformance claim. Canonically
equivalent filename behavior remains unavailable on that filesystem; it is not
counted as passed. Simulator compilation is not device execution.

The merged-main comparison SHA-256 is
`b72c97233288b2081005b0fce5c4ee7ceab572921021cffa5d45a2f8fa1bcf71`.
All 50 common/metrics rows, block effects and both flag lists were recomputed and
reviewed. Common comparison: zero median flags, nine spread flags. Metrics
comparison: two median flags, eleven spread flags. Ordinary date source was
-0.097% with mixed blocks; measured source +0.440%, ordinary reuse +0.198% and
measured reuse +0.805%. Metrics interpolation diagnostic reuse +10.174% and
ordinary reuse +12.189% both had positive blocks. These remain opt-in cost
observations. Neither this quieter date run nor the faster filter reuse clears
historical date flags or establishes a speedup.

## Frozen source and measurement plan

The immutable baseline is 1.3.0 commit
`9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e`; both independent current builds use
merged main `1313f82ac03b6f51224d6c4219fc26ad0a598ddf`. Their library fingerprint is
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.
`DateParsing.swift`, `RubyDateParser.swift`, `DateFormatting.swift` and
`Renderer+FilterHelpers.swift` remain byte-identical between these versions.
Other runtime changes and compiled layout can still affect a whole render.

The [original frozen plan](https://github.com/ThorFuchs/Swift-Liquid/blob/5da238f5a8228fc2dba263c5f8b03a33820f5aba/Documentation/DateTraceStudyPlan.md),
[driver](https://github.com/ThorFuchs/Swift-Liquid/blob/5da238f5a8228fc2dba263c5f8b03a33820f5aba/Scripts/hosted_date_trace_study.py)
and [consumer](https://github.com/ThorFuchs/Swift-Liquid/blob/5da238f5a8228fc2dba263c5f8b03a33820f5aba/Tools/DateTraceStudy/DateTraceProbe.swift)
precede all observations. The diagnostic branches replace CI for their experiments
and must not be merged. Only the findings belong in the product branch.

Unchanged main first passed `Scripts/ci.py --lane development`. All nine release
executables built before timing: baseline, current A and independently built
current B, each with the unchanged 1.3.0 common harness, the prior wall/CPU probe
and a signposted trace consumer. All builds use `-Xswiftc -g`; the added debugging
information is recorded, not assumed equivalent to an earlier release binary.
The common harness/manifest hashes remain
`2aed7fe384085e4b4b5ba26dcb2545f4006248822b21a864ef515cc51d3c985f` and
`aaf1bad0e6c4c7165b35320bf95878a2a3ac20a5efa9362066901ac9836b4439`.

Three serial blocks each contain common release ABBA, common identical-source
ABBA, actor release ABBA, actor identical-source ABBA, concurrent release ABBA and
concurrent identical-source ABBA. Each comparison retains six run medians per
side, 25 measured samples, ten warmups and 100 repetitions per sample. All 72
untraced runs completed before recording started: 1,344 raw records and 172
comparison rows. Independent recomputation verified every sample summary,
literal expected-output FNV1a checksum, source inventory, block effect and flag.
Derived untraced-data SHA-256:
`6f5332a5cda812e1cfc08e1f597dc007b97ea1148468cca43c6614e0b7c49107`.
No benchmark was repeated or dropped because of its result.

The wall/CPU probe is byte-identical to the prior study. Its equal bodies run
under explicit `@MainActor` and `@concurrent` callers and return checked-Sendable
`Data`. ISO timestamp, integer epoch zero and standard-filter workloads each
cover template construction, ordinary source/reuse and metrics source/reuse.
Output equality and hashing remain inside the timed loops. Epoch bypasses string
date parsing; parsing a template does not run its filters. These controls are not
an additive decomposition. `getrusage(RUSAGE_SELF)` measures whole-process user
plus system CPU, with microsecond granularity and measurement overhead. CPU minus
wall is not wait time, and these observations are not exclusive engine CPU.

The untraced runner reported Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS 27.0.1,
three virtual Apple M1 CPUs and 7 GiB memory. Recorded one-minute guest load
ranged from 1.671 to 2.142. Physical-host contention, frequency and thermal
isolation are unknown. All 172 rows have a spread flag. Neither spread nor an
identical-source control provides a correction factor for another comparison.

## Untraced findings and flag review

Common ordinary date source rose 44.705 to 48.785 microseconds (+9.125%); blocks
were +15.42/+19.27/-4.68%. Ordinary reuse rose +8.146%, all blocks positive.
Measured source/reuse rose +4.682/+4.184%, also with positive blocks. The source
observation falls below the 10% review threshold; that does not establish absence
of a regression. Identical-source date source rose +1.199%, with block effects
+23.85/+5.37/+1.90%. Retain these observations alongside the earlier all-positive
+12.005% and +11.9367% source flags; their cause remains unresolved.

The explicit actor ISO source probe moved -0.044% wall/-0.979% CPU, with mixed
blocks. Concurrent source moved +5.818/+5.619%, all blocks positive. Concurrent
reuse moved +3.056/+3.054%, with mixed blocks. Identical actor source, however,
moved -21.602% wall/-19.103% CPU, with mixed blocks, and identical actor template
construction and measured reuse also produced large flags. This run cannot
support a stable cross-caller or version normalization.

Every median flag is retained and reviewed below; the complete table retains
all 172 spread flags and every block. The phase counts are 5/26 common release,
3/26 common identical, 1/30 actor release, 8/30 actor identical, 8/30 concurrent
release and 0/30 concurrent identical (median/spread).

- Common release: custom-filter measured source +15.328% and ordinary reuse
  +12.024% have positive blocks. Filter reuse -18.826% and measured reuse
  -11.667% have mixed blocks; measured interpolation reuse -15.323% has negative
  blocks. Identical controls and broad spread prevent general speedup claims.
- Common identical: filter reuse +16.437%, interpolation reuse +20.257% and
  measured interpolation reuse -10.618% all have mixed blocks. They demonstrate
  substantial variation with unchanged sources, without explaining away the
  release comparisons.
- Actor release: measured filter reuse CPU +12.417% has mixed blocks; the wall
  record is +8.742% and also mixed. It does not isolate a date-specific effect.
- Actor identical: epoch reuse +17.705% CPU/+17.202% wall, ISO template
  construction +18.627/+18.536%, ISO measured reuse +14.799/+16.174%, and ISO
  source -19.103/-21.602% all have mixed blocks. These eight flags preclude
  treating identical-source performance as stable on this runner.
- Concurrent release: epoch measured reuse +10.128% CPU/+10.243% wall, filter
  measured reuse +10.422/+10.395%, and filter source +11.139/+10.934% all have
  positive blocks. Filter ordinary reuse +22.189/+21.978% has mixed blocks.
  Retain these adverse control observations. The identical ordinary-filter reuse
  control is also positive (+8.223% CPU/+9.394% wall), while its source and
  measured reuse changes are negative with different block patterns. None is a
  per-check cost or a causal explanation for the historical date regression.

## Recorder failures and capture admission

The [original study](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38889400923)
completed all untraced observations and six CPU captures. The seventh target
finished all six batches and wrote its expected outputs, but its recorder did not
return for over thirteen minutes. Normal workflow cancellation still allowed
artifact retention to succeed. The seventh partial trace is not admitted.
Original artifact archive SHA-256:
`d4da63efd52c487986183d9a9e1c5dd9f810e10f8b6420bc2bfff3dfc490eb94`.
Independent checks admitted only six complete captures/36 CPU regions, with
all expected output hashes, complete signposts, raw archive hashes and executable
UUIDs. There were zero engine executor regions in that partial cohort.

A [separate recovery](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38894241807)
verified the exact original binaries, then stalled in a standalone 100-call setup
while stopping its recorder. The target had completed; the watchdog returned 124
after 190 seconds including cleanup. All engine capture steps were skipped and
all setup logs retained. This reproduces a recorder stop problem without Liquid;
it does not prove the recorder's internal cause or qualify engine tracing.

The [coordinated attachment plan](https://github.com/ThorFuchs/Swift-Liquid/blob/cabc3e4214b197df397ddf2a89547fe660ddc5be/Documentation/AttachedDateTracePlan.md)
was frozen before the next hosted capture. A standalone local test first recorded
exactly 100 Main Actor/global transitions in each direction, saved successfully
and exited normally. The target stays alive while recording stops at the declared
window, then exits after release. Darwin tracing-start notification gates workload
entry. Coordination occurs outside all signposted batch bodies.

The new hosted cohort rebuilds three private trace consumers against the same
immutable library versions. Their batch bodies are byte-identical to the original
trace probe; only external coordination differs. These are new diagnostic
executables on a separate runner, not repeats of the original benchmarks.

The [hosted attachment run](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38895891677)
retained all 32 attempts. Individual admission verified 29 complete captures:
15 CPU captures/90 regions and 14 executor captures/84 regions, with 174 output
batches. Two baseline actor executor recordings (release positions 1 and 4) and
the third concurrent identical-source CPU recording (current B) reached their
watchdogs at `Stopping recording`. All three had written six complete,
checksum-verified workload results and the done marker. Their targets then
required cleanup; normal capture completion is not claimed. No retry substitutes
for them. The complete-matrix gate failed and retention succeeded.

Archive SHA-256:
`38e10a37f1725654a0e845dce72f686981626342678320a5eacda0d1565cf9e6`.
`attached-state.json` SHA-256:
`7ebc3060f3c56066212e88d05f33f46d5024b76ec40cede653e3d488acae6195`.
Independent admission hashed all 876 retained files and verified executable UUIDs,
source fingerprints, outputs, signposts, PIDs, normal exits of admitted processes
and raw CPU/executor aggregations. All original 72 benchmark JSON files are byte-identical
to the first cohort. The new host also reported Swift 6.4, macOS 27.0.1, three
virtual Apple M1 CPUs and 7 GiB memory; host identity and binaries remain separate.

The 36 admitted actor executor regions (current A/B only) each record 101 Main
Actor and 100 global running intervals, with 100 transitions in each direction.
The 48 concurrent regions (baseline/current) each record one global running
interval and no executor changes. These include ISO, epoch and standard-filter
source/reuse controls. Missing baseline actor recordings remain missing; the
separate single-workload cohort below supplies its own baseline observations.

The 90 CPU regions underwent the same image-identity symbolication repair and
independent raw-weight recomputation described below. Resolved analysis SHA-256:
`47e5b67a581d473cee5bdfb9452b4f330a432ba953b0d0ed1e50cdcf607e7c29`.
Across admitted ISO intervals, parser inclusive weight is 37.79–48.97% under the
actor caller and 65.39–78.16% under the concurrent caller. RegexMatcher self weight
is 14.98–21.66% and 28.49–41.19%, respectively. Remaining unresolved self weight
is 4.68–8.04% and 4.80–9.93%. Different denominators and instrumented callers
prevent converting these shares into ordinary latency ratios or a version effect.
The missing concurrent B recording also leaves that CPU control matrix incomplete.
All ISO interval summaries follow; epoch/filter results remain in the artifact.

| Caller / phase / position / version | ISO mode | Samples | Parser inclusive % | RegexMatcher self % | Formatter inclusive % | Unresolved self % |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| actor / release / 1 / v130 | iso-source | 1175 | 37.79 | 14.98 | 3.32 | 5.02 |
| actor / release / 1 / v130 | iso-reused | 1077 | 46.43 | 20.89 | 3.62 | 6.04 |
| actor / release / 2 / mainA | iso-source | 1080 | 41.02 | 16.39 | 3.98 | 6.20 |
| actor / release / 2 / mainA | iso-reused | 928 | 48.60 | 21.66 | 4.20 | 6.36 |
| actor / release / 3 / mainA | iso-source | 942 | 46.07 | 20.28 | 3.72 | 5.41 |
| actor / release / 3 / mainA | iso-reused | 870 | 45.63 | 18.74 | 4.83 | 6.67 |
| actor / release / 4 / v130 | iso-source | 1020 | 45.49 | 18.92 | 3.63 | 6.08 |
| actor / release / 4 / v130 | iso-reused | 872 | 48.97 | 21.33 | 4.24 | 5.39 |
| actor / identical / 1 / mainA | iso-source | 868 | 45.05 | 19.93 | 3.69 | 6.22 |
| actor / identical / 1 / mainA | iso-reused | 793 | 44.51 | 17.65 | 5.17 | 5.42 |
| actor / identical / 2 / mainB | iso-source | 871 | 40.18 | 18.37 | 5.17 | 5.17 |
| actor / identical / 2 / mainB | iso-reused | 790 | 44.56 | 20.89 | 4.81 | 4.68 |
| actor / identical / 3 / mainB | iso-source | 880 | 41.36 | 17.16 | 5.45 | 5.11 |
| actor / identical / 3 / mainB | iso-reused | 792 | 42.55 | 17.68 | 3.91 | 6.06 |
| actor / identical / 4 / mainA | iso-source | 1280 | 40.16 | 16.41 | 4.84 | 6.25 |
| actor / identical / 4 / mainA | iso-reused | 995 | 48.24 | 18.19 | 3.92 | 8.04 |
| concurrent / release / 1 / v130 | iso-source | 459 | 70.15 | 28.98 | 6.10 | 6.10 |
| concurrent / release / 1 / v130 | iso-reused | 401 | 72.82 | 35.91 | 9.23 | 6.98 |
| concurrent / release / 2 / mainA | iso-source | 478 | 65.69 | 32.22 | 6.69 | 7.32 |
| concurrent / release / 2 / mainA | iso-reused | 406 | 75.86 | 36.21 | 10.10 | 4.93 |
| concurrent / release / 3 / mainA | iso-source | 471 | 65.39 | 30.79 | 7.01 | 6.58 |
| concurrent / release / 3 / mainA | iso-reused | 403 | 78.16 | 41.19 | 6.45 | 9.93 |
| concurrent / release / 4 / v130 | iso-source | 492 | 71.34 | 32.32 | 5.89 | 4.88 |
| concurrent / release / 4 / v130 | iso-reused | 416 | 77.64 | 39.18 | 6.01 | 7.21 |
| concurrent / identical / 1 / mainA | iso-source | 530 | 66.60 | 28.49 | 7.55 | 9.43 |
| concurrent / identical / 1 / mainA | iso-reused | 490 | 76.12 | 36.33 | 8.78 | 6.33 |
| concurrent / identical / 2 / mainB | iso-source | 537 | 65.74 | 29.98 | 7.64 | 8.01 |
| concurrent / identical / 2 / mainB | iso-reused | 439 | 75.63 | 35.99 | 10.02 | 5.69 |
| concurrent / identical / 4 / mainA | iso-source | 479 | 69.10 | 31.32 | 7.72 | 4.80 |
| concurrent / identical / 4 / mainA | iso-reused | 406 | 75.12 | 37.44 | 9.11 | 8.87 |

The original and attached Actions artifacts have 30-day retention. Download them
while available. Raw archives, XML, symbols and private verification records stay
outside Git; source protocols, source identities and aggregate findings remain
versioned here.

## Admitted CPU samples and symbol coverage

The original six actor-caller captures retain six source/reuse ISO, epoch and
filter batches each: 20,000 measured renders after 100 warmups, with complete
output checks. Time Profiler samples are clipped to the target PID and complete
`RenderBatch` signposts. Sampling, auditing and Instruments work are part of this
instrumented experiment; these elapsed values are not ordinary render latencies.

The exported CPU names initially suggested a large difference in parser
attribution, even between two recordings of the exact same current executable.
Inspection found the same image-relative addresses named in one export and raw
in another. Re-symbolication uses each retained Mach-O UUID, recorded image load
address and matching dSYM with `atos`. Current A/B also have byte-identical
`__TEXT,__text` sections. Original XML and original analysis remain unchanged;
resolved address maps and a separately recomputed analysis are retained.

This repairs name coverage without taking another measurement. Named parser
inclusive weight now ranges from 38.60% to 45.48% across the twelve ISO intervals,
instead of the misleading raw range 4.73–45.48%. Remaining unresolved self weight
is 3.59–5.72%. ICU RegexMatcher self weight is 15.11–21.64%, and
`mach_msg2_trap` self weight is 11.40–15.24%. Formatter inclusive weight is
3.17–5.78%. These are descriptive sample weights: inclusive groups can overlap,
unknown parents remain possible, and a syscall frame is not a wait-time estimate.
No percentage is an exact per-function latency or per-cancellation-check cost.

Both versions spend substantial sampled work in date recognition. These samples
do not demonstrate a version-specific parser increase or establish the historical
+12% cause. In particular, the raw symbol-coverage difference must not be reported
as a parser improvement. Independent recomputation verified all 36 resolved CPU
regions against the same raw sample weights and intervals. Resolved analysis
SHA-256: `9b466cb12a47dfc278365bc9d7a230cb5e4d524d57fce3255cb647af9b89380b`.

| Capture | ISO mode | Samples | Raw parser inclusive % | Resolved parser inclusive % | Unresolved self after symbolication % |
| --- | --- | ---: | ---: | ---: | ---: |
| release/1/v130 | iso-source | 1456 | 38.60 | 38.60 | 4.74 |
| release/1/v130 | iso-reused | 952 | 45.48 | 45.48 | 5.04 |
| release/2/mainA | iso-source | 1360 | 36.91 | 41.10 | 4.85 |
| release/2/mainA | iso-reused | 1531 | 36.58 | 41.61 | 3.59 |
| release/3/mainA | iso-source | 1312 | 4.73 | 38.80 | 5.18 |
| release/3/mainA | iso-reused | 1288 | 5.75 | 44.02 | 4.19 |
| release/4/v130 | iso-source | 1323 | 41.12 | 41.12 | 5.14 |
| release/4/v130 | iso-reused | 1237 | 42.20 | 42.28 | 5.34 |
| identical/1/mainA | iso-source | 1450 | 5.38 | 38.69 | 3.86 |
| identical/1/mainA | iso-reused | 1268 | 4.73 | 41.48 | 4.89 |
| identical/2/mainB | iso-source | 1621 | 42.38 | 42.38 | 4.75 |
| identical/2/mainB | iso-reused | 1398 | 44.49 | 44.49 | 5.72 |

## Single-workload executor observations

The [narrowed plan](https://github.com/ThorFuchs/Swift-Liquid/blob/036ecd6394cb0f3c9accbc1c6973eddffbd0e40d/Documentation/SingleCaseTracePlan.md)
and [consumer](https://github.com/ThorFuchs/Swift-Liquid/blob/036ecd6394cb0f3c9accbc1c6973eddffbd0e40d/Tools/DateTraceStudy/SingleCaseTrace.swift)
were frozen before capture. Two private release consumers built from the same
immutable versions before any recording. Each recording selects one ISO
source/reuse batch, with 100 renders after ten warmups. Eight fixed-order captures
cover both versions under each explicit caller; none failed or was retried.
The local shared host is a separate cohort and is ineligible for latency claims.

Independent admission checked the selected complete signpost, actual PID,
recorder/target zero exits, literal output checksum, raw archive checksum,
executable UUID and every exported executor-state aggregation. Metadata SHA-256:
`835e785fcc38f8e3e22cf2de057256b61cc1206b7ee61b469790766e836d1c97`.

| Caller | Version | Mode | Main running intervals | Global running intervals | Main → global / global → main transitions |
| --- | --- | --- | ---: | ---: | --- |
| Main Actor | 1.3.0 | Source | 101 | 100 | 100 / 100 |
| Main Actor | Current | Source | 101 | 100 | 100 / 100 |
| Main Actor | Current | Reused | 101 | 100 | 100 / 100 |
| Main Actor | 1.3.0 | Reused | 101 | 100 | 100 / 100 |
| Concurrent | 1.3.0 | Source | 0 | 1 | 0 / 0 |
| Concurrent | Current | Source | 0 | 1 | 0 / 0 |
| Concurrent | Current | Reused | 0 | 1 | 0 / 0 |
| Concurrent | 1.3.0 | Reused | 0 | 1 | 0 / 0 |

These are actual executor identities from Swift task events, not an inference
from thread names. Counts describe consecutive recorded running segments per task
inside each selected interval. They do not count all attempted executor checks,
prove that a zero-transition batch performs no checks, or assign time to a hop.
Clipped running/enqueued/suspended occupancies are event intervals, not exclusive
CPU or a latency decomposition. The eight observations corroborate caller-path
sensitivity in both versions without explaining a cross-version date regression.
[Apple's Instruments overview](https://developer.apple.com/videos/play/wwdc2026/268/)
describes the executor instrumentation; the counts above come from these retained
engine traces.

## Decision and remaining uncertainty

The earlier all-positive +12.005% and +11.9367% date flags remain unresolved.
No cancellation checkpoint, parser, formatter, public execution annotation, cache
or dependency changes follow from this investigation. The recorded execution
paths and resolved samples identify useful work to isolate, but the untraced
variation and incomplete capture cohorts prevent a historical causal verdict.
A future candidate needs a reproduced adverse effect, a predeclared adoption
criterion, output/error/budget/cancellation regressions and matched qualification
under both callers. This report supplies no release performance clearance.

## Complete untraced aggregate observations

Positive change means higher time. Medians are microseconds; block effects and
run-median ranges are percentages. `M` marks absolute aggregate change at least
10%; `S` marks either range at least 10%. All raw precision, run medians, MAD and
samples remain in the retained artifact. Release phases compare baseline to A;
identical phases compare A to B. CPU and wall are separate records.

### release-common

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| custom-filter/parse-and-render | 27.724 | 29.713 | +7.173 | +6.28/+15.90/+0.38 | 27.06/36.41 | S |
| custom-filter/parse-and-render-metrics | 26.325 | 30.360 | +15.328 | +2.62/+34.74/+0.46 | 26.99/28.58 | M S |
| custom-filter/reused-template | 22.663 | 25.388 | +12.024 | +2.70/+14.32/+8.16 | 32.15/39.71 | M S |
| custom-filter/reused-template-metrics | 23.972 | 24.774 | +3.346 | +14.97/+4.24/-8.35 | 59.11/36.71 | S |
| date/parse-and-render | 44.705 | 48.785 | +9.125 | +15.42/+19.27/-4.68 | 35.81/55.08 | S |
| date/parse-and-render-metrics | 47.154 | 49.361 | +4.682 | +13.50/+10.27/+2.55 | 26.37/44.03 | S |
| date/reused-template | 42.923 | 46.420 | +8.146 | +20.01/+18.33/+2.07 | 27.25/61.78 | S |
| date/reused-template-metrics | 45.439 | 47.340 | +4.184 | +3.15/+8.15/+2.02 | 25.23/36.96 | S |
| filter-chain/parse-and-render | 29.493 | 28.130 | -4.622 | -16.75/-5.55/-13.27 | 62.55/31.35 | S |
| filter-chain/parse-and-render-metrics | 27.204 | 27.181 | -0.085 | -12.22/+15.88/-26.57 | 91.70/39.65 | S |
| filter-chain/reused-template | 24.730 | 20.074 | -18.826 | -20.95/-22.00/+5.18 | 44.93/55.16 | M S |
| filter-chain/reused-template-metrics | 25.822 | 22.809 | -11.667 | -23.87/+4.16/-4.57 | 46.05/42.42 | M S |
| inspection/inspect-reused-template | 7.035 | 6.974 | -0.868 | +1.42/+8.93/-3.07 | 18.05/24.87 | S |
| inspection/parse-and-inspect | 17.395 | 18.449 | +6.059 | +6.53/+14.48/+1.84 | 16.64/31.52 | S |
| interpolation/parse-and-render | 23.416 | 23.786 | +1.577 | +0.21/-8.82/+10.91 | 62.66/34.99 | S |
| interpolation/parse-and-render-metrics | 24.118 | 22.841 | -5.293 | -7.26/-2.79/+0.39 | 18.92/28.51 | S |
| interpolation/reused-template | 22.989 | 22.398 | -2.571 | -7.47/-14.18/+20.57 | 79.43/54.85 | S |
| interpolation/reused-template-metrics | 25.017 | 21.184 | -15.323 | -19.91/-17.32/-5.64 | 31.23/44.08 | M S |
| loop/parse-and-render | 44.412 | 42.172 | -5.045 | -4.76/+10.35/-24.65 | 73.76/38.31 | S |
| loop/parse-and-render-metrics | 46.280 | 41.969 | -9.314 | -6.76/+13.82/-30.84 | 81.94/36.39 | S |
| loop/reused-template | 37.472 | 35.463 | -5.361 | -14.02/+8.35/-18.41 | 59.73/32.65 | S |
| loop/reused-template-metrics | 36.112 | 37.108 | +2.756 | +1.85/+18.34/-6.01 | 41.30/45.65 | S |
| partial/parse-and-render | 30.180 | 30.801 | +2.059 | +2.69/+13.53/-15.20 | 51.40/33.35 | S |
| partial/parse-and-render-metrics | 30.836 | 32.314 | +4.793 | +7.86/+5.88/+0.52 | 25.61/31.00 | S |
| partial/reused-template | 24.747 | 25.203 | +1.843 | -6.94/+2.72/-0.30 | 39.48/32.66 | S |
| partial/reused-template-metrics | 25.967 | 26.064 | +0.373 | -1.67/+1.00/+49.64 | 35.29/128.44 | S |

### identical-common

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| custom-filter/parse-and-render | 29.814 | 28.888 | -3.108 | +31.57/-0.93/-5.41 | 18.72/53.09 | S |
| custom-filter/parse-and-render-metrics | 28.844 | 31.128 | +7.916 | -1.01/+14.50/+3.62 | 7.21/31.39 | S |
| custom-filter/reused-template | 23.795 | 24.487 | +2.907 | +0.46/+2.08/+2.84 | 23.02/36.99 | S |
| custom-filter/reused-template-metrics | 23.826 | 25.221 | +5.855 | +0.75/+18.70/+33.68 | 24.81/79.74 | S |
| date/parse-and-render | 48.061 | 48.637 | +1.199 | +23.85/+5.37/+1.90 | 8.15/53.98 | S |
| date/parse-and-render-metrics | 48.826 | 50.594 | +3.622 | +34.11/+8.49/+0.90 | 14.24/76.47 | S |
| date/reused-template | 44.144 | 45.449 | +2.956 | +10.37/+11.09/-0.29 | 11.95/29.21 | S |
| date/reused-template-metrics | 46.115 | 47.130 | +2.202 | +26.19/+3.85/+1.70 | 12.09/66.93 | S |
| filter-chain/parse-and-render | 27.463 | 28.171 | +2.577 | +16.48/+13.66/-22.72 | 67.18/32.66 | S |
| filter-chain/parse-and-render-metrics | 30.561 | 29.389 | -3.836 | -6.78/+2.53/-8.51 | 14.41/9.80 | S |
| filter-chain/reused-template | 23.803 | 27.715 | +16.437 | -17.19/+27.02/+12.70 | 40.48/44.72 | M S |
| filter-chain/reused-template-metrics | 26.155 | 27.020 | +3.307 | +10.01/-8.59/+4.89 | 21.74/33.35 | S |
| inspection/inspect-reused-template | 6.895 | 7.089 | +2.822 | -2.97/+12.03/+2.17 | 15.75/15.74 | S |
| inspection/parse-and-inspect | 17.782 | 18.849 | +5.999 | +1.86/+10.13/+4.83 | 10.61/16.33 | S |
| interpolation/parse-and-render | 24.398 | 24.090 | -1.265 | +1.80/+10.55/-28.60 | 71.07/15.65 | S |
| interpolation/parse-and-render-metrics | 24.759 | 24.592 | -0.675 | -9.41/+13.29/-2.19 | 31.76/21.26 | S |
| interpolation/reused-template | 22.424 | 26.966 | +20.257 | -2.46/+59.08/-1.43 | 70.86/49.62 | M S |
| interpolation/reused-template-metrics | 29.301 | 26.189 | -10.618 | +20.91/+0.37/-8.64 | 55.50/59.45 | M S |
| loop/parse-and-render | 46.753 | 45.187 | -3.349 | -3.71/+9.89/-25.95 | 62.72/24.60 | S |
| loop/parse-and-render-metrics | 43.404 | 43.828 | +0.976 | +1.97/-3.20/+1.64 | 14.51/13.33 | S |
| loop/reused-template | 38.529 | 36.155 | -6.162 | -4.71/-0.26/-17.53 | 41.91/7.89 | S |
| loop/reused-template-metrics | 37.014 | 38.422 | +3.804 | +2.31/+3.37/+3.03 | 12.09/10.35 | S |
| partial/parse-and-render | 30.874 | 30.648 | -0.733 | -0.81/+1.61/+1.18 | 11.52/9.91 | S |
| partial/parse-and-render-metrics | 31.784 | 31.472 | -0.982 | -5.18/+0.91/+4.32 | 9.61/12.57 | S |
| partial/reused-template | 25.985 | 25.556 | -1.649 | -10.03/-1.38/+1.91 | 13.67/19.04 | S |
| partial/reused-template-metrics | 26.035 | 26.223 | +0.721 | -7.79/-2.20/-2.55 | 22.62/27.02 | S |

### release-actor

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| epoch/parse-cpu | 2.380 | 2.340 | -1.681 | -16.01/-4.00/+3.06 | 31.51/11.97 | S |
| epoch/parse-wall | 2.375 | 2.338 | -1.535 | -15.84/-4.06/+3.29 | 31.44/12.01 | S |
| epoch/reused-cpu | 27.135 | 25.235 | -7.002 | +8.11/+4.93/-18.30 | 39.91/23.10 | S |
| epoch/reused-metrics-cpu | 26.015 | 24.750 | -4.863 | +15.66/+15.38/-13.88 | 44.17/52.57 | S |
| epoch/reused-metrics-wall | 25.897 | 24.402 | -5.771 | +18.02/+12.97/-12.91 | 42.19/57.53 | S |
| epoch/reused-wall | 27.037 | 24.971 | -7.640 | +7.72/+2.88/-18.10 | 38.22/25.36 | S |
| epoch/source-cpu | 28.550 | 28.745 | +0.683 | +1.04/+0.59/-2.75 | 48.06/47.83 | S |
| epoch/source-metrics-cpu | 28.640 | 28.610 | -0.105 | -2.65/+5.11/-0.05 | 41.76/31.39 | S |
| epoch/source-metrics-wall | 27.591 | 28.043 | +1.635 | -1.47/+3.67/-0.07 | 35.73/31.88 | S |
| epoch/source-wall | 28.095 | 28.058 | -0.130 | +5.90/-0.62/-2.65 | 51.28/63.84 | S |
| filter/parse-cpu | 2.810 | 2.615 | -6.940 | +0.71/-9.43/+2.36 | 11.39/16.44 | S |
| filter/parse-wall | 2.810 | 2.607 | -7.220 | +0.54/-9.59/+2.50 | 11.43/15.96 | S |
| filter/reused-cpu | 25.935 | 28.140 | +8.502 | +0.82/+4.82/+12.51 | 55.25/43.85 | S |
| filter/reused-metrics-cpu | 25.490 | 28.655 | +12.417 | +24.21/-5.29/-2.83 | 26.28/41.56 | M S |
| filter/reused-metrics-wall | 25.753 | 28.004 | +8.742 | +23.06/-7.64/-2.97 | 27.28/42.54 | S |
| filter/reused-wall | 25.588 | 27.974 | +9.325 | +4.35/+3.92/+13.13 | 54.17/50.62 | S |
| filter/source-cpu | 29.685 | 27.670 | -6.788 | +19.37/+1.61/-9.82 | 16.07/47.49 | S |
| filter/source-metrics-cpu | 28.040 | 27.775 | -0.945 | +6.04/-22.73/-3.79 | 20.19/46.44 | S |
| filter/source-metrics-wall | 27.888 | 27.786 | -0.368 | +6.05/-22.32/-3.31 | 20.99/46.61 | S |
| filter/source-wall | 29.325 | 27.509 | -6.191 | +25.02/+0.72/-9.31 | 13.79/63.37 | S |
| iso/parse-cpu | 2.615 | 2.635 | +0.765 | -6.68/+10.32/-2.29 | 16.44/8.35 | S |
| iso/parse-wall | 2.607 | 2.635 | +1.087 | -6.84/+10.52/-2.23 | 15.84/8.30 | S |
| iso/reused-cpu | 45.555 | 47.170 | +3.545 | -26.46/+6.45/+1.05 | 80.39/20.08 | S |
| iso/reused-metrics-cpu | 47.880 | 44.805 | -6.422 | -16.02/-12.00/-1.33 | 71.09/30.58 | S |
| iso/reused-metrics-wall | 47.010 | 44.381 | -5.591 | -16.43/-12.04/-1.53 | 72.71/30.63 | S |
| iso/reused-wall | 44.895 | 46.565 | +3.719 | -26.63/+6.72/+1.09 | 86.73/20.17 | S |
| iso/source-cpu | 49.555 | 49.070 | -0.979 | -9.33/-0.98/+1.69 | 52.61/25.33 | S |
| iso/source-metrics-cpu | 48.485 | 48.830 | +0.712 | -12.52/+2.24/-0.09 | 60.29/36.15 | S |
| iso/source-metrics-wall | 48.316 | 48.491 | +0.363 | -15.96/+1.63/+0.18 | 70.26/34.94 | S |
| iso/source-wall | 48.884 | 48.863 | -0.044 | -10.94/+0.63/+1.56 | 58.52/25.66 | S |

### identical-actor

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| epoch/parse-cpu | 2.350 | 2.570 | +9.362 | -0.94/-0.21/+17.09 | 17.87/24.90 | S |
| epoch/parse-wall | 2.351 | 2.564 | +9.046 | -1.22/-0.22/+16.97 | 18.36/25.02 | S |
| epoch/reused-cpu | 25.275 | 29.750 | +17.705 | +17.71/-2.12/+57.82 | 16.18/50.52 | M S |
| epoch/reused-metrics-cpu | 24.840 | 26.435 | +6.421 | -6.31/+6.25/+16.87 | 21.78/11.76 | S |
| epoch/reused-metrics-wall | 24.835 | 26.363 | +6.150 | -5.50/+6.18/+24.94 | 19.58/21.58 | S |
| epoch/reused-wall | 25.234 | 29.574 | +17.202 | +17.20/-2.05/+60.19 | 15.96/51.23 | M S |
| epoch/source-cpu | 28.470 | 28.980 | +1.791 | -3.36/+0.88/+8.86 | 22.94/41.55 | S |
| epoch/source-metrics-cpu | 28.280 | 30.785 | +8.858 | -21.66/-1.31/+43.79 | 70.72/43.72 | S |
| epoch/source-metrics-wall | 28.239 | 30.604 | +8.375 | -20.65/-3.73/+48.69 | 66.95/53.03 | S |
| epoch/source-wall | 28.411 | 28.815 | +1.425 | -5.03/+0.98/+21.29 | 23.28/43.63 | S |
| filter/parse-cpu | 2.660 | 2.775 | +4.323 | -3.94/+1.55/+3.20 | 23.31/20.18 | S |
| filter/parse-wall | 2.654 | 2.774 | +4.505 | -3.84/+1.63/+3.23 | 23.37/20.52 | S |
| filter/reused-cpu | 29.295 | 30.070 | +2.646 | -5.99/+15.70/+37.03 | 68.58/22.91 | S |
| filter/reused-metrics-cpu | 26.415 | 27.950 | +5.811 | +18.31/+2.67/+45.11 | 67.84/39.43 | S |
| filter/reused-metrics-wall | 26.245 | 27.929 | +6.414 | +19.95/+2.46/+51.01 | 66.65/41.69 | S |
| filter/reused-wall | 29.053 | 30.034 | +3.374 | -5.14/+16.34/+18.00 | 40.77/29.16 | S |
| filter/source-cpu | 28.300 | 29.590 | +4.558 | -0.38/+13.78/+27.57 | 12.12/53.06 | S |
| filter/source-metrics-cpu | 27.415 | 29.695 | +8.317 | +5.37/+11.57/+54.25 | 52.02/43.41 | S |
| filter/source-metrics-wall | 27.370 | 29.632 | +8.266 | +5.56/+11.73/+55.46 | 49.45/47.56 | S |
| filter/source-wall | 28.260 | 29.381 | +3.968 | -0.49/+13.05/+31.16 | 11.24/60.23 | S |
| iso/parse-cpu | 2.550 | 3.025 | +18.627 | -1.47/+54.81/+8.27 | 22.75/56.53 | M S |
| iso/parse-wall | 2.550 | 3.023 | +18.536 | -1.39/+59.89/+8.18 | 22.51/64.95 | M S |
| iso/reused-cpu | 47.530 | 46.890 | -1.347 | -13.04/+1.64/+18.11 | 48.60/73.68 | S |
| iso/reused-metrics-cpu | 49.700 | 57.055 | +14.799 | +3.09/-6.27/+42.58 | 30.66/43.50 | M S |
| iso/reused-metrics-wall | 48.931 | 56.846 | +16.174 | +3.00/-6.24/+44.71 | 30.52/43.40 | M S |
| iso/reused-wall | 47.481 | 46.152 | -2.799 | -13.89/+1.57/+22.31 | 47.08/92.31 | S |
| iso/source-cpu | 63.890 | 51.685 | -19.103 | -15.70/-21.17/+17.01 | 44.15/70.19 | M S |
| iso/source-metrics-cpu | 57.295 | 60.490 | +5.576 | -11.64/+6.86/+23.03 | 52.67/44.90 | S |
| iso/source-metrics-wall | 55.486 | 59.805 | +7.785 | -10.03/+6.94/+26.08 | 65.35/60.27 | S |
| iso/source-wall | 65.847 | 51.623 | -21.602 | -15.47/-22.71/+14.00 | 46.58/75.49 | M S |

### release-concurrent

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| epoch/parse-cpu | 2.225 | 2.420 | +8.764 | +72.61/+8.11/+3.60 | 20.67/137.60 | S |
| epoch/parse-wall | 2.219 | 2.420 | +9.099 | +71.79/+8.29/+3.91 | 20.36/136.74 | S |
| epoch/reused-cpu | 4.540 | 4.875 | +7.379 | +69.42/+10.92/+4.82 | 39.65/132.92 | S |
| epoch/reused-metrics-cpu | 4.690 | 5.165 | +10.128 | +35.91/+10.13/+4.98 | 25.80/49.37 | M S |
| epoch/reused-metrics-wall | 4.686 | 5.166 | +10.243 | +35.74/+10.24/+4.89 | 25.91/49.10 | M S |
| epoch/reused-wall | 4.541 | 4.874 | +7.326 | +70.80/+10.91/+4.58 | 39.52/133.04 | S |
| epoch/source-cpu | 7.000 | 7.670 | +9.571 | -0.20/+13.39/+5.77 | 57.43/37.42 | S |
| epoch/source-metrics-cpu | 7.300 | 7.605 | +4.178 | +91.76/+5.51/+3.85 | 30.41/158.58 | S |
| epoch/source-metrics-wall | 7.289 | 7.599 | +4.250 | +91.58/+5.62/+3.81 | 30.47/158.38 | S |
| epoch/source-wall | 6.997 | 7.659 | +9.456 | -0.22/+13.25/+5.71 | 57.39/37.52 | S |
| filter/parse-cpu | 2.475 | 2.645 | +6.869 | +17.34/+7.36/+2.02 | 24.24/39.70 | S |
| filter/parse-wall | 2.473 | 2.646 | +7.009 | +22.48/+7.32/+2.05 | 23.94/50.85 | S |
| filter/reused-cpu | 3.380 | 4.130 | +22.189 | -10.72/+23.65/+9.06 | 76.04/25.18 | M S |
| filter/reused-metrics-cpu | 3.790 | 4.185 | +10.422 | +10.50/+20.78/+0.53 | 30.61/33.69 | M S |
| filter/reused-metrics-wall | 3.786 | 4.180 | +10.395 | +10.34/+20.79/+0.49 | 30.61/33.58 | M S |
| filter/reused-wall | 3.375 | 4.116 | +21.978 | -9.49/+23.53/+9.02 | 76.12/28.15 | M S |
| filter/source-cpu | 5.970 | 6.635 | +11.139 | +32.46/+14.00/+9.20 | 28.64/48.23 | M S |
| filter/source-metrics-cpu | 6.360 | 6.880 | +8.176 | +41.36/+12.14/+2.44 | 26.42/66.72 | S |
| filter/source-metrics-wall | 6.361 | 6.876 | +8.106 | +41.27/+12.13/+2.32 | 26.36/66.38 | S |
| filter/source-wall | 5.968 | 6.620 | +10.934 | +31.48/+13.66/+9.04 | 28.44/48.38 | M S |
| iso/parse-cpu | 2.610 | 2.810 | +7.663 | +24.53/+9.55/-1.35 | 88.51/130.96 | S |
| iso/parse-wall | 2.608 | 2.799 | +7.309 | +24.62/+9.18/-1.50 | 88.16/131.45 | S |
| iso/reused-cpu | 21.935 | 22.605 | +3.054 | -8.14/+2.30/+2.45 | 68.57/41.89 | S |
| iso/reused-metrics-cpu | 22.595 | 24.670 | +9.183 | +33.91/+9.23/+2.50 | 45.85/91.20 | S |
| iso/reused-metrics-wall | 22.580 | 24.660 | +9.212 | +33.93/+9.24/+2.52 | 45.81/91.21 | S |
| iso/reused-wall | 21.922 | 22.592 | +3.056 | -7.52/+2.35/+2.44 | 68.40/41.81 | S |
| iso/source-cpu | 24.825 | 26.220 | +5.619 | +2.85/+5.22/+2.42 | 53.29/54.42 | S |
| iso/source-metrics-cpu | 25.625 | 26.505 | +3.434 | +13.98/+3.22/+1.01 | 56.62/83.04 | S |
| iso/source-metrics-wall | 25.624 | 26.497 | +3.410 | +14.01/+3.20/+1.01 | 56.61/83.01 | S |
| iso/source-wall | 24.812 | 26.256 | +5.818 | +3.36/+5.42/+2.43 | 53.27/55.58 | S |

### identical-concurrent

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| epoch/parse-cpu | 2.245 | 2.295 | +2.227 | -4.18/+6.25/-10.42 | 22.72/7.41 | S |
| epoch/parse-wall | 2.244 | 2.289 | +2.043 | -4.12/+5.93/-10.72 | 22.73/7.21 | S |
| epoch/reused-cpu | 4.850 | 5.140 | +5.979 | -2.34/+13.26/+1.63 | 13.20/18.29 | S |
| epoch/reused-metrics-cpu | 5.125 | 5.005 | -2.341 | -1.72/+6.82/-5.25 | 18.34/19.38 | S |
| epoch/reused-metrics-wall | 5.123 | 5.005 | -2.294 | -1.73/+6.81/-5.24 | 18.48/19.40 | S |
| epoch/reused-wall | 4.848 | 5.128 | +5.767 | -2.46/+13.25/+1.71 | 13.49/18.18 | S |
| epoch/source-cpu | 7.420 | 7.170 | -3.369 | -11.00/+15.19/-4.91 | 15.50/28.59 | S |
| epoch/source-metrics-cpu | 7.840 | 8.310 | +5.995 | -10.19/+10.80/+8.36 | 24.49/22.14 | S |
| epoch/source-metrics-wall | 7.836 | 8.307 | +6.000 | -10.22/+10.85/+7.90 | 24.58/21.52 | S |
| epoch/source-wall | 7.411 | 7.147 | -3.553 | -10.86/+15.18/-5.04 | 15.36/28.82 | S |
| filter/parse-cpu | 2.675 | 2.550 | -4.673 | -6.93/+11.57/-45.01 | 151.03/26.67 | S |
| filter/parse-wall | 2.672 | 2.548 | -4.639 | -7.06/+11.62/-44.81 | 150.28/26.55 | S |
| filter/reused-cpu | 3.770 | 4.080 | +8.223 | +13.81/+6.32/+1.20 | 24.67/37.99 | S |
| filter/reused-metrics-cpu | 4.000 | 3.895 | -2.625 | -1.25/-1.48/-6.76 | 14.25/14.63 | S |
| filter/reused-metrics-wall | 3.999 | 3.892 | -2.688 | -1.25/-0.44/-6.77 | 14.32/16.91 | S |
| filter/reused-wall | 3.772 | 4.127 | +9.394 | +13.76/+7.53/+1.36 | 24.46/37.72 | S |
| filter/source-cpu | 6.560 | 6.485 | -1.143 | -1.16/+9.86/-13.50 | 30.95/18.35 | S |
| filter/source-metrics-cpu | 6.880 | 6.695 | -2.689 | -2.54/-0.87/-9.71 | 23.69/16.43 | S |
| filter/source-metrics-wall | 6.866 | 6.698 | -2.458 | -2.42/+0.99/-9.59 | 23.62/19.93 | S |
| filter/source-wall | 6.556 | 6.488 | -1.036 | -1.20/+11.97/-13.40 | 30.91/22.32 | S |
| iso/parse-cpu | 2.710 | 2.835 | +4.613 | +7.05/+9.96/-10.51 | 38.75/21.87 | S |
| iso/parse-wall | 2.706 | 2.831 | +4.643 | +7.12/+9.82/-10.45 | 38.31/21.62 | S |
| iso/reused-cpu | 23.605 | 23.535 | -0.297 | -6.99/+8.99/+2.92 | 15.80/22.43 | S |
| iso/reused-metrics-cpu | 23.240 | 23.230 | -0.043 | -3.10/+3.74/-0.95 | 15.53/10.76 | S |
| iso/reused-metrics-wall | 23.231 | 23.237 | +0.028 | -3.10/+4.73/-0.97 | 15.44/12.27 | S |
| iso/reused-wall | 23.583 | 23.750 | +0.710 | -6.93/+10.15/+2.93 | 15.69/22.42 | S |
| iso/source-cpu | 25.280 | 25.610 | +1.305 | -6.66/+20.90/+1.21 | 18.87/34.01 | S |
| iso/source-metrics-cpu | 25.400 | 26.670 | +5.000 | -1.08/+13.66/+0.89 | 10.08/17.06 | S |
| iso/source-metrics-wall | 25.389 | 26.657 | +4.998 | -1.07/+15.46/+0.90 | 10.09/17.08 | S |
| iso/source-wall | 25.256 | 25.592 | +1.331 | -6.66/+21.27/+1.23 | 18.79/34.36 | S |
