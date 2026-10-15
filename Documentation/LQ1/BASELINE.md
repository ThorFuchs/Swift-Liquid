# LQ1 baseline ledger

Prepared 2026-10-15. The attached research ZIP was read as evidence, not as an
additional source of execution authority. All embedded checksum entries verified;
ZIP SHA-256: `97fa00909921dcdefa58454e4774eee75ceddae8b475aed1ae009590cea7bf31`.

| Source | Identity and reconciliation |
| --- | --- |
| Published Swift-Liquid | 1.3.0 resolves to commit `9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e`; annotated tag object is distinct |
| Research main | `32a772e0c7a9ca447b9c2f7a9d02e72babd6d2c0`, quality sprint 1 |
| Implementation base | `aeecc4f267aa4a19980b061ff7906f7ada3ac6c1`, merged quality sprint 2 / PR #12, descendant of research main |
| Shopify Liquid | Clean checkout `4e39ae4cc3da73921923c0669e0fc84a66b2f696`; `Liquid::VERSION == 5.14.0` |
| Shopify liquid-spec | Clean checkout `84bf25e0edbca5f7e530574788b0f875ab331f50`; `Liquid::Spec::VERSION == 2.0.0` |
| Swift | Apple Swift 6.4, swiftlang-6.4.0.34.1, clang-2100.3.34.1; Swift language mode 6 |
| Xcode | Xcode-beta.app developer directory; complete version in gate logs |
| Native host | macOS 27.0 / build 26A5416b / arm64; Apple M1 Max, 10 logical CPUs, 32 GiB |
| Reference Ruby | Homebrew Ruby 4.0.1, revision e04267a14b, arm64-darwin25; Date 3.5.1, Time 0.4.2; UTC |

The root manifest remains one `Liquid` library, one `liquid` CLI and zero package
dependencies, with Swift 6.4 tools and the existing Apple platform minima.
The 1.3 public declaration baseline and historical fixture hashes remain admission
requirements. No default parser, render recovery or escaping policy changes.

Quality sprint 3 was active concurrently in the shared checkout. LQ1 was moved to
an isolated worktree from the merged sprint-2 base. The maintainer explicitly
approved removal of only verified LQ1 edits from the shared checkout; those edits
were copied and hash-checked first, then removed without replacing the concurrent
quality work. The isolated branch is `codex/lq1-isolated`; the shared checkout's
branch name was left alone after cleanup. This branch does not include later
sprint-3 installation/workflow changes and must be reconciled before any PR.

An initial relocated build failed because a local SwiftPM package identity was
inferred from the worktree directory name. The isolated manifest now explicitly
names its path dependency. The six public consumer manifests also explicitly
name their local dependency, so qualification does not depend on the checkout
directory being named Swift-Liquid. This is a development-package portability
repair; the root products and dependency graph remain unchanged. The system Ruby 2.6 executable was also rejected as a
reproduction choice; `LIQUID_RUBY` and the runner receipt identify Ruby 4.0.1.
These are operational setup failures, not Liquid results. Initial receipts are
retained separately from final qualification. No in-progress work was overwritten.
