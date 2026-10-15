# Interpolation latency investigation

The 1.3.1 release retained observed ordinary/measured reused-interpolation
increases of +17.03%/+33.43% against 1.3.0. Cancellation correctness remains a
requirement: output admission must check cancellation before its byte quota,
including empty output and final delivery after synchronous work.

## Reject the first two hypotheses

A [recorded study](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38819503018)
compared immutable 1.3.1 code with two separate variants: exact native-string
conversion guards and forced output-check inlining. Two independently built
identical-source copies supplied an A/A control. Every cancellation checkpoint
remained present. The plan and driver were committed before timing on the separate
`codex/interpolation-investigation` branch; that diagnostic workflow is not part
of the proposed production change.

All eight binaries built before timing. The immutable common harness/manifest
retained all 26 records, ten warmups, 25 samples and 100 repetitions. An authored
second driver changed only the entry to one `@concurrent` call; all workloads,
checks and timing loops stayed the same. Three interleaved ABBA blocks per variant
and driver retained 72 raw runs, 156 comparisons, exact source patches, manifests,
symbols and disassembly. Raw summaries, output identities, block effects and all
flag lists were independently recomputed.

| Variant | Caller | Ordinary reused change | Measured reused change |
| --- | --- | ---: | ---: |
| Native-string guards | Common | −4.98% | −8.57% |
| Native-string guards | Concurrent | −0.81% | −0.12% |
| Forced output inlining | Common | +22.43% | +16.12% |
| Forced output inlining | Concurrent | −3.52% | +0.22% |
| Identical-source control | Common | +11.25% | +19.11% |
| Identical-source control | Concurrent | +0.90% | +2.08% |

These are each phase's observed aggregate changes, not paired effects across
phases or confidence intervals. Every phase retained spread flags in all 26
comparisons. Native-string guards also retained adverse common date/custom-filter
observations. The concurrent reused-interpolation effects do not corroborate a
reliable gain; forced inlining worsens common observations. Neither variant is
adopted. No unfavorable run, flag or source variant was discarded.

The concurrent caller's reused-interpolation observations were around 2.5–3 µs,
whereas common-caller observations were around 20–30 µs. This supports examining
caller/executor effects separately from rendering work. It does not identify a
sole cause for the released flags or establish that they are all environmental.
The three-vCPU Apple M1 VM recorded one-minute load of 1.64–2.06; physical-host,
thermal and scheduling isolation remain uncontrolled.

## Follow up on asynchronous node calls

The existing renderer uses asynchronous functions for the root, template list
and each node even when the root contains only text and plain variables. A bounded
synchronous path can avoid those internal calls while preserving public async
execution behavior and the original stringification authority.

The candidate classifies at most three root leaves into an invocation-owned,
immutable fixed-arity plan. Only text, raw text and plain-variable output/echo are
eligible. It classifies the complete shape before charging or evaluating anything.
Larger roots, filters, dynamic expressions and control flow use the existing path.
Eligible leaves cannot throw a recoverable `RenderError`; resource failures and
cancellation keep their original identities.

Root and child entry charges, depth cleanup, multi-node cancellation checks,
per-child output admission, aggregate admission and the engine's final admission
remain in the same order. There is no cached cancellation state, changed quota,
new dependency, public declaration, actor annotation or template/engine cache.

The follow-up must compare frozen candidate library bytes with immutable 1.3.1
and an identical-source control under both drivers. All binaries finish before
timing. Keep the unchanged common protocol and every raw observation. Review all
workloads, distributions and block effects before adopting the candidate.

Qualification includes a public value/Unicode/metrics/exact-byte-capacity matrix;
differential snapshots against the unchanged general renderer across small and
fallback shapes, recovery policies and step/depth/output boundaries; deterministic
cancellation during stringification; existing callback cancellation tests; and
the affected `Scripts/ci.py` gates. Tests use no sleep or timing deadline as an
oracle. Published fixture bytes, parser modes, licenses, API baselines and 1.3.1
release assets remain unchanged.

## Frozen-candidate follow-up results

The [follow-up study](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38822674933)
first passed `Scripts/ci.py --lane development`: 78 functions and 2,166 parameter
cases, public consumers and CLI/schema checks for the frozen candidate. Its first
preflight attempt passed those tests but stopped at a consumer because the temporary
checkout basename changed SwiftPM's local package identity. The corrected checkout
uses `Swift-Liquid`; no benchmark sample existed before that setup correction.
Both attempts and all failed setup logs remain retained.

The measured source is commit `65f66404e2ad1e62862d22db12c8c5a59001635b`, with
Liquid fingerprint `6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.
The final proposed library retains those exact Swift-source bytes; later changes
add concurrency coverage and this report. The baseline is immutable 1.3.1 commit
`fb81cf4ff01f1bf098ceb5fff65638b1271294e0`. The unchanged common harness is still
selected by its recorded 1.3.0 commit, never a floating branch.

Six binaries built before timing. Three serial ABBA blocks per candidate/control
and driver retained 48 complete runs and 104 comparisons. All raw summaries,
checksums, source manifests, flag lists and block effects were independently
recomputed; development streams were checked against the frozen candidate's
reviewed inventory. Existing budget methods remain byte-identical to 1.3.1.

| Caller | Interpolation mode | 1.3.1 µs | Candidate µs | Change | Identical-source change |
| --- | --- | ---: | ---: | ---: | ---: |
| Common | Source | 17.910 | 19.030 | +6.25% | −0.85% |
| Common | Source, metrics | 18.618 | 18.639 | +0.11% | −0.52% |
| Common | Reused | 19.132 | 19.945 | +4.25% | −3.59% |
| Common | Reused, metrics | 25.136 | 18.870 | −24.93% | −4.16% |
| Concurrent | Source | 4.305 | 3.927 | −8.78% | −0.15% |
| Concurrent | Source, metrics | 4.521 | 4.127 | −8.72% | −0.97% |
| Concurrent | Reused | 2.366 | 2.014 | −14.86% | −3.19% |
| Concurrent | Reused, metrics | 2.550 | 2.166 | −15.04% | −1.12% |

Concurrent reused block effects were `[-15.75, -14.29, -13.21]%` ordinary and
`[-16.42, -15.12, -11.24]%` with metrics. Their control effects were
`[-2.51, -9.74, -2.33]%` and `[1.09, -9.47, -0.17]%`. Candidate run-median
ranges for these rows were 5.71%/9.69%, versus baseline 2.69%/3.59%. This supports
a reduction in rendering work on this host under that caller, beyond the observed
aggregate control effects. It does not establish a universal percentage.

Common measured-reuse block effects were `[-32.74, -15.52, -15.05]%`; controls were
`[-13.24, -5.34, -11.28]%`. That improvement is corroborated, with material spread
retained. Common ordinary reuse changed by +4.25%, with blocks
`[-7.47, 3.44, 9.44]%`; it does not establish an improvement. Common source changed
by +6.25%, with blocks `[7.10, 6.89, -8.76]%`, and measured source by +0.11%.
Those adverse/subthreshold observations remain part of the decision. No claim is
made that all original caller-sensitive regressions are resolved. Comparisons
from different runs must not be multiplied to infer a return to 1.3.0 latency.

Other workload median changes ranged from −5.32% to +3.48% common and −0.39% to
+2.01% concurrent; none added a positive 10% median flag. The candidate common phase
retains one faster median flag and 21 spread flags; concurrent retains two faster
flags and 15 spread flags. Identical-source phases retain no median flags, with
14 common and 23 concurrent spread flags. Every flag and observation is retained.
One-minute guest load was 1.65–1.97 on the three-vCPU Apple M1 VM. Ranges and MAD
remain descriptive, without physical-host, thermal or statistical-independence
claims.

Adopt the bounded synchronous candidate because the reused rendering reductions
are corroborated under the concurrent caller and measured common caller, with
unchanged output and budget contracts. Keep ordinary common-caller uncertainty
explicit. The existing loop-body fast helpers have different charging rules;
they cannot replace this path's original root/child steps and output checks.
The source-bound review retains the failed setup, rejected variants, controls and
all raw data; final CI must still qualify the complete proposed source inventory.
