# SL21-02A.3 — narrower quoted-literal scope for Control Tower review

## Decision requested

Review a narrower candidate that retains the existing SL21-02A WIP's literal
byte preservation, leaves malformed-input recovery unchanged, and preserves
its established inert quoted-markup behavior. This is a scope proposal, not a
GREEN qualification, release, or claim of complete Liquid conformance. There
is no new runtime change after the preserved WIP in this increment.

The proposed supported slice covers matching quoted literals represented in
the pinned test vectors, including literal backslash-n/t/r, backslash before a
closing quote, repeated backslashes, unknown escape-like sequences, opposite
quotes, Unicode and actual control characters. `wellFormedLiteralBytesMatchReference`
independently checks 28 such cases per parser mode. That is bounded test evidence,
not proof of all possible literals or contexts.

Do not admit the four original lax malformed-quote observations as passes.
Do not expand malformed trailing token recovery, filter arguments, assign,
echo, multiline or multiple-construct handling on the basis of the earlier
experiment. The raw 96-case fixture remains unchanged, and its four differences
remain visible. The expanded 75-case fixture also remains unchanged; six raw
mode-expanded quoted-delimiter differences are proposed security-preserving
reference divergences, and the remaining 15 are unresolved. See the separate
`SL21-02A3-DISPOSITIONS.json` register. These are not matches.

## Security and ownership

`SL21-02A3-SOURCE-OWNERSHIP.md` defines the proposed authority boundaries. The
current lexer can scan a quoted token beyond an apparent outer delimiter, and
the existing parser does not expose a validated immutable range that proves
which bytes recovered expressions may own. A general shift to reference outer
framing exposed a previously inert partial invocation in the predecessor's
actual security probe; an attempted exception then exposed an adjacent-quote
variant. A stricter guard blocked both probes while failing assignment and
multiline reference controls. None of those experiments is an accepted repair.

The added tests use explicitly registered, counted host lookup, filter and
partial resolver capabilities. Protected quote, assignment, echo, multiline,
raw and comment witnesses require no callback, no corresponding inspection or
dependency reference, and correct output. Independently framed positive controls
must call each capability exactly once. Ambiguous malformed witnesses must fail
at parsing before any callback. These tests constrain the observed cases; they
are not a proof over arbitrary source.

A future change needs a reviewable way for framing to assign immutable source
ownership before recovery reuses the existing expression parser. It must show
that independently framed later constructs remain accessible, while bytes in
protected literals remain inert. If that needs a wider parser redesign, obtain
a separate scope decision; do not implement ad hoc callback, partial-name or
fixture-specific exclusions. Cancellation during a long scan and worst-case
complexity need dedicated exact-source validation; the present progress probes
are not an asymptotic proof.

## Consumer impact

Published Swift-Liquid 2.0.0 converted `\n`, `\t`, `\r`, doubled backslashes
and escaped quote spellings inside Liquid source literals. The WIP preserves
literal backslash bytes and ends a literal at a matching quote. Existing
consumers may see different output or parse errors; use actual control
characters or host values where those are intended. The source-bound 2.0.0
execution and a limited downstream audit remain in the SL21-02A evidence.

A conservative semantic-version recommendation is a major release if the old
observable behavior is considered part of the supported contract. The working
2.1.0 target stays unchanged pending Control Tower review; a minor release
requires a deliberate compatibility decision and migration notice.

## Release and qualification status

The predecessor's exact-source WIP conformance evidence records 4,738 matches,
five separately reviewed raw Swift conflicts, 369 unexecuted and ten Ruby
concerns across 5,112 identities. Those receipts are preserved but are not a
new qualification of this tests-only source revision. Native and safety
qualification remain blocked by the unresolved raw recovery assertions; full
exact-source qualification and hosted CI are not represented as passed.
