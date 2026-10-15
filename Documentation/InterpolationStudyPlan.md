# Bounded interpolation investigation

Recorded before observing the study. Baseline: published 1.3.1,
fb81cf4ff01f1bf098ceb5fff65638b1271294e0, Liquid fingerprint
50b372f97e4f3429647723b7c9ec8c4b8cca13759774fa069b369109b48fafa4.

Hypotheses: (1) exact native String conversion can avoid unrelated dynamic type
probes, preserving conversion precedence for every other runtime value;
(2) explicitly inlining RuntimeBudget.output may reduce a call/code-generation
cost while retaining the same cancellation-before-quota body. These are separate
variants; no cancellation checkpoint, quota, error or logical charge is removed.

Build baselineA, nativeString, inlineOutput, baselineB before timing. Retain every
source manifest, exact patch, compiler, hardware metadata and common disassembly.
Use the immutable 1.3.0 common harness/manifest, unchanged, with 26 records and its
25 samples/10 warmups/100 repetitions. It remains a comparison with 1.3.1 code.

A second authored driver changes only the common harness entry: one @concurrent
call surrounds all inner work. Workloads, inputs, checksums, sampling and timed
call boundaries remain unchanged. This separates recurring caller/executor
scheduling from costs observed when already running on the generic executor;
it does not establish scheduling isolation or replace the common comparison.

Three serial blocks, each containing ABBA baselineA/variant/variant/baselineA for
nativeString, inlineOutput and identical-source baselineB, under both drivers.
Six runs per side in each of six phases, all observations retained. Recompute all
raw summaries, output identities, median/MAD/range flags and three-block effects.
All builds finish before any timing. No other qualification job runs on this VM.
Physical host and thermal conditions remain uncontrolled; ranges are descriptive,
not confidence intervals. No selected retry or automatic speedup claim.

Assess all modes, especially ordinary/measured reused interpolation, against the
identical-source effects and block consistency. Prefer a narrow conversion change
if corroborated across drivers and larger than the control effect. Do not adopt a
variant solely because an aggregate flag looks favorable. Investigate material
adverse effects before promotion. Full public regression/cancellation, sanitizer,
reference, API/documentation and release benchmark qualification are required for
the actual proposed source. Keep the published 1.3.1 tag/assets unchanged.

## Follow-up after the first study

The first study (run 38819503018) rejected both initial variants. Native-string
reused gains were not corroborated on the concurrent caller; forced inlining
worsened common results. All 156comparisons and adverse runs remain retained.

Before observing follow-up timings, freeze candidate 65f66404e2ad1e62862d22db12c8c5a59001635b,
core fingerprint 6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a.
This candidate avoids internal async root/node calls for at most 3 text/raw/plain-
variable leaves, preserving all runtime budget/cancellation boundaries and fallback
semantics. Existing budget methods remain byte-identical to 1.3.1; the new multi-node
loop has its own cancellation site to match the general loop's original polling.

First qualify the actual candidate through Scripts/ci.py --lane development,
retaining raw 78-function/2166-case evidence plus consumers and CLI/schema checks.
Only after success, build baselineA/candidate/baselineB under common and concurrent
drivers before timing. Three interleaved ABBA blocks for candidate and A/A under
both drivers yield 48 complete runs and 104 comparisons. Keep all original sampling,
checksums, raw data, controls, distributions and flags. An improvement must be
assessed against control magnitude and block consistency, with special attention
to both reused-interpolation modes and all other workloads. Do not select retries
for preferred numbers. Full final-source qualification remains required.

The initial follow-up preflight (run 38822187059) passed 78functions/2166cases,
then failed the first consumer because its temporary checkout basename was
qualification. SwiftPM derives local dependency identity from that basename.
Correct only the temporary directory to qualification/Swift-Liquid; candidate
bytes, protocols, thresholds and planned sampling remain unchanged. No benchmark
sample existed before this setup correction. Retain the failed receipt and logs.
