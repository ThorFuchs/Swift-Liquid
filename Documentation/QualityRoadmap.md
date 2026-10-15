# Public quality sprints

The quality program strengthens public presentation, documentation and repeatable
qualification while preserving the dependency-free Liquid core and released
1.0–1.3 contracts. A sprint is complete when its implementation and affected
`Scripts/ci.py` gates pass; a polished page or a larger test count is insufficient.

## Sprint 1 — public surface and enforceable documentation

This change prepares the first sprint for review:

- Rewrite the README around installation, runnable examples, requirements and
  direct links to Shopify's reference, its pinned tests and independent Golden Liquid.
- Expand contributor guidance, issue/PR templates, ownership, community standards
  and the current-release security policy. Refine the GitHub About statement and topics.
- Provide a responsive documentation landing page and getting-started, CLI and
  qualification guides, retaining existing DocC URLs and offline archives.
- Require summaries and named-parameter comments on every authored public
  declaration, and protect the published 1.3.0 declaration baseline.
- Compile the README's exact six runnable examples and check documented output.
- Add deterministic public rendering properties and an independent cycle-group
  oracle, plus cancellable test barriers and cooperative suite time limits.

Acceptance includes native debug/release qualification, sanitizers, public
consumers, all existing fixture/reference accounting, DocC warnings as errors,
site route/asset checks and the clean source archive. CI retains source-bound
receipts. The new test baseline is 68 functions; the published 1.3.0 evidence
continues to describe its original 65 functions. The property cases add no
Shopify render-conformance count.

## Sprint 2 — adversarial behavior and test evidence

Expand deterministic parser/value/Unicode boundary exploration with minimized
reproductions and fixed seeds. Review timeout and cancellation cases, especially
in-flight synchronous traversals whose current tests use a scheduling delay.
Prefer controlled public behavior over production-only test hooks. Investigate
structured Swift Testing evidence so disabled, skipped and failed cases have
explicit accounting beyond human log summaries. Keep missing fixture and
reference failures terminal.

Acceptance requires a concrete regression or invariant for every addition,
repeatability under parallel execution and sanitizer coverage. Avoid tests that
merely repeat implementation details or inflate counts.

## Sprint 3 — contribution isolation and package discovery

Review self-hosted runner isolation and an ephemeral Swift 6.4 path for external
contributions. Requiring approval for all external fork workflows is an admission
control; it does not sandbox approved code. Maintainers must inspect workflow and
code changes before granting execution. Preserve least-privilege tokens and the
separate Pages deployment boundary. See
[GitHub's runner security guidance](https://docs.github.com/en/actions/concepts/security/compromised-runners).

Verify package-index listing and release discoverability, clean-checkout install
instructions and platform claims. A Swift Package Index submission contacts an
external project and should use a separately reviewed registration change. Do not
add a listing or build-status badge until its destination is live.

## Sprint 4 — measured maintenance

Review benchmark variance, cancellation responsiveness and representative larger
workloads. Select the immutable 1.3.0 baseline when preparing the next release's
matched comparison; retain historical measurements. Investigate material flags
without rerunning until a preferred result appears. Keep logical quota, elapsed
latency and process-memory claims separate.

New platform support or language extensions remain explicit scope decisions.
A release requires all gates and a separate publication request; these sprints
alone do not authorize another version tag.
