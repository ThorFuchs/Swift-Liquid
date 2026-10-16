# Range-property commands

The maintainer authorized this bounded follow-up on 2026-10-16, from the
qualified case-reevaluation source `d2437a0`. No merge, release, public API,
parser-default, numeric-domain or fixture changes are authorized.

Pinned Ruby Liquid `4e39ae4cc3da73921923c0669e0fc84a66b2f696`
(`lib/liquid/variable_lookup.rb`) treats dot `first`, `last` and `size` as
commands after real-key lookup. Bracket strings are keys, not those commands.
`lib/liquid/standardfilters.rb` invokes the corresponding methods on ranges.
The original independent findings are liquid-spec `84bf25e` cases
`property_access_range_first_last_size` and
`filter_vs_property_range_equivalence` in `liquid_ruby/variable_type_filters.yml`
(lines 342 and 510), and their lax counterparts (321 and 447).

Swift's lazy range already stored endpoints but property lookup omitted its
runtime type. A descending range was replaced by an empty array, losing endpoint
identity. The repair preserves a typed range with an admitted cardinality, computed from the already checked endpoints: an
ascending range's count is checked before construction, while a descending range
has count zero. Dot commands and argument-free standard filters share the typed
command lookup. They do not materialize or enumerate values. Iteration still
produces no elements for a descending range. This also restores its existing
range stringification/equality path instead of applying empty-array behavior.

For `(1..5)`, properties and filters return `1`, `5`, `5`. For `(5..1)`, both
return `5`, `1`, `0`; its string form is `5..1`, and it does not equal the `empty`
comparison literal in pinned Ruby. Bracket `r["first"]`, `r["last"]`, `r["size"]`
and dynamic string-key access return nil for a range. Static path optimization
must preserve command versus bracket identity for all three names. A separate six-variant pinned Ruby negative control preserves nil for `r.count`,
literal bracket count and dynamic bracket count. Cardinality remains a computed
implementation detail rather than a newly reflected field. No general
range indexing, `length` command or host-object reflection is introduced.

Real object keys, loop records, strings, arrays and scalar size behavior retain
separate tests. Twenty successful reference controls cover every parser mode,
source/parsed input and four render policies. Two existing concat-error controls
retain their separate raising/recovery phases and each engine's diagnostic bytes;
they are not exact-error or successful-output claims. Raw before/after public
JSON-RPC probes retain all 132 variants. Additional Swift tests cover partial
error locations, exact output/work/iteration admission, zero enumerated iterations
for properties, immutable shared-template reuse and deterministic cancellation.

Existing range-bound coercion, finite admission limits, evaluator checkpoints,
custom-filter value admission, public declarations and defaults stay unchanged.
Huge or nonrepresentable numbers gain no parity claim. Nonnumeric-bound and
range-filter behavior beyond this bounded rule remain separate findings.
Pinned fixtures, original eligibility, expected bytes, upstream comparator and
prior returns remain unchanged. Final qualification must bind every gate to the
same clean commit; independent mismatches and operational errors still fail.
