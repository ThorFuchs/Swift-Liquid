# ADR: isolated render host-input visibility

Status: **adopted; C implemented after explicit maintainer approval**.
Signed **Codex, 2026-10-16**, recording the maintainer’s instruction in this session.

## Historical deferral at `8ab1632`

Pinned Ruby `context.rb#new_isolated_subcontext` preserves `static_environments`,
while `tags/render.rb` starts a fresh local scope. The liquid-spec runner supplies
JSON host inputs through those static environments. The proposed C overlay design
therefore returned `T|` for a partial reading host title and caller-local local,
without exposing the assignment. Named bindings, nested render, render-for,
null/missing, counters, recovery, budgets and concurrency passed targeted controls.

The original authored test
`InspectionTests.concurrentRendersAndInspectionShareOnlyImmutableTemplates`
(`Tests/LiquidTests/InspectionTests.swift:104`, assertion at line 114) uses:

```liquid
{{ name | upcase }}{% render 'card' %}
```

The partial is `{{ name }}` and host input is `name: n7`. Its unchanged expectation
is `N7`. Pinned Ruby static-environment contexts and C return `N7n7`, in lax,
strict and strict2, under raising and recovery. The full C development lane records
40 assertion failures in this one existing function. Pinned corpus cases are not
changed, and the failure is not relabelled flaky, operational or passing.

The governing R3 instruction prohibits changing expected bytes to increase passes
and requires preserving historical gates. It also permits deferring C. Updating
this old assertion would require an explicit reviewed compatibility decision;
a targeted Ruby match alone cannot authorize it. Final source reverts C completely
and retains A/B. The experiment's two independent improvements are excluded from
final repair credit. This is a scope decision, not a claim that Ruby lacks globals.

## Adopted contract

Map original `LiquidEngine` context inputs to immutable admitted host roots.
Keep assign/capture/loop aliases and explicitly passed partial bindings in local
invocation overlays. Nested render should inherit the original roots, not its
parent's named-argument overrides. Explicit bindings, including null, shadow
roots in that invocation. Include shares caller state. Counters and generated
forloop state remain isolated; deliberately supplied host fields remain data.

Admit roots once, share their immutable backing values, and avoid copying the
whole input into each nested render. Save/restore only mutable overlays and
counters. Preserve shared cumulative budgets, diagnostics and cancellation. No
loader, implicit I/O, reflection, public strict-variable option or global registry.

## Maintainer decision and bounded assertion correction

On 2026-10-16 the maintainer explicitly instructed: “adopt Ruby’s render
host-global semantics, correct only the conflicting authored assertion, implement
C, and rerun all gates. Keep pinned fixtures unchanged; no merge or release.”
This resolves the historical gate conflict. The single existing assertion changes
from `N\(index)` to `N\(index)n\(index)`; its source, forty tasks and inspection
checks remain intact. Pinned Ruby returns `N7n7` in all three parser modes and
raising/recovery for the exact `n7` reproduction. No pinned expectation changes.

The implementation restores the retained host-root/local-overlay design.
Supplementary regressions cover original inputs, local shadows, named/null
bindings, nested render, render-for, includes, counters, exact old-assertion
reproduction, error recovery/location, no ambient loader, admission/output/step/
nesting limits, shared-template concurrency and deterministic cancellation.
Root inputs are admitted once and retained beneath scope overlays; nested render
neither copies the root map nor resets cumulative budgets. No public API change.

All final gates bind to one clean source commit after the last code/docs edit.
The return retains the original partial packet, failed C experiment and revert,
this explicit decision, exact assertion diff and new source-bound receipts.
Independent mismatches remain failures; the existing suite population, eligibility,
reference pins, expected bytes and comparator remain unchanged. The separate
case-operand reevaluation difference and range-property failures remain deferred.
No merge, tag, publication or performance exercise is part of this correction.
