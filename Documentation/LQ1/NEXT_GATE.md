# Next gate: maintainer review, not release

Signed **Codex, 2026-10-15**. No public API, push, tag or release approval is implied.

Review the local source diff, the nonpositive-truncate rule and its provenance,
the complete missing-features configuration, all excluded rows and the raw traces.
The independent gate currently fails. Historical qualification success cannot
turn those mismatches into passes or justify a full-language compatibility claim.

Before merging, reconcile this branch from the merged sprint-2 base with concurrent
quality sprint 3. Rerun source-bound native, safety, docs, pinned reference and
relevant platform lanes after resolving conflicts, plus the opt-in liquid-spec
lane. Preserve both initial and repaired evidence. Match every executed row to a
source file/line/mode and keep reference failures distinct from Swift mismatches.

Triage lowest-complexity core candidates first: lax filter syntax, conditional
alternatives, counter/loop behavior, cycle identity and explicit partial scope.
Investigate the accepted-invalid parser cases separately from error wording.
Ten recursion quota outcomes stay operational; do not loosen limits or convert
them into inline language errors to increase matches. Ten pinned-Ruby expectation
mismatches need a test-suite/reference-policy review before engine changes.

Select only E3 for a future additive API RFC at this stage. Specify source indices,
Unicode spans, local/external paths and diagnostic behavior before code. E1, E2,
E4 and E5 remain deferred. If any proposed fix requires default changes,
nonstandard tags, reflection, relaxed quotas or numeric normalization, stop that
fix and return a narrow RFC with the failing evidence intact.

Production recordings and Dawn require a separate portability manifest. Linux,
WASI and device execution require their own real gates before claims. Competitive
performance belongs to EngineBench and was not measured here. Publishing any
version needs a separate maintainer request and its complete release gates.
