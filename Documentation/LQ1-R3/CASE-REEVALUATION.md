# Case-operand reevaluation

The maintainer authorized this focused correction on 2026-10-16, after the
host-input wave at `8e058e4`. Pinned fixtures, existing authored expectations,
parser defaults, public APIs and finite policies remain unchanged. No merge,
release, benchmark or further runtime rule is part of this scope.

## Reference rule

Pinned Ruby Liquid `4e39ae4cc3da73921923c0669e0fc84a66b2f696` stores one
`Condition(left, '==', right)` for each when value. `Case#render_to_output_buffer`
evaluates each condition in source order, and `Condition#interpret_condition`
evaluates the current left operand before the right operand. Earlier branch
bodies can change either expression. Comma/or alternatives repeat this sequence;
they may render the same body more than once. An else consults only preceding
matches and does not evaluate the case operand. No when means no operand evaluation.

```liquid
{% case x %}{% when null %}A{% assign x = 1 %}{% when null %}B{% when 1 %}C{% endcase %}
```

With host `x: null`, Ruby returns `AC`. The previous implementation cached null
before the branch loop and returned `AB`. The correction evaluates the operand
inside each when comparison, preserving the existing disjoint when/else AST,
source order, repeated matches, else policy and immutable parsed templates.

## Resource and error policy

Every performed operand evaluation spends its normal evaluator-step capacity.
A further comparison of simple operands charges two expression evaluations,
including its current left value. It does not receive free work or a reset budget.
Exact work counts are library-version observations, not stable public constants.
Unexecuted expressions do not spend work: an else-only case never evaluates its
operand. Initial context admission and whole-partial admission remain unchanged.
Output, iterations, nesting, cancellation and operational failures keep their
existing policies. Runtime recovery remains explicit and retains diagnostics;
it cannot make a raising error or failed comparison an error-free render.

## Qualification

Supplementary controls use pinned Ruby's public Template/Context in lax, strict
and strict2, with raising and recovery recorded separately. They cover the exact
deferred minimal, successive mutations, comma/or alternatives, duplicate nulls,
early else, dynamic indices, object replacement, includes, isolated renders,
captures, nested cases, loops, unchanged literal operands and newly reached errors.
Public Swift Testing exercises source/parsed inputs under all four render policies,
error locations in partials, exact budgets, unused operands, concurrent reuse and
deterministic callback-entry cancellation with healthy siblings and later reuse.
The original fixtures and existing test bodies are preserved byte-for-byte.

The follow-up return binds every final gate to one clean SHA after the last
code/docs edit: native Debug/Release and consumers, ASan/TSan, docs/DocC,
simulator compilation, published 1.3.0 installation, pinned reference and full
independent liquid-spec. Population and eligibility remain 5,099 source cases,
5,112 variants, 4,624 selected and 488 excluded. Raw and phase-qualified verdicts,
all continuing failures, actual exits and operational errors remain separate.
Supplementary regression gains never become invented original-suite gains.

The original R3 and C returns remain immutable historical evidence. Range-property
differences, deferred grammar, transport and hosting findings retain their own
scope. The independent lane must continue to exit 1 while failures remain.
