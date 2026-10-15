# ADR: isolated render host-input visibility

Status: **deferred; C implementation reverted**.
Signed **Codex, 2026-10-15**. Maintainer decision pending.

## Evidence and incompatible requirements

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

## Proposed future contract, requiring approval

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

## Required next decision and qualification

Review whether the old authored expectation is an intentional supported contract
or an incorrect test of Ruby host-input semantics. Explicitly authorize any
expectation change with provenance; never alter Golden/reference/spec fixtures.
Then replay the retained C patch, add the exact conflicting case as a reviewed
public regression and re-run all source/parsed policies, all modes, alias/null/
nesting controls, concurrency, quotas and deterministic callback cancellation.
Full historical and independent gates must bind to the final reviewed SHA.
If the existing visibility behavior is retained, document the divergence and
leave the two source-backed failures measured. No silent compatibility switch.
