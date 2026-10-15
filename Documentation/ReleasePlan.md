# Release 1.0 plan

The first release establishes open-source Shopify Liquid core as a focused Swift
package. Scope was selected by the maintainer on 2026-10-14.

Required gates:

1. Standard tags and filters; precise syntax and behavior contracts; rejected
   Rhoe extensions; documented parser-mode and numeric boundaries.
2. Every pinned Golden Liquid fixture evaluated; zero unexpected failures or
   skips; independent Shopify reference comparison with reference failures
   recorded separately; meaningful safety and concurrency regression tests.
3. Debug and release builds/tests in Swift 6.4; an external public consumer;
   working CLI with observable failures; resource and cancellation checks.
4. Repeatable native release benchmarks with checksums and environment receipts.
   No inherited performance claim without a matched reference experiment.
5. Compiled DocC, checked README examples, functioning documentation links,
   support and vulnerability-reporting routes, complete source/fixture licenses.
6. Reviewable public file inventory, reproducible source archive, exact-commit CI,
   immutable 1.0.0 tag, release notes, source/docs assets, and checksums.

Repository publication and a stable version release are separate milestones.
Publishing development source does not certify that the 1.0 gates passed.

The adopted [1.1 roadmap](Roadmap.md) adds scoped typed custom filters and read-only
template inspection. The [upstream feature review](Architecture/UpstreamFeatureReview.md)
records the remaining RhoeLiquid capabilities and why they are deferred or belong
in integrations. Custom tags, cache APIs, richer adapters, document rendering,
services, macros, inheritance and additional platform qualification retain their
separate design and scope decisions.

Qualification now includes explicit recovered-error parity, the Ruby Date/Time
grammar corpora, both public render paths, simulator-SDK library compilation,
and a deterministic source archive rebuilt from a clean extraction. Run every
technical lane at the candidate commit; publication and an immutable version tag
remain maintainer-controlled steps.

## 1.1.0 release gates

Retain every 1.0 gate and its reference accounting. Qualify typed filters and
inspection separately, including the three public consumers, 33 CLI cases,
AddressSanitizer and all three ThreadSanitizer concurrency cases. Run the new
`matched-performance` lane with the immutable 1.0.0 baseline after the other
qualification jobs; review every threshold flag before publication. The existing
`performance` lane additionally measures filters and source/reused inspection.

The final clean archive depends on both sets of measurements. Retain all eight
lane receipts, archives and checksums with the
[release notes](Releases/1.1.0.md). `Scripts/prepare_release.py` validates source
inventories and assets and packages the evidence without creating a tag or release.
Publication still requires the maintainer's explicit request, exact-commit main
qualification and version-resolution verification.

## 1.2.0 release gates

The maintainer adopted the [1.2 roadmap](Roadmap-1.2.md) on 2026-10-15: opt-in
render metrics and a CLI JSON metrics file. The [metrics contract](Metrics.md)
defines the API and schema. The roadmap retains compatibility and failure contracts,
public acceptance cases, measurement against immutable 1.1.0 and all eight final
qualification lanes. Publication requires completed gates and an explicit
maintainer request.

Retain all 1.0/1.1 compatibility gates, 54 test functions, four public consumers,
60 CLI cases, full AddressSanitizer coverage and four ThreadSanitizer concurrency
cases. Qualify all simulator SDKs, compile DocC and rebuild a clean source archive.

The matched lane pins immutable 1.1.0 and its unchanged 14-record harness. It also
runs 24 candidate enabled/disabled metrics comparisons across both error policies using the same binary,
with separate three-block ABBA sequences. All binaries build before timing.
Retain common per-run summaries, individual metrics samples, output checksums,
environment receipts and both flag lists. Review every flagged result before
preparing assets; passing measurements alone are not a regression verdict.

`Scripts/prepare_release.py` requires matching source inventories from all eight
lanes, reproducible archives and an explicit benchmark review bound to the exact
comparison checksum. It prepares the three archives, notes and checksums under
`Artifacts/release/1.2.0` without creating a tag or release. Qualify the merged
main commit again before any separately requested publication.

## Adopted 1.3 release gates

The [1.3 roadmap](Roadmap-1.3.md) adopts bounded partial-dependency inspection
and an explicit CLI dependency mode. Scope adoption and public API/JSON contracts
precede implementation. Preserve all 1.0–1.2 APIs, existing inspection/metrics
schemas, root package products/dependency graph and pinned fixture accounting.

Retain every existing release lane and add meaningful graph admission,
resolution, missing/dynamic reference, cycle, cancellation and concurrency cases,
an independent public consumer and CLI schema/failure checks. Compare existing
workloads against immutable 1.2.0 and measure graph construction separately.
The roadmap defines the delivery sequence, analysis bounds and acceptance gates;
scope adoption authorizes implementation; version publication requires a separate request.

The 1.3 candidate retains 65 test functions, five public consumers, 60 legacy CLI
cases and 24 dependency CLI cases, plus six positive/nineteen negative report-
schema vectors evaluated by Swift-JSON. Five concurrency cases run under
ThreadSanitizer; AddressSanitizer runs the full fixture suite. The duplicate-path
CLI vector is unavailable on normalizing macOS filesystems and is not a success.

Matched qualification pins immutable 1.2.0 commit
`8676da8059e71905632c233cffb438f8edbf51d2` and its unchanged 26-record harness,
including measured renders. Keep the separate 24-pair candidate metrics phase
and four graph construction records. All samples, output checksums, source and
harness identities must match the documented policy. The packaging gate rejects
missing measured-render records, missing samples, inconsistent summaries and
changed graph shapes/checksums. Review both threshold lists before preparing the
three archives, checksums and [1.3.0 notes](Releases/1.3.0.md). Publication requires
separate authorization and exact-main qualification after merging preparation.
