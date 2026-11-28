# SL21-02A.4 — approved narrow quoted-literal profile

## Decision

The Control Tower accepts the narrower SL21-02A.3 profile for qualification.
Quoted Liquid source literals preserve backslash bytes and a matching quote
terminates the literal. The existing source-ownership contract remains in
`SL21-02A3-SOURCE-OWNERSHIP.md`, with this clarification: a quoted literal may
be data for an independently authorized AST operation, but its contents do not
become newly authorized executable syntax. Registered operations outside the
literal remain available. No public API, dialect or host capability is added.

* **GAP-STRING-01 — literal bytes:** the supported profile verifies 84
  well-formed mode-expanded observations plus contextual and transport tests.
  Their successful observations do not prove every possible literal context.
* **GAP-STRING-02 — delimiter ownership:** six mode-expanded cases deliberately
  preserve Swift's inert quoted delimiter behavior even where Ruby frames the
  source differently. The raw difference remains visible; no reference match is
  claimed. Instrumented host lookups, filters, partial resolution and inspection
  verify the bounded witnesses in the supported profile.
* **GAP-STRING-03 — malformed-expression recovery:** 15 expanded lax cases are
  explicitly deferred. The original matrix has four deferred observations,
  three sharing exact mode and source bytes with expanded cases; their contexts
  remain distinct. Together the two matrices contain 25 reviewed observations
  but only 22 distinct mode/source identities. Deferred sources must still be
  parsed and rejected with the specifically reviewed `LiquidError.syntax`; an
  operational failure or unexpected success does not qualify.

## Evidence policy

The original 96- and 75-case reference fixtures and strict raw assertion bodies
remain intact in the isolated `Tools/QuotedStringRawTests` package. The raw lane
executes both comparisons and preserves its failing verdict and all 25 issues.
The separate reviewed lane executes all 171 observations: it compares raw
matches directly and validates the exact source, mode, reference observation and
intended Swift behavior for each of 25 approved or deferred observations. The
six approved framing observations and the 19 deferred observations are not
counted as raw matches. The explicit overlap register prevents counting three
shared source/mode identities twice; reference contexts are not conflated.

Policy and fixture digests, identities, original raw test bodies, output bytes,
syntax error messages and locations are fail-closed. The reviewed lane checks
inspection, dependencies and absence of unintended host capability invocation.
It does not establish general parser security from finite tests. Historic native
assertions remain unchanged. Full conformance evidence and Ruby reference
concerns stay separately reported.

## Consumer compatibility

Swift-Liquid 2.0.0 interpreted escape-like text such as `\n`, `\t`, `\r`,
`\\` and escaped matching quotes in Liquid source literals. The preserved
correction changes output bytes and can change parsing. Templates that need
control characters should use actual characters or host-provided values; code,
paths, Markdown and mathematical templates should be reviewed for literal
backslashes. Host-provided strings, JSON decoding, raw content and explicit
escaping filters retain their separate behavior.

A major version is the conservative recommendation if the published 2.0.0
behavior is treated as part of the public contract. A minor 2.1.0 release
would require an explicit compatibility decision and migration notice; 2.1.0
remains the working target pending that decision. No release is authorized.

## Cancellation and bounds

Source admission applies a finite UTF-8 byte limit, and public cancellation is
reported as `CancellationError`; neither an operational error nor cancellation
satisfies reviewed language rejection. The existing quoted-string scan advances
monotonically once across the selected source bytes. It does not itself poll
for cancellation inside that loop; admission and subsequent error/parse paths
perform separate checks. This is a bounded responsiveness limitation, not a
claim of prompt mid-scan cancellation or a whole-parser complexity proof. Any
runtime change to address it requires separate review under this increment's
restrictions.
