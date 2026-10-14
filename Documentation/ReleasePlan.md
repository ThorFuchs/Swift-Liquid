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

After 1.0, evaluate custom filter/tag APIs, opt-in application caches, richer
input adapters, and additional platform qualification. Rhoe document rendering,
services, macros, inheritance, and hosted storefront behavior need separate
product and compatibility decisions.
