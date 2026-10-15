# E1 — Opt-in strictVariables

Status: design study; deferred. Signed **Codex, 2026-10-15**; maintainer review pending.

Problem: authors cannot currently request missing-input failures separately from
strict parser/filter policies. A boolean option alone is not a semantic contract.
No default changes or public API code are proposed in LQ1.

Study an immutable, opt-in engine policy retaining the existing initializer.
Represent missing lookup internally as distinct from explicit null: null remains
an admitted Liquid value, while a missing root/key/index carries a source path.
Decide where a property chain fails, how dynamic keys are named, and whether an
out-of-range index is missing. Null traversal and missing traversal must have
explicit, pinned Ruby comparisons rather than a generic Swift nil shortcut.

Build a truth table before selecting behavior: output, assignment, filter input,
`default` with and without allow_false, direct `if`/`unless`, comparisons,
short-circuit expressions and nested chains. Ruby strict_variables, Python
Undefined subclasses and LiquidJS lenientIf differ; borrowing a name cannot
silently choose one policy. The library's default behavior must remain unchanged.

Raising mode should deliver a typed Liquid error only after a reviewed rule;
explicit recovery must preserve diagnostics and the same assignment/output
boundaries. Cancellation and quotas remain operational. `render` partials resolve
only their admitted scope; `include` retains shared scope. A global missing-key
cache or fallback into caller objects would violate invocation isolation.

Required evidence: public source/parsed tests in all modes, missing/null/default
matrix, partial scope tests, recovery location/order, cancellation, current public
consumers and every historical fixture. A separate RFC must settle whether this
needs a new public error case and its compatibility implications. Actual LQ1
transport gaps do not justify a Drop API or strictVariables implementation.
