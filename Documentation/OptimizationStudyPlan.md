# Frozen normalization and matching optimization experiment

Freeze this plan, candidate bytes, probe, workloads, driver and workflow before timing.
Common baseline is merged PR22 main `1c37b11f1487453772aaae9e6be0cfd75ab2af01`. No release or follow-up merge.

Two independent candidates:
1. ASCII normalization: same allowed bytes and maximal-run replacement as the pinned
   ICU expression. Encountering any non-ASCII byte falls back to the original whole
   string regex. No grammar/recognition order, quotas or cancellation changes.
2. Matching range: only replace NSRange(input.startIndex..., in: input) with
   NSRange(location: 0, length: input.utf16.count) in the original find helper.
   No capture, matching expression, options or mutation changes.

Never combine these candidates in this experiment. Independent identical-source
controlA/controlB builds provide an A/A comparison; they are not correction factors.
Before timing: standalone equivalence check (17,844 inputs; 26 original expressions;
463,944 complete-range/capture checks), native lane plus pinned Ruby reference lane
for baseline and each candidate, build all eight binaries, validate all sixteen
public caller/order combinations and check output payloads independently in Python.
Native admission uses original checked inventories and keeps cancellation/adversarial
cases; no test count establishes complete conformance.

Four independently built variants: controlA, controlB, normalization, matching.
Unaugmented production library in both binary kinds. No suffix/public probe API.
Common binary uses the byte-pinned 1.3.0 common consumer and manifest. Public binary
uses six workloads (ISO fraction/offset, RFC, Unicode-fallback timestamp, invalid
input, interpolation control, filter-chain control), each source/reused under explicit
@MainActor and @concurrent batch callers. Caller bodies are generated identically;
each actual public render still crosses whatever async boundaries the engine defines.
No per-call wrapper boundary. CPU is whole-process getrusage, wall ContinuousClock;
output equality and FNV audit are inside both clocks. No exclusive parser CPU or
executor-wait attribution, per-render-tail, memory or cancellation-latency claim.

Build release with identical -g flags. Record all source/library/probe hashes, eight
binary hashes/UUIDs, compiler, virtual host identity, loads and every command. No
builds or parallel measurements between timed runs. Run three serial ABBA blocks
for each of normalization-v-controlA, matching-v-controlA and controlB-v-controlA.
Each block executes common, actor, concurrent (reverse callers in block 2); comparison
phase order reverses in block 2. Public records forward/reverse alternate by position
with polarity reversed in block 2. Thus 108 runs, 26 common plus 24 per public caller
per comparison = 222 comparison records; six run medians each variant/phase. Twenty-
five retained samples, ten warmup samples, 100 calls per batch in both consumers.
Retain raw samples, checksum of all 3500 audited calls, median/p95, six-run median,
MAD/range, three block changes and every >=10% median or run-range flag. No timing-
driven retry, trimming or selection. p95 describes batch averages. Warmup excludes
cold-start inference. Timing runs are uncancelled and do not measure responsiveness.

Adoption criteria frozen before measurement:
- semantic equivalence and all relevant compatibility/cancellation gates pass;
- for at least one ASCII date workload, both callers and both CPU/wall clocks show
  >=5% lower six-run medians, all three blocks negative, and magnitude exceeds the
  corresponding absolute identical-source A/A median drift;
- no Unicode-fallback or non-date control shows >=10% increase with all blocks
  positive, and no common date record shows that persistent adverse pattern;
- inspect every record/flag and source delta; any ambiguous/conflicting result stays
  experimental. Passing criteria only justifies that selected workload, not general
  speedup or resolution of historical 1.3.0 regressions. If a candidate is adopted,
  qualify its final public patch through all regular CI lanes before a merge request.
  If neither qualifies, publish a docs-only follow-up with every result retained.

The finite workflow is diagnostic-only and must never merge. All setup errors and
partial attempts remain retained. A rerun is permissible only for a concrete setup
failure, with a frozen correction and disclosure, never because timing is adverse.
