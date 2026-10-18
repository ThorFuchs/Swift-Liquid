# Contribution isolation

All qualification jobs use GitHub-hosted virtual machines. `xcode-27` is the
provider's macOS 27 preview image, with Xcode 27.2 selected for Swift 6.4. It is not
a repository-owned runner label. See GitHub's [image announcement](https://github.com/actions/runner-images/issues/14404)
and [installed software](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md).
The image is a preview; availability and installed SDKs can change. The compiler
version gate fails if the required toolchain is unavailable.

The 2026-10-15 repository audit found no registered self-hosted runners. PR #12's
native job reported the GitHub Actions runner group, consistent with the provider's
image documentation. The earlier roadmap treated `xcode-27` as potentially
self-hosted; this audit resolves that uncertainty. Do not attach a persistent,
shared host to this public repository's contribution workflows.

## Execute a contribution

Both same-repository and approved fork pull requests use `pull_request` and the
same hosted qualification path. GitHub disposes of the hosted job environment;
no repository workflow restores shared build caches. Before checkout, each job
requires `runner.environment == github-hosted` and exports its verified value through
`GITHUB_ENV` for subsequent steps. GitHub permits the runner context in step-level
environment values, not job-level environment values; see the
[context availability table](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#context-availability).
Qualification receipts retain the
provider environment, OS, architecture, image identifiers and checkout SHA. Read
[GitHub's hosted-runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
for the provider boundary and [compromised runners](https://docs.github.com/en/actions/concepts/security/compromised-runners)
for its limits.

Repository settings require approval from **all external contributors**, default
workflow tokens to read-only, and prevent workflows from approving pull requests.
Approval is admission control. Before approving a fork run, review the complete
workflow diff, scripts, package manifests, plugins, dependency changes and code
that those commands execute. Approval does not certify the contribution's intent.
A real external-fork submission is not fabricated as part of the local policy tests.

The workflow uses `contents: read`, no injected repository secrets and checkout
with `persist-credentials: false`. Actions use full commit pins. Artifact downloads
stay within their own run; there is no privileged workflow triggered by PR artifacts.
The artifact downloader uses an audited Node 24 revision. Changing runner labels,
action pins, triggers, caches or privileges requires explicit maintainer review.

## Correctness, measurements and documentation

Routine PR, main and manual correctness runs execute native, safety, docs,
reference, platforms and installation, then the full clean archive lane. The
always-run `Repository correctness` job accepts only successful qualification and
archive dependencies. Failed, missing, skipped, cancelled and neutral work cannot
be accepted by its program. The exact emitted check context must be observed on
an actual hosted run before branch protection requires it. Local semantic tests
are evidence about the policy; they do not install repository protection.

Timing runs only through a separately commissioned manual benchmark request.
Its exact clean dispatch commit must match the explicit full SHA; both canonical
lanes execute serially on one hosted job against immutable 1.3.0. Dispatch and
its request record grant no timing authority, host admission or performance
acceptance. All retained performance holds remain until separately decided.

Documentation generation stays in correctness. Deployment is a separate manual,
main-only workflow. Its read-only admission job verifies the repository, current
main, exact push run/attempt/workflow, all eight successful jobs, artifact origin,
API digest, complete site bytes and source/build provenance. Artifact creation
and finalization must fall within the latest-attempt documentation job timestamps;
an older attempt with the same run/source cannot supply its artifact. It does not execute
artifact contents. The separate privileged Pages job only configures and deploys
the admitted site; it checks out no source. Signed storage downloads receive no
GitHub authorization header. A moved main, expired/missing artifact, absent digest
or failed/neutral/skipped prerequisite blocks deployment. A retained explicit
maintainer deployment approval is required independently of these checks.

The site artifact includes its declared hidden `.nojekyll` file. Build artifacts
stay scoped to the generated lane directory. No PR artifact triggers a privileged
workflow. Sequential main checks cannot establish an atomic branch lock; a changed
source must be reconsidered. Live environment protection remains a separately
managed boundary and must be verified before any actual deployment.

`Scripts/workflow_policy.py` audits these structural invariants with Ruby's standard
YAML parser, rejecting duplicate keys, aliases and object construction. Negative
regressions cover shared/dynamic runners, privileged triggers/tokens, secrets,
persistent credentials, overridden PR refs, caches, reduced qualification and
routine timing, incomplete aggregate success and source-unbound deployment. These checks aid review: a contribution
can modify its own copy of a checker. They do not create a sandbox. The provider's
hosted isolation and separately managed repository/environment settings are the
actual boundary.

Run affected checks through `Scripts/ci.py`. The native lane runs policy regressions;
every lane audits the workflow before qualification. When checking live settings,
use maintainer credentials locally, never an administrator token inside PR CI:

```sh
gh api repos/ThorFuchs/Swift-Liquid/actions/runners
gh api repos/ThorFuchs/Swift-Liquid/actions/permissions/workflow
gh api repos/ThorFuchs/Swift-Liquid/actions/permissions/fork-pr-contributor-approval
gh api repos/ThorFuchs/Swift-Liquid/environments/github-pages/deployment-branch-policies
```

Review the values, retain a dated receipt outside Git, and report unavailable API
checks as unavailable. A permission error is not evidence of a secure setting.
