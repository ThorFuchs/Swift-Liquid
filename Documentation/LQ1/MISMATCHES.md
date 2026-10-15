# Independent mismatch review

The repaired run is a **failed** functional gate. The raw matrix records every
selected and disabled variant; generated packet `MISMATCHES.md` lists every
selected failure by case, mode, pinned source line and result digest. This page
summarizes findings and does not replace those receipts.

| Suite | Source cases | Mode variants | Selected | Matched | Mismatched | Operational | Disabled |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| basics | 955 | 955 | 897 | 803 | 85 | 9 | 58 |
| liquid_ruby | 2,106 | 2,119 | 1,608 | 1,335 | 272 | 1 | 511 |
| liquid_ruby_lax | 121 | 121 | 114 | 54 | 60 | 0 | 7 |
| parser_errors | 1,905 | 1,905 | 1,905 | 3 | 1,902 | 0 | 0 |
| partials | 12 | 12 | 12 | 10 | 2 | 0 | 0 |
| Total | 5,099 | 5,112 | 4,536 | 2,205 | 2,321 | 10 | 576 |

A match uses the pinned comparator (exact output or required patterns) plus an
explicit error-phase check. Successful-render **outcome** does not mean matching
output. Recovered diagnostics remain recovered-error outcomes even if matched.
No skipped variants were reported. All 576 unexecuted rows have visible reasons:
547 transport-inapplicable, 7 outside numeric domain and 22 unsupported policy/mode
variants. Six unsupported `warn` records are preserved; the upstream expansion
helper would otherwise omit them. None is counted as passed.

## Verified repair

[truncate_zero_length](https://github.com/Shopify/liquid-spec/blob/84bf25e0edbca5f7e530574788b0f875ab331f50/specs/basics/filter-edge-cases.yml#L282)
expected `...`, while Swift returned an empty string. Pinned Ruby confirms the
ending remains when a nonempty input exceeds a zero/negative requested length.
The general helper now computes a nonnegative prefix without subtracting from
`Int.min`. Public source/parsed/recovery tests in all three modes also protect
empty input, Unicode scalars, custom endings and output limits. Three suite
outcomes change from failing to matched. Initial receipts remain immutable.

## Open general-rule candidates

These remain unresolved until focused regressions and semantic review; no fixture
or rule is special-cased to raise a pass count:

- Lax filter separators and empty chains can reject input the reference accepts.
  The lowest failing eligible basics complexity is now 100; liquid_ruby starts at
  90. Complexity is a sparse suite ordering, not a language-wide clearance score.
- Dotted/bracket loop parameters, conditional alternatives, counter namespaces,
  and cycle-site identity have divergent outputs or parse behavior. For example,
  `cycle_unnamed_variables_independent_counters` yields `ab` rather than `aa`.
- Invalid sort/comparison inputs and recovery output can differ in error type,
  message or placement. Ruby inspect-style object formatting needs a value-domain
  review, not an arbitrary native-object bridge.
- Partial scope, dynamic include syntax, name lookup and eager-vs-lazy admission
  need separate core and host-policy reproductions. Two selected partials cases
  differ; they were exercised only for correctness despite their `bench_` names.

The parser_errors suite rejects 1,860 cases during parse, but only three satisfy
the required comparison. The other 1,857 have diagnostic mismatches. Forty-three
reach successful rendering and two fail only at render; these acceptance/phase
failures need priority over wording polish. Do not count all rejections as passes.

Ten recursion cases hit `nestingDepth` limits. The existing finite policy is an
operational boundary, and must not become inline Liquid recovery. Nine are
classified as documented bounded-domain divergence; the tenth also fails its
pinned-Ruby expectation and is classified as a test-suite concern. Outcomes and
nonzero exits remain intact.

Ten expectations also mismatch pinned Ruby under this runner/hosting policy:
`security_var_name_no_interpolation`, three strict2 blank-body cases, five
filesystem/recursion cases and `assign_swallows_filter_error`. They require
reference/suite review before engine changes. No expected bytes were rewritten.
The remaining 2,312 selected failures are unresolved; symptom labels such as
parser diagnostics or unexpected rejection do not establish a verified root cause.

## Reproduce and retain

Run the [independent lane](../../Tools/LiquidSpecAdapter/README.md), then:

```sh
python3 Scripts/summarize_liquid_spec.py Artifacts/liquid-spec/independent/spec \
  --initial /path/to/retained/initial/ELIGIBILITY_MATRIX.json
```

The summary emits `TRIAGE.json`, `CORE_REPAIR.json` and the complete mismatch list
without editing the raw matrix or outcomes. Core defects, documented domain
boundaries, Ruby-only types, hosted features, protocol artifacts, suite concerns
and unresolved cases remain distinguishable. Public API studies remain separate
from automatic repair candidates. See [next gate](NEXT_GATE.md).
