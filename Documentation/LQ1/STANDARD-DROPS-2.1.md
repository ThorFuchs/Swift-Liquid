# Standard test drops: 2.1 capability study

This is an exploratory, source-bound study of the 56 variants whose first
recorded exclusion is `drops` alone. The [case-level matrix](STANDARD-DROPS-2.1.json)
retains the exact fixture and mode identities, constructor inputs, expected
behavior, source-file digests, required capabilities and probe observations.
All 56 remain excluded; no upstream or reviewed result has changed.

The pinned Ruby Liquid 5.14.0 and pinned standard drop classes were exercised
directly with the same context construction style as the upstream Ruby adapter:
53 exact output matches and one exception containing the expected error text.
These are exploratory observations, not executions of the suite comparator.
Two generated cases were not run; their generator expressions were not evaluated.

A separate counterfactual replaced four boxed drop classes with primitive values
in Ruby. All 33 applicable fixture outputs matched in that narrow experiment.
A separate public Swift API probe rendered the same 33 primitive substitutions
and observed all 33 expected outputs. The 75 package/runtime source hashes match
the released 2.0.0 receipt. This does **not** establish general drop equivalence,
security semantics or eligibility for admission. The other 23 need dynamic
behavior or contain unexecuted generated inputs.

Broader pinned-Ruby controls compared six boxed values with primitive
substitutions across 13 operations each. Seven of the 78 observations differed.
For example, a string drop returned `0` for `size` while its string value
returned `3`; the drop did not iterate where the string did. A nil-valued
string drop also raised on direct rendering where nil rendered empty. These are
observed reference behaviors, not Swift suite failures, but they rule out an
unqualified general policy that replaces boxed drops with primitive values.

| Drop class | Variants | Required behavior |
| --- | ---: | --- |
| `BooleanDrop` | 22 | boxed Boolean materialization, truthiness, equality and filter behavior |
| `StringDrop` | 5 | boxed string/nil materialization, truthiness and string/filter semantics |
| `MethodDrop` | 5 | dynamic method-like lookup with integer-bearing property names |
| `SequenceDrop` | 5 | dynamic iteration and size/first/last properties |
| `NestedDrop` | 5 | recursive dynamic property access and drop identity/value conversion |
| `NumberDrop` | 3 | boxed numeric materialization and numeric-filter coercion |
| `IndexDrop` | 3 | typed integer/string index lookup |
| `NilDrop` | 3 | nil materialization and object-sensitive empty comparison |
| `OpaqueDrop` | 3 | object truthiness, stringification and empty comparison |
| `ErrorDrop` | 2 | error-producing dynamic access and render error policy |

The initial direct probe used `Template.render` options instead of the upstream
adapter’s `Liquid::Context` construction and therefore returned inline errors
for two cases. That attempt is retained as a harness-setup failure, not treated
as an engine mismatch; the corrected probe is recorded separately.

## Smallest next implementation decision

Design a typed host-object representation that preserves operation-specific
behavior, rather than flattening a drop at the adapter boundary. Compare the
pinned real drop and any proposed representation across public Swift rendering,
truthiness, `empty`/`blank`, equality, filters, partial scope, errors and value
limits. A case can be admitted only when its complete transport and semantics
are validated; otherwise preserve exclusion. See the separate
[design proposal](STANDARD-DROP-DESIGN-2.1.md).

The fixture sources remain attributed to [Shopify liquid-spec](https://github.com/Shopify/liquid-spec/tree/84bf25e0edbca5f7e530574788b0f875ab331f50),
licensed under MIT. Original fixtures and the comparator are unchanged.
