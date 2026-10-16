# Remaining caller/date investigation — frozen plan

This diagnostic branch must never be merged. Product candidate is frozen at
`61d0353ad6fc17566800a4c5c8abbbd611fea9ff`, Liquid SHA-256
`77b6ec497a99005c01a34a370ac727089b62a685c1a62f722e0337f8e0db7d55`.
Merged PR #16 is `e29ec2a639b8d73a1c885b541f1bcef408c9c2a7`, Liquid SHA-256
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.

Hypotheses: caller/executor round trips may dominate small ordinary calls; repeated
temporary String/Character construction may add avoidable strftime work. Do not
change public isolation annotations, cancellation polling, parser production order,
quotas, fixtures, root dependencies or library products to obtain a result.

Before timing, qualify the merged implementation with the new date tests ported
without changing library bytes, and qualify the immutable candidate, each through
`Scripts/ci.py --lane development`. Retain both receipts and raw test streams;
require 81 functions/2,178 parameter cases and public consumer/CLI checks.

Build all eleven binaries before any timing: immutable 1.3.0, 1.3.1, merged source,
scalar formatter candidate, and a separate identical merged-source build under
both the unchanged common caller and a driver changing only the entry to one
`@concurrent` call; plus a caller probe linked to the merged source. The common
harness/manifest remain pinned to 1.3.0 and retain all 26 records, checksums,
25 samples, ten warmups and 100 repetitions. Candidate library changes must be
confined to DateFormatting.swift; RuntimeBudget bytes and checkpoint counts must
match the merged source. Retain exact patches/manifests and optimized disassembly.

Three serial blocks each interleave ABBA comparisons of 1.3.0→1.3.1,
1.3.1→merged, merged→formatter, and merged→identical under both callers: 96 raw
runs/208 comparisons. Preserve every sample, median, distribution, block effect,
median flag and spread flag; independently recompute all of them. Ranges/MAD are
descriptive, not confidence intervals or evidence of independent samples. Do not
multiply separate comparison ratios to claim an overall result.

After each block, the same caller-probe binary runs actor/concurrent/concurrent/
actor. Its two otherwise identical bodies measure no-inline nonisolated empty and
cancellation-checking async calls, plus ordinary/measured reused interpolation and
date calls. Each retains the same warmup/sample/repetition counts, output audits
and checksums. Retain optimized SIL to inspect actual executor hops. These are
synthetic diagnostics: do not subtract probe time from whole-call measurements,
identify a sole cause, promise a scheduling bound, or change application executor
semantics. No probe result changes the historical common harness.

Adopt a runtime change only if repeated block effects and both callers support a
meaningful benefit beyond observed identical-source effects, without an unexplained
material adverse workload. Otherwise retain the investigation and reject the
candidate. Do not rerun until a preferred result appears. The final product source
must pass its affected/full gates before a reviewable PR is marked ready; this
study alone is not release qualification or authorization to publish.

Static review corrected a new test assertion before qualification: LiquidError does
not conform to Equatable, so match its quota case after expecting the error type.
The first queued dispatch was cancelled before timing; no library byte changed.
Retain that dispatch and this setup correction alongside the completed study.

The first running attempt passed both 81-function/2,178-case preflights and built
the probe, then its standalone SIL command failed to locate Liquid. This toolchain
places modules beside the product; include that product directory as well as the
conventional Modules directory. No timed sample existed. Keep the failed attempt
and qualify the same product bytes again before the corrected study.
