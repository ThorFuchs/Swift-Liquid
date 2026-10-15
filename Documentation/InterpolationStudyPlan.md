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
