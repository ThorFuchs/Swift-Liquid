# Public quality sprints

The quality program strengthens public presentation, documentation and repeatable
qualification while preserving the dependency-free Liquid core and released
1.0–1.3 contracts. A sprint is complete when its implementation and affected
`Scripts/ci.py` gates pass; a polished page or a larger test count is insufficient.

## Sprint 1 — public surface and enforceable documentation

Sprint 1 was merged in PR #11 and qualified on main:

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

Sprint 2 was merged in PR #12:

- Add fixed-seed Unicode scalar, JSON truncation/escape, parser boundary and exact
  UTF-8 capacity cases, with independent expected results and small reproductions.
- Fix the sanitizer stack exhaustion exposed at the public 128-level JSON
  boundary with an iterative reader, retaining value order and error policies.
- Replace sleep-driven inspection cancellation and the immediate loop-cancel race
  with explicit barriers, cancellation precedence and healthy invocation reuse.
- Admit versioned Swift Testing streams against a reviewed exact inventory, retaining
  raw events, per-function/case completion and actual skip/issue/cancellation counts.
- Exercise failed, disabled, known-issue, empty and filtered runs with an isolated
  dependency-free runner probe; reject damaged evidence without reading success text.
- Repeat the selected adversarial/cancellation cases twice under parallel execution;
  retain full AddressSanitizer and the five ThreadSanitizer concurrency checks.

See [testing and evidence](Testing.md) for reproduction, adapter details and limits.
Synchronous inspection tests establish entry cancellation and reuse, without claiming
cancellation at a selected in-flight instruction or a latency guarantee. The JSON
reader uses an explicit stack; public APIs, admitted nesting, fixture bytes and root
dependencies remain unchanged. The reviewed baseline is 73 functions and 2,104 parameterized cases; counts alone establish neither complete
conformance nor performance. Acceptance requires affected native, safety and docs
qualification and retained source-bound CI evidence.

## Sprint 3 — contribution isolation and package discovery

The audit verified that `xcode-27` is already GitHub's hosted macOS preview image;
it is not self-hosted. No self-hosted runners were registered in the repository at
the audit date. Sprint 3 makes this hosted path explicit and enforceable:

- Require provider-hosted admission before checkout and retain runner/image provenance.
- Audit workflow triggers, token permissions, action pins, cache and checkout policy,
  complete gates and the separate main-only Pages boundary; test meaningful failures.
- Preserve all-external-contributor approval, read-only token defaults and the live
  Pages environment's main-only deployment policy. Document what approval does.
- Qualify a clean public-URL library/CLI installation of the immutable 1.3.0 anchor
  in an additional CI/release lane, preserving candidate/archive qualification.
- Verify canonical release/docs links and package-index status. Submit the one-URL
  registration as a separately reviewed external change after explicit maintainer
  authorization; add no premature badge.

See [contribution isolation](ContributionIsolation.md) and
[package discovery](PackageDiscovery.md) for the audit, maintained checks and limits.
Acceptance includes workflow-policy regressions, actual hosted runner receipts,
clean published installation, all affected native/docs gates and the clean archive.
No core runtime, public API, fixture pin or root dependency changes are required.

## Sprint 4 — measured maintenance

Review benchmark variance, cancellation responsiveness and representative larger
workloads. Select the immutable 1.3.0 baseline when preparing the next release's
matched comparison; retain historical measurements. Investigate material flags
without rerunning until a preferred result appears. Keep logical quota, elapsed
latency and process-memory claims separate.

New platform support or language extensions remain explicit scope decisions.
A release requires all gates and a separate publication request; these sprints
alone do not authorize another version tag.
