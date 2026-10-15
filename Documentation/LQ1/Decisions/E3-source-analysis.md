# E3 — Richer source analysis and diagnostics

Status: sole future implementation proposal selected for RFC review; no code.
Signed **Codex, 2026-10-15**; maintainer approval pending.

Problem: existing inspection gives roots and literal dependencies, while authors
need paths and source locations. The independent parser track reports 43 invalid
cases reaching output and many rejected cases with incompatible diagnostics.
Better provenance can shorten each reproduction; it must not obscure grammar bugs.

Study an immutable source index using UTF-8 offsets with precisely defined scalar
line/column conversion and range endpoints. Keep original source spelling and
root/partial identity. Parser tokens/AST nodes should retain tag, filter and
expression spans internally before any public result type is proposed. Avoid
reconstructing locations by searching output text or rendered values.

A prospective additive result could report `variablePaths` with literal/dynamic
segments, local declarations vs external roots, nested partial provenance and
filter/tag spans. Loop aliases, assign/capture, increment/decrement namespaces,
render isolation, include sharing and branch-dependent declarations need explicit
static rules. Dynamic access remains unknown; report uncertainty rather than
claiming a required-input schema. Existing inspection APIs and JSON schemas stay
unchanged; a new schema/version needs separate review.

Never evaluate expressions, call filters, query host objects, render branches or
load partials during analysis. Admit only explicit source/parsed bundles under
existing cancellation and finite graph/source capacities. Reuse invocation-owned
traversals; a source index must not become an unbounded engine cache.

First review gate: an RFC with representative diagnostics and editor navigation,
source/parsed equivalence, multiline liquid/raw/comment and Unicode/CRLF cases,
partial scopes, dynamic keys and bounded cancellation. Compare the existing
1,857 parse-rejection diagnostic mismatches without weakening their expectations.
Grammar acceptance repairs remain a separate correctness backlog. Implement only
after the maintainer accepts semantics and the public compatibility design.
