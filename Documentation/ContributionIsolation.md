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
requires `runner.environment == github-hosted`. Qualification receipts retain the
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

## Publish documentation

The separate Pages job runs only on `main` after the complete qualification matrix
and clean archive pass. It has the Pages/OIDC permissions, uses the `github-pages`
environment, and only configures/deploys the current run's qualified site. It does
not check out or execute repository code. The live environment's deployment branch
policy admits `main` only. PRs package their site for review and do not deploy it.

`Scripts/workflow_policy.py` audits these structural invariants with Ruby's standard
YAML parser, rejecting duplicate keys, aliases and object construction. Negative
regressions cover shared/dynamic runners, privileged triggers/tokens, secrets,
persistent credentials, overridden PR refs, caches, reduced qualification and
publishing without complete main gates. These checks aid review: a contribution
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
