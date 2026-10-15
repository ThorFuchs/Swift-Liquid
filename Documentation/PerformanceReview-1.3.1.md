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

Before observing its results, specify one complete local
`Scripts/ci.py --lane matched-performance` run at merged PR #14 commit
`2a9e787e9f073b444e69d258f53ecaabbdd74bcb`. Use the same immutable baseline,
unchanged harness, compiler requirements, three ABBA blocks, six runs per side,
sampling and 10% review thresholds. Build every binary before timing, run no
additional qualification build during measurement, and retain every observation.
The release candidate must have the identical Liquid Swift-source fingerprint
for this study to inform its review. CLI versions and Markdown do not affect that
fingerprint. No repeats are selected to obtain an unflagged result.

This study supplements the final candidate's nine CI gates. It does not replace
exact-source candidate qualification, establish physical-host isolation or create
independent statistical samples. Its full receipt, environment, raw samples,
flags and interpretation accompany the final release evidence, including any
unfavorable or inconclusive observations.

## Release decision

For the final candidate, recompute both comparison phases from raw samples,
verify output identities and review all four exact flag lists. Inspect absolute
latencies, individual run distributions and three-block effects. Preserve the
prior runs and independent study beside the final evidence. A mechanically valid
comparison is insufficient to approve performance, and an unresolved material
regression must not be hidden by changing thresholds or accepting a status field.

The bound review must explain whether a repeatable cost remains, whether it is
acceptable for this correctness fix and what the observations cannot establish.
A possible cost may be disclosed and accepted explicitly; it must not be described
as no regression or zero overhead. Fresh exact-main qualification and review are
required after the release preparation merges and before separately authorized
publication.

Graph construction, larger workloads and cancellation response have distinct
timing boundaries. Retain their output checks and all cancellation outcomes;
normal completion races are not cancellation successes. There is no hard deadline,
process-memory bound or comparison with another Liquid engine. See
[performance methodology](Performance.md) and
[measured maintenance](MeasuredMaintenance.md).
