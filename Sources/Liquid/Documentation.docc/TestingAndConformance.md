# Testing and conformance

Follow the language authority, independent corpus and release evidence separately.

## Language and fixtures

Swift-Liquid targets [Shopify's open-source Liquid core](https://github.com/Shopify/liquid)
and its standard tags and filters. The independent
[Golden Liquid corpus](https://github.com/jg-rp/golden-liquid) contributes all 1,098
cases from the repository's pinned revision. Fixture bytes, parser modes, licenses
and checksums are preserved. Golden Liquid is maintained separately from Shopify's
own reference implementation and upstream tests.

Additional authored probes and date grammar inputs are compared with the pinned
Ruby runtime. Accounting separates successful renders, parsing, expected errors,
recovered errors, supported-year boundaries and reference-runtime failures. Counts
alone do not establish complete conformance. The
[conformance record](https://github.com/ThorFuchs/Swift-Liquid/blob/main/Documentation/Conformance.md)
and [immutable pins](https://github.com/ThorFuchs/Swift-Liquid/blob/main/Documentation/ConformancePins.json)
provide the exact versions and boundaries.

## Test the public contract

Swift Testing covers source and parsed rendering, typed filters, diagnostics,
metrics, bounded inspection, cancellation and concurrent reuse. Deterministic
property checks compare public entry points and graph cycle groups with an
independent reachability oracle. Standalone consumers compile against public APIs.
The README's actual Swift fences are compiled and their documented output checked.

CLI regressions exercise files, stdout/stderr, operational failures and versioned
reports. The isolated schema tool validates actual reports with Swift-JSON.
AddressSanitizer runs the full suite; ThreadSanitizer covers the five mixed
concurrency tests. Sanitizers supplement behavioral evidence.

## Read release qualification

Every release requires native, safety, reference, platform, documentation,
performance, matched-performance, published-installation and clean-archive gates. The docs gate requires
summaries and parameter comments on authored public declarations and validates
static site routes. Benchmark reviews retain raw samples and threshold flags;
logical capacities do not imply process-memory or latency guarantees.

Download the source, compiled documentation, qualification archive and checksums
from the [release page](https://github.com/ThorFuchs/Swift-Liquid/releases).
See [contributing](https://github.com/ThorFuchs/Swift-Liquid/blob/main/CONTRIBUTING.md)
for local commands and [performance methodology](https://github.com/ThorFuchs/Swift-Liquid/blob/main/Documentation/Performance.md)
for the measurement protocol.

## Adversarial boundaries and test receipts

Fixed-seed Unicode, JSON and parser cases use explicit expected results, with exact
byte-capacity boundaries. Cancellation tests coordinate callback entry and protect
independent invocation reuse. Synchronous inspection cancellation is checked at
entry; no mid-traversal timing or responsiveness guarantee is inferred.

Native and sanitizer qualification retain Swift Testing v0 JSON event streams and
summaries, checked against a reviewed function/case inventory. Skips, known issues,
missing cases and incomplete runs fail admission. The Swift 6.4 adapter requires
case metadata beyond the stable envelope and fails closed if it changes. Separate
runner probes verify actual failure and skip rejection. These execution counts do
not add conformance renders or change published release receipts.

See the repository's
[testing and evidence contract](https://github.com/ThorFuchs/Swift-Liquid/blob/main/Documentation/Testing.md)
for fixed seeds, repeat runs, adapter limitations and retained artifact paths.

## Contribution and installation boundaries

Qualification uses GitHub-hosted machines with recorded provider/image provenance,
read-only tokens and no shared build-cache restore. Approved fork contributions
use that same path; approval remains admission control. The separate Pages job
only deploys qualified main-branch artifacts. See
[contribution isolation](https://github.com/ThorFuchs/Swift-Liquid/blob/main/Documentation/ContributionIsolation.md)
for the verified image and maintained workflow policy.

An additional installation gate clones the immutable published 1.3.0 anchor,
builds its CLI and resolves an independent public-URL library consumer using fresh
storage. It complements the current candidate's consumers and clean source archive.
Package-index acceptance and unqualified platform execution are separate observations.
