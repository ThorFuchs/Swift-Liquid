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
