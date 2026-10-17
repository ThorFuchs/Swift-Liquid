# Typed expected-token diagnostics

This change refines presentation after an existing parser rejection. It does not
change the grammar, parser modes, first rejection, recovery, quotas or public API.
The local baseline is 35abaa7ba13364058756ef4aa8603d51a4eb08db, tree
985296c9feb75343df6806eebb014687ee2e9d45. Its complete retained seven-lane
non-timing evidence is in the adopted d313 return. New-source qualification is
recorded externally after the final commit; this document is not a gate receipt.

## Original inputs and checked behavior

The derived R6ExpectedTokenCases.json fixture preserves the original nineteen
strict2/raise identities, exact templates, empty variables/partials, original
options and unchanged expectations from Shopify/liquid-spec at
84bf25e0edbca5f7e530574788b0f875ab331f50. Exact named YAML nodes are selected by
original file, line and name. Historical sourceDigest is the whole YAML file hash;
inputUTF8SHA256 separately identifies the actual template bytes. The full MIT
notice accompanies the fixture. No source is reconstructed from an error excerpt.

Pinned Ruby Liquid 4e39ae4cc3da73921923c0669e0fc84a66b2f696 supplies the retained
reason/context observations. Native supplementary mode and policy checks remain
separate from those nineteen identities. Ruby lax acceptance is not claimed as
Swift acceptance parity. The independent lane and historical 1,888 failures across
49 groups are unchanged: targeted regressions do not subtract nineteen from them.

## One parser, explicit original provenance

ParserError.expectedToken retains its typed expected/found TokenType values.
The parser catches that same first rejection without advancing its cursor or
trying another parse. Its error-only producer selects the surrounding native
token frame and verifies the pinned first-terminator boundary. The existing
DiagnosticSourceSnapshot is the single immutable byte/range/scalar-position
authority. It validates supplied header and reason spellings; it recognizes no
tag grammar and emits no AST. Successful parsing performs no diagnostic source
scan or byte-buffer copy.

LiquidTemplate passes one explicit internal original/anonymous provenance
argument at its existing parser call. That narrow additional call-site plumbing
prevents synthetic Parser inputs from acquiring assumed provenance. Nested
rewritten liquid bodies keep the unmapped default. No public constructor or
source-ID/editor contract changes. The existing publicError bridge receives the
validated location through the existing ParserError sourceLocation property.

Only a validated markup-ending delimiter is presented as end_of_string. Explicit
typed vocabulary provides close_square/close_round, id and the checked punctuation
names without changing TokenType.description or rewriting a finished message.
Ordinary tags use stripped markup, output and echo use the established output
wrapper, and when retains its distinct direct reason. Case operands remain
ordinary tag contexts. Unsupported reason spellings conservatively retain the
old typed failure/message rather than guessing quoted/numeric source text or collapsed comparison spellings.

Unknown identity, missing source, rewritten input, invalid boundaries, mismatched
source/reason/header bytes and quoted-delimiter frame disagreement stay unmapped.
Their existing failure and absent expected-token location remain; no exact span
or Ruby compatibility is invented. Generic-token, unexpected-character and other
error families retain their existing behavior, including existing token locations.

## Positions, finite work and reuse

One-based positions follow the existing original-byte engine contract: LF advances
line, CRLF advances at LF, lone CR stays on its line, and columns count Unicode
scalars including combining marks and tabs. Public partial positions remain local
and anonymous; no template name is invented. A Ruby construct-line value can
differ for multiline headers, and Ruby's absent column establishes no equality
claim. The original nineteen inputs are single-line; supplementary LF/CRLF/loneCR,
trim, composed/decomposed Unicode and emoji controls check the engine policy.

Producer/validator loops remain linear in admitted input and check cancellation.
Source/depth rejection and cancellation stay operational under raising and
recovering APIs; eager partial compilation is unchanged. Immutable origin state
belongs to the current parse, with no global cache or host I/O. Concurrent reuse
and deterministic provider-entry cancellation controls are separate regressions.

## Qualification boundary and retained work

Nine new test declarations cover the original nineteen plus supplementary
policies, frame fallback, vocabulary/first rejection, valid inputs, quotas,
partials, positions, cancellation and concurrent reuse. The inventory records 123
functions/2,278 parameter cases, with 14 thread functions/12 parameter cases and 23
adversarial functions/70 parameter cases. These counts describe authored selectors;
actual final receipts and strict raw event joins must establish execution.

All 29 previous raw adaptation records, original fixtures/pins/licenses, APIs,
products, empty root dependency graph and platform floors remain. Adaptation 30
records this bounded change. The narrow C assertion/provenance limitation is not
expanded. D2/D3/D4, 25 accepted-invalid cases, two disabled-include runtime cases,
ten nestingDepth outcomes, editor/registry/downstream work and PR23 optimization
remain separate. F01–F14/F13, E01 and all 120 performance dispositions persist.
Performance stays HOLD_PERFORMANCE_PENDING_QUIET_WINDOW; the independent lane
stays failed and unrerun. New R6 source acceptance, integration and release remain
pending review. No speedup or full-conformance claim follows.
