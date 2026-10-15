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
