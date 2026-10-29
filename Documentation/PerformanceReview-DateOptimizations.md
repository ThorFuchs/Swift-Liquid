# Targeted date normalization and matching investigation

<!-- Fill only from independently admitted, complete artifacts. -->

## Decision

Prepare the **ASCII normalization fast path only** for final qualification. It
meets the predeclared performance rule on both RFC source and reused-template
workloads: CPU and wall medians fall by 11–13% under actor callers and 19–21% under
concurrent callers, all three blocks improve, and corresponding identical-source
aggregate drift stays below 0.8%. This supports those selected warmed workloads
on this host. It does not establish a universal date speedup.

Reject the matching-range-only candidate. Its ISO/RFC observations do not meet the
same rule under both callers. Keep the original matching range, captures and
mutation code. Neither candidate is combined with another runtime optimization.

The final patch adds public source/parsed regressions across all four rendering
policies for ASCII replacement runs, NUL/control bytes, Unicode/non-BMP/decomposed
prefixes, invalid-input byte preservation, the 128/129-byte boundary and lowercasing that
expands an admitted spelling beyond the parser bound. Existing
concurrent date reuse now mixes ISO, RFC and Unicode-fallback inputs under the same
engine. Final source-bound CI receipts qualify that patch separately from the
experiment; the measurements below use the exact same library bytes.

The two candidates are independent. Neither changes recognition order, grammar
expressions, capture spelling, quotas, public async entry points, cancellation
checks or the public date-input bound. This experiment does not compare an
optimized production release with 1.3.0; it compares two small candidates with
merged PR #22 main. Historical date and filter flags remain open.

## Baseline qualification

PR #22 merged as `1c37b11f1487453772aaae9e6be0cfd75ab2af01` after all nine
lanes in [38944449458](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38944449458)
passed. Reviewed head `a87fddf14c7eccf79c8fecd7b2040519a111a74d` and CI synthetic
merge `8737e897310bd9a89306b200fd37a4f2c31df108` had identical trees. Independent
admission verified 206 exact source hashes in ten receipts, original Swift Testing
streams, reference outcome categories, CLI/schema checks, public API, simulator
builds and clean source/archive checksums. All 50 benchmark comparisons and block
effects were recomputed against comparison SHA-256
`ba9bb7745da656ba522e366b977aff619952b55d585eaeb0dfc5a1c824582342`.
No median flags appeared; 25 common and 22 metrics spread flags remain. Ordinary
date source +0.492% and reused +0.355% have mixed-sign blocks. Measured reuse
−6.302% also reverses. These results clear no earlier regression.

Fresh-main run [38946919220](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38946919220)
has independently admitted primary receipts for that same merged source. All 50
matched comparisons and block effects were recomputed against SHA-256
`ce3f08d3c924bc7328cbcdf016c6d59bdd170f470047109dbc50fe779cca4646`:
zero median flags, 20 common and 15 metrics spread flags. Ordinary date source
+1.110%, reused +1.388%, measured source +1.485% and measured reuse +1.099% all have
mixed-sign blocks and spread flags. No historical date or filter flag is cleared.

All nine fresh-main lanes and Pages passed. Independent admission verified the
same 206 source hashes in ten receipts, original debug/release/ASan and repeated
adversarial/TSan streams, reference categories, four compile-only simulator SDKs,
published-URL installation, clean native rebuild and two archive checksums. Root
manifest and ten pinned fixture/compatibility files remain byte-identical to 1.3.0.
The 126 public declarations remain unchanged. Maintenance evidence retained 200
runnable cancellations, zero completed samples and no latency deadline. Runtime
qualification is macOS 27 / Swift 6.4; simulator builds do not establish device
execution. Canonical-equivalent filename tests were unavailable on the normalizing
filesystem and are not counted as passed.

## Frozen candidates and semantic boundary

The [frozen diagnostic source](https://github.com/ThorFuchs/Swift-Liquid/tree/8595bb66aa1d18c68361ae9d63f411812af07526)
and [predeclared plan](https://github.com/ThorFuchs/Swift-Liquid/blob/8595bb66aa1d18c68361ae9d63f411812af07526/Documentation/OptimizationStudyPlan.md)
identify the source, candidate transformations, workloads, command order, review
thresholds and adoption rule before timing. The diagnostic branch replaces CI for
one finite experiment and must never merge.

The normalization candidate replaces the regex initializer operation only for
ASCII input. It scans UTF-8 bytes, copies the exact allowed ASCII set, and replaces
each maximal excluded run with one ASCII space. If it encounters any non-ASCII
byte, it discards the partial buffer and applies the original expression to the
whole original input. This preserves ICU Unicode classification. No global cache,
mutable registry, package dependency or new public declaration is introduced.
The temporary byte buffer belongs to that initializer call.

The matching candidate changes only the full-input range in the original `find`
helper from `NSRange(input.startIndex..., in: input)` to
`NSRange(location: 0, length: input.utf16.count)`. Expression lookup, first-match
options, capture conversion and `take` mutation remain byte-identical. It does not
replace regular-expression matching with a handwritten grammar. Neither candidate
is combined with the other in this experiment.

Before timing, a standalone equivalence program checks 17,844 inputs: all 128 ASCII
single bytes, all 16,384 byte pairs, Unicode/decomposed/non-BMP/digit/whitespace
prefix/suffix mixtures, long ASCII inputs and 1,024 deterministically seeded mixed
strings. It compares normalization bytes with the original ICU expression, checks
both whole-input ranges, and compares every first-match/capture range from all 26
original expressions: 463,944 checks. Its normalized-byte FNV is
`6c5d516fbf973470`. These are finite equivalence observations, not a proof for all
possible strings or future ICU versions.

The baseline and both candidates separately passed the hosted native and pinned
reference lanes before timing. Raw debug/release streams each admit 81 functions
and 2,178 parameter cases; each native lane repeats the 18-function/64-case
adversarial/cancellation profile twice. Each reference lane retains 1,502 renders,
337 grammar parses, 132 expected errors, 26 recovered errors and 35 supported-year
boundaries, plus 15 separate host-extension renders. No reference failure or skip
is counted as a render. All eight binaries and sixteen caller/order validations
(192 output records) precede timing. Local development qualification, 48 public
outputs and the same equivalence program passed without admitting local timings.

## Measurement protocol

Four independently built variants use the same merged baseline: unchanged
`controlA`, unchanged `controlB`, normalization only and matching only. Both
consumer kinds link their unaugmented production library. There is no diagnostic
bridge, parser suffix, extra library API or audit subtraction. All eight release
binaries build with the same `-Xswiftc -g` flags before timing. Source inventories,
parser bytes, library fingerprints, binary hashes/UUIDs, probe/config hashes,
compiler, virtual hardware, loads and exact commands are retained.

The common consumer and manifest come byte-for-byte from pinned 1.3.0. The common
consumer still measures all 26 ordinary/measured render and inspection records.
A separate public consumer renders six inputs in source and reused-template modes:
ISO fractional offset, RFC timestamp, a Unicode-prefix timestamp exercising the
fallback, invalid input, interpolation and a standard-filter chain. Its explicit
`@MainActor` and `@concurrent` batch bodies are otherwise identical. Every public
call retains the engine's normal execution semantics; there is no added per-call
async wrapper. Templates and contexts are prepared outside timing; source-mode
calls still parse during each render.

Each comparison runs three serial ABBA blocks, six runs per side. Block 2 reverses
comparison and caller order; public record order alternates forward/reverse with
block-2 polarity reversed. There are 108 complete runs, 1,800 raw workload records
and 222 comparisons: three candidate/control comparisons, each with 26 common,
24 actor and 24 concurrent records. Twenty-five samples follow ten warmup samples;
each batch contains 100 calls. All 3,500 calls per record, including warmups, check
expected UTF-8 output and update FNV inside the clocks.

Public wall time uses `ContinuousClock`; CPU uses whole-process `getrusage` user
plus system time with microsecond accounting. Both include the consumer audit and
bookkeeping. CPU is not exclusive parser CPU, CPU minus wall is not executor wait,
and p95 describes batch averages rather than individual render tails. Warmed,
uncancelled runs provide no cold-start, cancellation-response, process-memory or
other-engine comparison. The common consumer reports wall time only.

Raw samples, median/p95, six run medians, MAD/range and three block changes are
retained. Absolute aggregate median changes and either side's run range at or
above 10% trigger separate flags. These are descriptive thresholds, not confidence
intervals. Identical-source controls are observations, never correction factors.
No timing-driven retry, discarded sample, trimming or scheduler-cause imputation
is allowed.

## Results and complete flag review

Timing ran on 2026-10-16 from 18:47:06 to 18:49:42 UTC after setup completed.
The complete cohort is [38947177449](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38947177449).
The [aggregate appendix](PerformanceReview-DateOptimizations-Data.md) retains every
one of the 222 comparisons. There are **20 median flags and 146 spread flags**:

| Comparison / consumer | Records | Median flags | Spread flags |
| --- | ---: | ---: | ---: |
| normalization-common-ordinary | 26 | 3 | 20 |
| normalization-public-actor | 24 | 4 | 10 |
| normalization-public-concurrent | 24 | 8 | 8 |
| matching-common-ordinary | 26 | 0 | 20 |
| matching-public-actor | 24 | 2 | 18 |
| matching-public-concurrent | 24 | 2 | 20 |
| identical-common-ordinary | 26 | 1 | 13 |
| identical-public-actor | 24 | 0 | 13 |
| identical-public-concurrent | 24 | 0 | 24 |

Selected RFC normalization changes (positive means higher cost):

| Mode | Actor CPU / wall % | Concurrent CPU / wall % | A/A actor CPU / wall % | A/A concurrent CPU / wall % |
| --- | --- | --- | --- | --- |
| Source | −13.140 / −13.150 | −18.971 / −18.957 | +0.277 / +0.271 | −0.758 / −0.766 |
| Reused | −11.162 / −11.179 | −20.728 / −20.743 | −0.228 / −0.244 | −0.535 / −0.560 |

All twelve RFC CPU block changes lie between −20.984% and −8.709%; all twelve wall
block changes lie between −21.062% and −7.521%. Both modes satisfy the frozen ≥5%
rule in both callers/clocks with every block negative. No guarded Unicode or
non-date control, or common date record, shows an aggregate ≥10% slowdown with
all blocks positive. Identical-source drift is not subtracted from candidate
results and is not an equivalence bound.

The other flags and limitations remain material:

- Normalization's three common median flags are lower ordinary date source/reused
  (−14.675%/−14.897%, all blocks negative) and measured source (−10.381%, block 2
  reverses). Measured reuse is −6.483% and also reverses. All four carry spread
  flags. These are the unchanged common ISO workload; they do not generalize the
  explicit-caller ISO outcome below.
- Normalization's actor flags are the four lower RFC records. Concurrent flags
  comprise four lower RFC and four lower invalid-input records (−10.358% to
  −11.105%, all blocks negative). Invalid-input timing is not evidence of a
  successful date render. Explicit concurrent ISO source/reuse has a slower first
  block despite lower aggregates; ISO does not independently meet the rule.
- Unicode-fallback normalization changes are +0.102% to +1.571% CPU and +0.124% to
  +1.598% wall. Actor and concurrent reused Unicode CPU/wall blocks are all positive;
  these costs are retained below the guard. Concurrent reused-filter CPU/wall
  +3.448%/+3.407% also have all-positive blocks. Common interpolation reuse is
  +5.972%, all-positive, with a 65.283% baseline run range. None is silently
  reclassified as zero cost or corrected with A/A observations.
- Matching has no common median flags. Its actor interpolation reuse is
  −12.282% CPU/−10.240% wall, all-negative blocks, despite changing only date code;
  this is not attributed to an interpolation optimization. Concurrent invalid
  reuse is −10.180%/−10.186%, all-negative. Its selected concurrent ISO reused
  records clear 5%, but actor records do not. RFC stays below 5%; actor source
  blocks reverse. There is no corroborated both-caller date improvement.
- Identical-source common interpolation reuse is **+17.750%**, all-positive blocks,
  with a spread flag. Actor public A/A has 13 spread flags; concurrent public A/A
  has a spread flag on every record. Corresponding RFC aggregates stay below 0.8%
  absolute drift, but concurrent RFC blocks reverse and differ by up to +8.65%.
  No scheduler, code-layout, physical-host or causal historical explanation is
  inferred from these observations.

The host reports Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS 27.0.1 arm64,
`VirtualMac2,1`, three virtual Apple M1 CPUs and 7 GiB RAM. One-minute guest load
before runs ranges from 1.231 to 2.520. Physical-host isolation, thermal state and
clock frequency are unknown. There are 21,600 retained public CPU samples and no
zero CPU observations. This is one hosted cohort; no universal speedup, exclusive
normalizer cost, cold-start benefit, zero overhead or historical clearance follows.


## Reproduction, failures and retained evidence

The initial diagnostic workflow at `3e2bc3a892c33c31de08af7df8b6c0a932718651`
failed validation in [38947092841](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38947092841).
A manual dispatch returned HTTP 422 because `runner.temp` was used in an unsupported
job-level environment field. No runner or measurement started. The sole correction
sets the reference path through `RUNNER_TEMP` and `GITHUB_ENV` in the first step,
then refreezes at `8595bb66aa1d18c68361ae9d63f411812af07526`. Candidate and consumer
bytes and the measurement plan are unchanged. This setup failure is separate from
the complete cohort; no timing result was selected or discarded.

The artifact `liquid-normalization-matching-study` (ID `12068201268`, 7,364,296
bytes, 30-day Actions retention) has ZIP SHA-256
`0c3d9d95122022a31aba54c29fd0ba62f3caa1432e30c4cef163f9556c3aeebd`.
The study JSON SHA-256 is
`32e7257acc41964016960432675bcba2395a74aea87961b23e7f0f85fd0ab7e8`.
Independent admission verified the ZIP digest, all 457 checksummed files (plus
the checksum manifest), exact frozen tools and parser transformations, all eight
binary hashes/UUIDs, source-bound original test/reference streams, all 192 untimed
payloads, exact commands/order, all 1,800 raw workload records, output checksums,
raw sample summaries, six-run distributions, block effects and both flag lists.
All 222 rows were reviewed; no observation was trimmed or retimed.

Unchanged control libraries have SHA-256
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.
Normalization-only library SHA-256 is
`e4ac4e173afbb6ae5b297cfd9946cf42b5e824aee5308685065b3da0f62dffe8`;
matching-only is
`b4862bf9333bd6c1a1c94c94624b91fcafef159c0469dea8537cc1d88bd2eb15`.
Every other library file is byte-identical to the merged baseline. The final
production patch must match the measured normalization-only fingerprint. Raw
measurements, qualification records, binaries and private review files remain
outside Git; the frozen public diagnostic source permits reproduction after
artifact expiry. The public appendix retains all aggregate effects and flags.

Historical date +12.005%/+11.9367%, earlier fresh-main ordinary-date
+13.999%/+12.711%, measured date-source +10.181%, and the adverse concurrent filter
control +10.417% CPU/+10.361% wall remain unresolved. The prior operation study's
107 median flags and 852 spread flags, including substantial identical-source
changes, remain in its [report](PerformanceReview-ParserOperations.md) and
[complete appendix](PerformanceReview-ParserOperations-Data.md). A quieter later
comparison does not erase them.
