# LQ1 scope decisions

Prepared and signed by **Codex, 2026-10-15**. Maintainer acceptance pending.
These are studies, not authorization to modify a public API or publish a release.

Preserve immutable Sendable inputs/engines/templates, invocation-owned mutable
state, zero root package dependencies and explicit partial admission. No parser
default, standard tag, output escaping, quota or recovery policy changes in LQ1.
The one core repair restores a reference rule within the existing value domain.

| Study | Decision for this wave |
| --- | --- |
| [E1 strictVariables](Decisions/E1-strict-variables.md) | Defer implementation; write missing/null and fallback semantics first |
| [E2 custom tags/blocks](Decisions/E2-custom-tags.md) | Defer; no registry or grammar plugin code |
| [E3 richer analysis](Decisions/E3-source-analysis.md) | Sole future implementation proposal selected for review, conditional on correctness backlog |
| [E4 host loader/output sink](Decisions/E4-host-io.md) | Defer to optional host module with explicit transactional semantics |
| [E5 JSON fidelity](Decisions/E5-json-fidelity.md) | Defer to optional Swift-JSON bridge; no core dependency |

**Next priority proposal: E3, source-index diagnostics and richer static analysis.**
The independent parser corpus exposes both accepted-invalid syntax and diagnostic
mismatches. Exact source spans would reduce reproduction and editor-navigation
work without executing templates or adding a hosting dialect. Start with an
internal source-index design and a separately reviewed public RFC. Acceptance
must demonstrate fewer unresolved diagnostic cases and useful variable-path/local
scope results, not a feature-count target. Review core parser/loop/cycle defects
before promising an additive release. E3 is a proposal; no public code is added.

Why the others wait: strictVariables needs missing-vs-null representation; custom
tags require grammar/AST/budget ownership; loaders/sinks require cancellation and
rollback rules; JSON fidelity requires explicit loss policy. None may be slipped
into an adapter to improve a pass rate. Hosted themes, arbitrary reflection,
macros, autoescape defaults and arbitrary-precision value expansion remain outside
this wave. Transport exclusions do not make those features core defects.
