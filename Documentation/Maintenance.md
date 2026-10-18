# Maintained development and CI operations

Thorsten Fuchs owns maintenance and integration decisions. This policy separates
engineering checks, explicit measurements, documentation deployment and release.
The configuration is effective only after the reviewed commit reaches GitHub and
the maintainer verifies its actual runs and protection settings. Local preparation
does not constitute a push, merge, deployment or gate acceptance.

## Everyday correctness

Run affected work through `python3 -B Scripts/ci.py --lane LANE`. Routine hosted
CI runs `native`, `safety`, `docs`, `reference`, `platforms`, `installation` and the
strict `archive` lane. Archive follows the six-lane matrix, consumes its own run's
documentation and rebuilds the full native lane from a Git-free export. It keeps
exact source/mode/provenance, literal inventory joins and asset checksums.

Use `LIQUID_SWIFTPM_FLAGS='--jobs 2'` for bounded local non-docs checks. Remove that
variable entirely for documentation. Reference needs a clean checkout at
`4e39ae4cc3da73921923c0669e0fc84a66b2f696`; the optional independent lane also needs
liquid-spec at `84bf25e0edbca5f7e530574788b0f875ab331f50`. Never repair a retained
historical reference in place or silently advance a pin. The schema tool retains
Swift-JSON 1.3.0 at `9517233ef0a3c1b961b738df58fe3ee4081d780c`. Installation tests
published Liquid 1.3.0, not an unpublished candidate.

`Repository correctness` evaluates both required dependency results with
`always()` and accepts only success. Matrix failures are not tolerated. Retain
superseded/cancelled runs; only the exact current head or verified synthetic merge
identity can satisfy a PR gate. Observe the real check context before requiring
it in main protection. A local checker cannot enforce hosted repository settings.

## Deliberate measurements

The `Controlled benchmarks` workflow is manual only. It requires a separately
recorded maintainer timing commission, full source SHA and explicit confirmation.
The checkout must be clean and equal both the dispatch SHA and requested SHA.
Canonical performance and matched-performance run serially, with immutable
1.3.0 baseline `9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e`. Existing sample policies,
thresholds, raw distributions and adverse flags stay unchanged.

The request helper validates identities, not human authority or a quiet host.
Agree the host/protocol/window and preservation policy in that separate commission
before dispatch. The workflow creates no automatic waiver or retry. Measurements
remain unaccepted until reviewed. PF1-005/PF1-006 are terminal; all 120 historical
performance dispositions and `HOLD_PERFORMANCE_PENDING_QUIET_WINDOW` persist.
PR23's optimization is a separate held line. No timing is part of closeout CI.

## Explicit documentation deployment

Generate and validate documentation in correctness; deployment requires its own
explicit approval and `Deploy admitted main documentation` dispatch from main.
Supply the exact main commit, successful push-to-main correctness run ID and
retained approval record. The admission checks the repository, workflow/run/attempt,
all required jobs, current main, artifact origin/digest and every declared site
body plus its source/build receipt. Artifact creation/finalization must lie within
the latest-attempt documentation job; stale same-run/source artifacts fail. The privileged Pages job executes no source.

Routine evidence excludes both raw DocC and site trees. The complete site travels
inside `site.tar.gz` with a digest-bound `site-transport.json` inventory, preserving
Swift declaration filenames containing colons, bytes, modes and provenance. Both
archive correctness and deployment admission validate the envelope; neither
renames generated paths or treats transport success as a release/deployment gate.

An absent/expired artifact, skipped/neutral prerequisite, PR run or moved main
fails admission. Reconsider the source rather than overriding the check. The
environment's main-only policy and effective permissions still need live readback
before deployment. The input record is not independent evidence of human approval.
No ordinary push, PR update or merge deploys the site.

## Compatibility, integration and release

The [conformance record](Conformance.md) identifies the exact R6 full independent
snapshot and known failures. New policy-only source may cite it only with a
verified unchanged-runtime/adapter/fixture bridge. Neither passing unit tests nor
an archive makes the independent conformance gate green. Known limitations need
an accountable maintainer, impact, disposition and release consequence.

Integrate through a reviewed PR, actual successful correctness checks and effective
main protection, using a history-preserving merge. Resolve conversations and retain
explicit whole-line/limitations acceptance. A single-maintainer review exception
requires an explicit decision; self-approval is not an independent platform review.
Never force push main or delete another session's unique work.

Release remains governed by [RELEASING.md](../RELEASING.md) and the unchanged
exact-source nine-lane packaging validator. Both timing lanes, benchmark flags,
compatibility decisions and explicit publication authority remain separate release
obligations. No workflow creates version tags or releases. Preserve F01–F14/F13,
the narrow C authority provenance limit, E01 and all original failed attempts.

After closeout's actual-main checks, work from a clean owned daily checkout on
accepted main. Feature scope and acceptance criteria require a separate commission;
this document neither creates a feature branch nor chooses the next feature.
Keep historical checkouts/resources until individually owned, inventoried and
restore-tested recovery supports an explicitly approved retirement.
