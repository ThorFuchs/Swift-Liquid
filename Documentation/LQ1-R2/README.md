# LQ1-R2: independent conformance triage

Local review milestone, not a release or a certification of Shopify compatibility.
R2 replays LQ1 onto qualified main `c683b620` while preserving quality sprint 3's
hosted-workflow, installation and source-inventory protections. Five original
LQ1 commits remain identifiable in history. No published fixture, pin, expectation,
release receipt, public API or root dependency changed.

## Evidence before interpretation

The original upstream `AdapterRunner#run_single` result is retained in
`upstreamVerdict`, including `status`, `passed`, output, expectation and a digest.
`comparison` follows that verdict exactly. `qualificationComparison` separately
rejects wrong parse/render phases and operational failures, as LQ1 did. Neither
supplementary dimensions nor a similar diagnostic can promote an upstream failure.
The pinned comparator's default-pass branch can accept a missing expected error;
the instrumented baseline has 52 raw passes that fail qualification. Reporting
those raw passes is an accounting correction, not an engine improvement.

The immutable LQ1 population contains 1,857 parser-diagnostic mismatches. Explicit
reason/token extraction establishes the same reference rejection condition for
482, a different condition for 47, and insufficient evidence for 1,328. These
labels do not prove the first group correct or the latter groups defective. None
of these baseline cases isolates a location-only failure with matching upstream
message patterns. Missing line/column information remains unknown. The exact
upstream Ruby helpers determine message-pattern/location matches; the explanatory
Python classifier never substitutes for them.

All 45 original phase differences are accounted for: 18 bare-bracket expressions,
two `for` modifier/separator forms, 20 assignment-target forms, one numeric capture
target, one case-branch form and three comment-boundary forms. The first two
clusters are repaired; 25 parser inputs still reach rendering. The 52 lax parse
rejections remain measured, with all three pinned Ruby modes recorded in the
return. [Deferred syntax decisions](DEFERRED_SYNTAX.md) explain why broad
acceptance changes require another reviewed regression matrix.

## Three general repairs

| Invariant | Independent provenance at liquid-spec `84bf25e` | Qualified mismatches becoming matches |
| --- | --- | ---: |
| Bare bracket expressions require a receiver in strict2; lax/strict retain indirect root lookup | `parser_errors/assign.yml:314`, Ruby `parser.rb#expression` | 26 |
| `for`'s `reversed` modifier precedes named attributes; strict modes reject trailing separators, lax ignores late modifiers | `parser_errors/adversarial_boundaries.yml:52`, `parser_errors/for.yml:488`, Ruby `tags/for.rb` | 2 |
| Unnamed variable cycles have identity per parsed tag; literal/named grouping stays intact | `basics/cycle.yml:55`, `:66`, Ruby `tags/cycle.rb#maybe_dup_lookup` | 3 |

The third repair stores only an immutable identity in the checked-Sendable AST.
Counters belong to each invocation and participate in render scope save/restore;
include reuses its parsed partial's site. Public tests cover all parser modes,
source/parsed rendering, explicit recovery, partial scope and concurrent reuse.
The historical corpus is unchanged. The current test inventory has 78 functions,
2,116 parameter cases and six shared-engine concurrency functions.

The independently executed post-repair source `906d9d1` retains exactly 5,099
source cases, 5,112 variants, 4,624 selected and 488 disabled: 459 transport,
22 unsupported (including six warn variants), seven numeric-domain cases.
Qualified results are 2,253 matched, 2,361 mismatched and ten operational errors.
Raw upstream results are 2,280 matched and 2,344 mismatched. All 88 portable
`ruby_types` variants stay selected (17 qualified matches, 71 failures).
The independent command exits 1. These counts are not a language-wide pass rate.

## Remaining output findings

Minimized public-API probes establish several distinct in-domain differences:

- Dynamic include property names are rejected by the parser; a simple dynamic
  name with `with` also binds its default alias incorrectly. No loader is needed
  to demonstrate either difference with an explicit map.
- Dotted/bracket `for` limit values are rejected after expression parsing.
- `render` loses supplied global inputs while correctly hiding caller-local
  assignments. Passing the same value explicitly succeeds. This explains the
  nested-layout partial case; preserving globals needs a separate scope repair.
- Object-property `size` reports zero while the `size` filter reports the actual
  count. This explains missing cart-property branches in the other complex
  partial case; it is not a filesystem or global-inheritance failure.
- A `case` list containing `null` can match an unrelated string (lowest Ruby-core
  failing complexity 90). Mixed-type sorting also misses a required runtime error.

A control with an unused malformed partial instead demonstrates eager Swift bundle
admission versus Ruby's lazy map access. It is a hosting artifact, not evidence
that a general ambient loader belongs in core. Range-valued cycles retain the
pinned behavior; the cycle repair does not treat every nested variable expression
as a top-level Ruby `VariableLookup`.

All ten original pinned-Ruby expectation concerns reproduce unchanged. They cover
one malformed-interpolation expectation, three blank-body errors, five filesystem
or recursion diagnostic prefixes, and one assignment-error suppression expectation.
Their source and verdict digests remain in `TRIAGE_DETAIL.json`; they are failures,
not automatic Swift repair candidates. Ruby-only types and out-of-domain numbers
retain their explicit exclusion reasons.

## Qualification and next review

`Scripts/ci.py` now records starting/ending commit, tree, clean state, source
snapshot and whether qualification stayed on one clean revision. Final return
receipts must all bind to the final source SHA after documentation edits; no
adapter-only exception is permitted. Debug/Release, safety, docs, platforms,
pinned reference, consumers and the failed independent lane remain separate.
Operational errors never become successful Liquid renders. No timing suite runs.

The return packet carries the original LQ1 results, rebased preflight (including
the failed docs invocation and successful same-source retry), instrumented
baseline, one full independent run per repair, final gates, raw redacted RPC
traces, diagnostic ledger, exact transitions, conflict log, source/diff and hashes.
Final receipts, rather than this prose, establish the final qualification status.

[E3 source diagnostics](E3-SOURCE-DIAGNOSTICS-RFC.md) is the sole future API design
proposal. It remains design-only. E1 strict variables, E2 custom tags, E4 loaders/
streaming and E5 JSON bridges stay deferred. The next correctness gate should
review the remaining 25 acceptance differences and scope/lookup minimals before
choosing another bounded set of repairs. Maintainer review is required before
merge, publication or any public API change.
