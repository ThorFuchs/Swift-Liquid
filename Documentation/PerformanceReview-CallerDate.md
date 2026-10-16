# Caller and date latency investigation

PR #16 was merged at `e29ec2a639b8d73a1c885b541f1bcef408c9c2a7`. The follow-up
investigates two observations retained by that PR: ordinary interpolation under
the original caller, and source-date rendering against 1.3.0. Here, ordinary means
rendering without metrics; common caller means the unchanged benchmark's async
main entry. A concurrent caller moves the entire benchmark loop into one explicit
`@concurrent` function. These distinguish invocation policies from caller context.

## Keep the historical observations

The PR comparison observed date source rendering +12.005%, with all three block
effects adverse and a candidate run-median range of 97.938%. Its ordinary reused
interpolation observation was −16.128% against 1.3.0, but with mixed block signs.
The earlier controlled comparison against 1.3.1 observed ordinary common reuse
+4.25%, source +6.25%, and concurrent reuse −14.86%. Those runs remain retained;
newer observations do not erase their flags or establish a sole cause.

The [merged-main qualification](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38827370929)
passed all nine gates and deployed its documentation. Independent verification
bound every receipt to 198 source files, requalified raw test streams, checked
source/documentation archive bytes and checksums, and retained reference/API/fixture
accounting. The library fingerprint is identical to the PR's measured candidate:
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.

Its fresh 1.3.0 comparison observed ordinary interpolation +5.705% from source and
+8.397% reused; date ordinary source was +0.474%. Neither phase had a 10% median
flag; common/metrics phases retained 16/7 spread flags. All 50 comparisons and all
four flag lists were independently recomputed. An unflagged increase still
matters, and a different result for identical library bytes demonstrates that a
single cross-version observation cannot fully attribute the change to source.
It does not prove that all observed differences are environmental.

## Separate source changes and callers

The [new study](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38829803897) and its
[frozen plan](https://github.com/ThorFuchs/Swift-Liquid/blob/1e84882e3823d1950d04b7251bed3fb748809491/Documentation/CallerDateStudyPlan.md)
were committed before timing on a separate diagnostic branch. It compares
immutable 1.3.0, immutable 1.3.1, merged PR #16, a formatter candidate and an
independently built identical merged-source copy under both callers. All eleven
binaries build before timing. Three serial interleaved ABBA blocks per comparison
retain 96 common-harness runs and 208 comparisons. The common harness/manifest
remain the unchanged 1.3.0 bytes, with 26 records, ten warmups, 25 samples, 100
repetitions and output/checksum verification inside the timed loop.

A supplemental binary links only the merged source. Otherwise identical explicit
MainActor/concurrent bodies measure no-inline nonisolated empty and cancellation-
checking async functions, plus ordinary/measured reused interpolation and date.
Three actor/concurrent/concurrent/actor blocks retain twelve runs and 72 records.
Optimized SIL records actual compiler executor operations. These are diagnostic
observations; subtracting synthetic call time from rendering would not measure
an isolated engine cost. Static/dynamic hop optimizations and scheduling still
apply. See Swift's [async-main semantics](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0323-async-main-semantics.md),
[non-actor async execution](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md),
and [explicit concurrent execution](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md).
The package does not enable `NonisolatedNonsendingByDefault` or change public
isolation annotations as a performance shortcut.

## Candidate and correctness boundaries

The candidate recognizes strftime flags, modifiers and directives directly as
Unicode scalars. The previous code repeatedly constructed temporary String and
Character values for recognition. Literal spelling, parser production order,
calendar calculations, per-directive steps, padding bounds, output capacity and
cancellation polling remain unchanged. No cache, dependency or public API is added.
Skipping reference-clock validation for fully specified dates was rejected during
review because it would change existing failure behavior.

Before timing, `Scripts/ci.py --lane development` qualified both the unchanged
merged formatter with the authored tests ported onto it and the frozen candidate:
81 functions/2,178 parameter cases plus public consumers and CLI/schema checks.
New cases retain exact NFD, emoji, NUL and unknown-directive bytes; independent
format expectations; exact evaluator steps and byte capacities; cancellation before
quota failure; and shared-engine date calls across all four policies. Existing
pinned date/grammar fixtures, fixture licenses, public APIs and root dependencies
remain untouched.

The first queued dispatch was cancelled after static review corrected an error
assertion that required Equatable. The first running attempt passed both preflights
and built the caller probe, then stopped at standalone SIL emission because its
module search path did not match this toolchain's build layout. No timing had
begun. The corrected diagnostic discovers emitted module/framework paths and
matches the package's deployment target. Failed/cancelled setup records are retained
alongside the completed study; no timed run is discarded or replaced.

## Caller results and interpretation

| Probe, reused render where applicable | MainActor µs | Concurrent µs |
| --- | ---: | ---: |
| `empty-async` | 0.0569 | 0.0563 |
| `checked-async` | 14.0204 | 0.1138 |
| `interpolation` | 18.9602 | 2.0865 |
| `interpolation-metrics` | 21.2277 | 2.2458 |
| `date` | 37.4602 | 19.8975 |
| `date-metrics` | 37.8671 | 20.0637 |

Standalone optimized SIL from the probe source shows that the empty async
specialization contains no executor hop. The checked specialization retains a hop
to the generic executor; the actor caller restores MainActor after calls. The
concurrent caller targets the generic executor. This diagnostic is separately
emitted from source, not a dynamic hop trace extracted from the timed binary.

The checked-async observation includes executor round trips, scheduling, the check,
call bookkeeping and output auditing. It is **not** a 14 µs cancellation-check cost.
The empty function's optimized behavior makes it unsuitable as a normalization
constant. Do not subtract either probe from render time. The same-binary caller
contrast supports a material executor/scheduling component in whole-call latency;
it does not establish the sole cause of the historical version differences.

Probe actor measured-interpolation run-median range was 23.69%; actor date ordinary/
measured ranges were 10.95%/10.73%. All twelve runs and 72 records remain retained.
Changing public engine isolation to remove round trips would also change where
application work executes; this investigation preserves that behavior.

Applications that intentionally want a whole batch loop off their actor can choose
an explicit concurrent entry. The [public consumer](../Examples/Consumer/Sources/LiquidConsumer/main.swift)
compiles and runs such a helper with checked-Sendable engine/templates/context,
entry/final cancellation checks and each engine call's existing checks. It remains
one structured async call. Each render keeps its own capacities; the example adds
no cumulative batch quota. Applications requiring actor-owned work between renders
should retain their chosen actor boundaries. No universal batch speedup is claimed.

## Cross-version results

| Comparison | Caller | Interpolation source | Interpolation reused | Date source | Date reused |
| --- | --- | ---: | ---: | ---: | ---: |
| 1.3.0 → 1.3.1 | common | +3.09% | +8.55% | +0.70% | +1.33% |
| 1.3.0 → 1.3.1 | concurrent | +5.05% | +9.62% | +0.96% | +0.36% |
| 1.3.1 → merged PR #16 | common | -3.10% | -9.86% | +0.14% | +0.02% |
| 1.3.1 → merged PR #16 | concurrent | -10.06% | -17.39% | -0.07% | +0.33% |

The release comparison retains ordinary reused-interpolation increases in all
three blocks: common `[7.91, 12.76, 8.42]%`, concurrent `[11.14, 8.73, 6.96]%`.
Measured common reuse increased 27.54%, with blocks `[28.10, 32.59, 4.92]%`.
Those observations remain part of the record. The release contains the required
output-cancellation checkpoint, but this is not an isolated per-check experiment.
No checkpoint is removed or weakened to recover a baseline timing.

Merged PR #16's concurrent ordinary reused effects were
`[-17.22, -17.23, -17.57]%`; common ordinary reused effects were
`[-13.18, -9.71, 2.79]%`. Its concurrent source and measured reuse flags were
−10.06%/−16.05%; common measured reuse was −18.15%. These corroborate the bounded
path's benefit under the concurrent caller and common measured caller, while
ordinary common reuse remains caller-sensitive. Each percentage compares its own
phase; ratios from different phases must not be multiplied into a direct release
claim.

Date ordinary source changes were +0.70%/+0.96% in the release comparison and
+0.13%/−0.07% after PR #16, common/concurrent respectively. Together with fresh
main's +0.47%, these do not corroborate a persistent material date slowdown in
these controlled observations. The earlier +12.005% flag remains unresolved and
retained. All four date implementation/helper files are byte-identical from
1.3.0 through merged PR #16. This evidence does not prove absence of regressions
on other hosts or identify a sole cause.

## Reject the formatter candidate

The measured candidate is `61d0353ad6fc17566800a4c5c8abbbd611fea9ff`, Liquid
fingerprint `77b6ec497a99005c01a34a370ac727089b62a685c1a62f722e0337f8e0db7d55`.
The final proposal restores every production library byte to merged PR #16.

| Date mode | Caller | Candidate change | Identical-source change |
| --- | --- | ---: | ---: |
| parse-and-render | common | +4.28% | -5.60% |
| parse-and-render-metrics | common | -0.88% | -5.53% |
| reused-template | common | +1.39% | -5.03% |
| reused-template-metrics | common | -0.71% | -5.83% |
| parse-and-render | concurrent | -2.90% | -1.72% |
| parse-and-render-metrics | concurrent | -2.55% | +0.16% |
| reused-template | concurrent | -3.76% | +1.00% |
| reused-template-metrics | concurrent | -4.55% | +0.24% |

Common source-date block effects were `[-4.88, 5.89, 4.73]%`, reused
`[-5.52, 2.02, 3.59]%`. Concurrent effects were negative in every block, but
modest aggregate reductions and the retained identical-source variation do not
satisfy the all-caller adoption criterion. Absence of a 10% flag is not sufficient
reason to keep a performance change. No retry was selected to seek a preferred
outcome. Retain the stronger date regression coverage and reject the runtime patch.

## Complete evidence and limits

All raw samples, output identities, summary statistics, block effects, source
manifests and all sixteen median/spread lists were independently recomputed. The
study SHA-256 is `10eb2f626bbec03d605b0029129f816b02cc79671fac554395eb7d90f799e1f3`.

| Phase | Median flags | Spread flags |
| --- | ---: | ---: |
| release-common | 1 | 26 |
| release-concurrent | 0 | 0 |
| merged-common | 1 | 20 |
| merged-concurrent | 3 | 1 |
| formatter-common | 0 | 22 |
| formatter-concurrent | 0 | 16 |
| identical-common | 0 | 17 |
| identical-concurrent | 0 | 26 |

The five median flags are the release common measured-reuse increase, merged
common measured-reuse reduction, and merged concurrent interpolation source,
ordinary-reuse and measured-reuse reductions described above. Every spread list,
including unflagged medians and the zero-flag release concurrent phase, remains
retained. Other formatter-phase workload median changes ranged from −2.76% to
+5.63% common and −2.37% to +0.88% concurrent; those are observations, not extra
speedup claims.

One-minute guest load ranged from 1.45 to 2.08 on a three-vCPU Apple M1 VM with
7 GiB guest memory. Physical-host, thermal and scheduling isolation are unknown.
Ranges/MAD describe these runs without confidence intervals or independent-sample
assumptions. Timings include the historical harness's result/checksum auditing;
they do not measure process memory or establish cross-engine superiority.

The production Liquid fingerprint remains
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.
The final changes add tests, a compiled application example and this record.
Published 1.0–1.3.1 releases, API baselines, fixture pins, licenses, cancellation
checks, capacities and the empty dependency graph remain unchanged. The full CI
run attached to the follow-up PR qualifies that final source inventory separately
from the experimental study; publication still requires a maintainer request.
