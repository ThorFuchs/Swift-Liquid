# Swift-Liquid 1.3.1 benchmark review

The maintenance release preserves the published APIs and common workloads. Its
runtime changes are iterative JSON container parsing and an additional cooperative
cancellation check at output admission. Neither change is presented as a speedup.
This document records the investigation and review policy; the qualification
archive contains the final candidate's numerical results and checksum-bound
release decision.

## Why investigate the output checkpoint?

PR #14's final comparison, in
[run 38793230969](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38793230969),
retained these median-change flags against immutable 1.3.0:

| Common workload | Mode | 1.3.0 µs | Candidate µs | Change |
| --- | --- | ---: | ---: | ---: |
| custom-filter | parse-and-render-metrics | 24.744 | 27.432 | +10.86% |
| custom-filter | reused-template | 19.399 | 21.367 | +10.15% |
| interpolation | reused-template-metrics | 20.915 | 23.023 | +10.08% |

The separate same-candidate metrics phase flagged date diagnostic source
rendering at +12.13% (45.079 µs ordinary, 50.548 µs measured). This is an opt-in
cost observation, not a cross-version slowdown. All four flag lists were retained:
three common change flags, one metrics change flag, 23/26 common spread flags and
21/24 metrics spread flags.

The three common block effects were respectively
`[13.35, 1.15, 15.26]%`, `[19.43, -4.79, 14.44]%` and
`[16.50, 11.65, 8.13]%`. The metrics flag's effects were
`[7.45, 12.74, 5.38]%`. Observed min/max ranges overlap for each flagged pair;
these ranges are not confidence intervals. A sign change or overlap does not
prove that an intrinsic cost is absent. Earlier
[run 38790106544](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38790106544)
used the earlier implementation and retained a different flag set; it does not
qualify the corrected engine.

An extra task-cancellation check per output boundary is a plausible small cost.
The common inputs are constructed before timing, so their prepared contexts do
not measure JSON parsing. The initial question is whether the common increases
repeat on an independent host and whether output-heavy loop and partial workloads
show a consistent effect. Timing variation remains a competing influence; no
cause is inferred from spread alone.

## One independent-host study

One complete local `Scripts/ci.py --lane matched-performance` run used merged
PR #14 commit `2a9e787e9f073b444e69d258f53ecaabbdd74bcb`. Its question and
sampling policy were recorded before observing results. It kept the immutable
baseline, unchanged harness, three ABBA blocks, six runs per side and 10% review
thresholds. All binaries built before timing; no other local qualification build
ran during timing. The Liquid Swift-source fingerprint is
`50b372f97e4f3429647723b7c9ec8c4b8cca13759774fa069b369109b48fafa4`.
CLI versions and Markdown do not change this fingerprint.

The host was severely contended: one-minute load was 247.69–277.31 on ten physical
cores. Every common and metrics comparison had a spread flag. Common median
changes ranged from −33.11% to +94.13%; metrics changes from −44.35% to +44.48%.
This study is inconclusive for intrinsic cost and does not clear the earlier
flags. All unfavorable observations remain retained; no local repeat was selected.

## Isolate the checkpoint

The required merged-main
[run 38800631012](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38800631012)
again observed ordinary reused custom filters at +11.40% and measured reused
interpolation at +19.05%, with spread flags in all 26 common comparisons. These
recurring effects justified a different experiment, specified before timing.

A private release executable linked two modules copied from the same Liquid
Swift sources. The control omitted only the new output-admission cancellation
check; this intentionally incorrect cancellation control is not a package product
or supported engine. Source manifests and the exact diff are retained. Four
prepared public-API fixtures ran five warmup and forty measured ABBA blocks,
500 calls per batch, with output equality and FNV-1a checks inside timing.
Identical checked-code A/A comparisons used the same boundaries for each fixture.
No qualification build overlapped timing.

| Fixture | Median paired checkpoint change | Identical-code A/A median |
| --- | ---: | ---: |
| Ordinary reused custom filter | +5.57% | +0.99% |
| Measured reused interpolation | +9.34% | +0.052% |
| Ordinary reused loop | −0.50% | −1.00% |
| Reused inspection | +1.54% | +0.92% |

Measured interpolation was positive in 37/40 blocks; median batch values were
about 2.47 µs for the control and 2.68 µs with the checkpoint. This supports a
possible positive cost on a small workload. The custom-filter blocks had extreme
signed spread, and the loop and inspection results do not establish a speedup or
absence of overhead. Local load remained about 203. A/A controls, interleaving and
output checks improve the diagnosis but do not establish isolation. Separate
module names/code layout can influence the result. This authored harness differs
from the pinned common harness; no cross-harness latency comparison or universal
overhead bound is justified.

## First candidate observations

[Run 38801432017](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38801432017)
measured the same Liquid fingerprint with the unchanged common protocol. Its
source-interpolation flag was +15.17% (20.589 to 23.712 µs), with block effects
`[3.66, 12.72, 19.01]%`. Measured reused interpolation changed sign relative to
the earlier runs: −10.43%, with blocks `[-12.24, -26.25, 23.06]%`. That result is
not evidence of a speedup. Spread flags affected 25/26 common and all 24 metrics
comparisons; five opt-in metrics flags ranged from +11.01% to +23.20%.

These are retained observations for the earlier candidate source inventory,
not a substitute for qualification after this review documentation was added.
The final candidate's archive contains its own raw measurements, all four exact
flag lists and checksum-bound decision. No repeated measurement was selected to
obtain an unflagged result.

## Hosted checkpoint control with the pinned harness

The final PR #15 [comparison](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38803456604)
retained nine common median flags, including four loop changes from +17.07% to
+36.11%. A separate [hosted diagnostic run](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38806847671)
used the same Liquid Swift-source fingerprint, pinned common harness, manifest,
Swift 6.4 compiler and sample protocol. The diagnostic branch remains separate
from the release source. All binaries built before timing. Three interleaved ABBA
blocks compared the checkpoint engine with a control omitting only that check,
and compared two independently built copies of the identical checkpoint source.
Every raw sample, source inventory, control diff and comparison is retained in
the qualification archive.

The four loop checkpoint changes were +2.02%, +1.96%, +0.83% and +1.20%; their
identical-source controls ranged from −0.29% to +0.20%. The larger final-PR loop
changes did not reproduce as isolated checkpoint costs. This does not establish
that they were solely environmental or that the release has no regression.

Measured reused interpolation changed from 19.490 to 23.248 µs, or +19.28%, with
three block effects of `[24.69, 18.59, 23.21]%`. Its identical-source comparison
was −4.08%. The checkpoint comparison retained eleven spread flags; the
identical-source comparison retained eight and no median-change flags. All other
checkpoint median changes ranged from −5.98% to +3.83%. A VM's scheduling, thermal
conditions and physical-host isolation remain uncontrolled. Separate builds may
also change optimization and code layout; the result is an observed variant cost,
not a portable instruction cost or a universal bound.

This stronger control supports accepting a measurable cost for a small
metrics-enabled call in return for the reproduced cancellation-correctness fix.
Fresh main measurements must still be reviewed on their own merits. The control
study corroborates that review; it does not qualify main's source inventory.

## Release decision

For the final candidate, recompute both comparison phases from raw samples,
verify output identities and review all four exact flag lists. Inspect absolute
latencies, individual run distributions and three-block effects. Preserve the
prior runs and independent study beside the final evidence. A mechanically valid
comparison is insufficient to approve performance, and an unresolved material
regression must not be hidden by changing thresholds or accepting a status field.

The recurring flags and controlled interpolation observation support treating a
positive checkpoint cost as a correctness tradeoff. Retain the checkpoint: the
old engine could deliver normal output after cancellation during its last filter.
A possible latency increase on these small calls is acceptable for fixing that
reproduced defect; this is not a no-regression or zero-overhead verdict. The bound
review must assess every final flag and any additional material regression rather
than inheriting this decision mechanically. Fresh exact-main qualification and review are
required on the final main commit before the authorized publication.

Graph construction, larger workloads and cancellation response have distinct
timing boundaries. Retain their output checks and all cancellation outcomes;
normal completion races are not cancellation successes. There is no hard deadline,
process-memory bound or comparison with another Liquid engine. See
[performance methodology](Performance.md) and
[measured maintenance](MeasuredMaintenance.md).
