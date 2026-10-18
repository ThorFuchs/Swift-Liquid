# Parser diagnostic fidelity: R5 evidence contract

Status: evidence and design only. Signed Codex, 2026-10-16. No diagnostic,
acceptance, parser-default, recovery or public API change is implemented here.

## What the fixed population establishes

The original RANGE source is `a72058d4afd2a668699b375dc26d1bbd1994a969`.
Its read-only packet verifier passes 3,069 manifest entries. The independent
population remains 5,112 variants, 4,624 selected and 488 excluded; historical
Golden/Ruby fixtures, expectations, pins and receipts remain immutable.

Within 1,905 selected `parser_errors` variants, 24 already qualify. The residual
partition is 482 D1 same classified condition with different text, 1,327 D2 with
insufficient reason evidence, 47 D3 with different explicit rejection reasons,
and 25 D4 accepted by Swift. D1 contains 463 unexpected-character and 19
expected-token cases. These classifications describe observed messages, not a
new public typed-reason API. D2 remains unestablished; D3 and D4 require separate
semantic/acceptance review. No case is reclassified to improve the denominator.

None of the 463 D1 unexpected-character cases asserts a line in its fixture.
A successful upstream pattern/location comparison therefore cannot establish
source-location fidelity. Raw upstream comparison and stricter qualification
are separate outcomes; neither implies exact message equality.

## Reference producer and context

Pinned Shopify Liquid is `4e39ae4cc3da73921923c0669e0fc84a66b2f696`;
liquid-spec is `84bf25e0edbca5f7e530574788b0f875ab331f50`.
In `lib/liquid/lexer.rb`, `raise_syntax_error` reads a Unicode character with
`StringScanner#getch` and raises `Liquid::SyntaxError` with an unexpected-character
reason. `parser_switching.rb` adds the construct's line and markup context.
`variable.rb` wraps variable markup in Liquid output delimiters; the default
tag context strips surrounding whitespace. `errors.rb` formats the prefix and
optional template name. `partial_cache.rb` supplies a partial's name when its
parse fails during reference rendering.

These are distinct responsibilities. Supplementary native Ruby observations use
read-only `TracePoint(:raise)` snapshots to retain the initial reason and later
context mutations. They do not replace messages or change the reference engine.
The original suite runner's actual verdict remains authoritative for its own
fixture policy. In particular, a fixture can accept an error pattern without
requiring every byte of Ruby's wrapper or a column that Ruby does not expose.

## Current Swift behavior and limits

`LexerError.unexpectedCharacter` retains a character and absolute byte position.
Its message quotes that character. `publicError` maps it to `LiquidError.syntax`
with absent line and column. This is producer-side information loss, not JSON-RPC
normalization: the adapter forwards the public payload without inventing context.
The public syntax error has a typed syntax category and optional coordinates;
it exposes no typed reason, source ID, span or partial name.

The lexer admits the entire source before parsing. The parser's multiline
`liquid` handling then rewrites body lines as synthetic tags and reparses them,
using a line offset for some parser errors. Its nested lexical catch wraps the
error as `ParserError.unsupportedFeature`. An absolute offset in that rewritten
string is not an original-source span. Counting newlines from an arbitrary
failure offset also does not reproduce Ruby's construct-line policy.

The source render APIs eagerly parse every supplied partial, including unused
ones. The independent adapter preserves that public contract. Ruby's reference
loader parses requested partials during rendering. A partial parse failure can
therefore be a Swift compile failure and a Ruby render failure. This is a
documented admission/phase distinction, not permission to defer parsing or turn
syntax errors into recovered runtime output.

Supplementary probes cover special characters, quotes, backslash, composed and
decomposed scalars, emoji, LF/CRLF, multiline tags, output/conditional contexts,
explicit render/include/unused partials and opaque raw/comment controls. Every
lax/strict/strict2 and raising/recovery outcome is retained. In particular, Unicode
probes can expose different rejection conditions; the ASCII D1 conclusion is
not extrapolated to those inputs. Existing cancellation and finite-work tests
remain mandatory, and supplementary observations add no conformance cases.

## R5 decision

Do not remove quotation marks merely to satisfy the 463 text patterns. A complete
reason/context correction needs original construct identity and provenance through
rewriting and explicit partial admission. That source-coordinate ownership belongs
to LQ3. R5 therefore implements **zero diagnostic code changes**, preserves all
authored assertions and produces a blocked G2 return with a narrow interface
decision in [SOURCE_ORIGIN_HANDOFF.md](SOURCE_ORIGIN_HANDOFF.md).

The isolated integration candidate combines RANGE with the already merged PR16.
Both semantic tests and immediate-template budget/cancellation tests are retained.
Its own exact-source receipts, full fixed-population matrix, taxonomy, raw logs
and integration review belong to the separately delivered R5 packet. Earlier
RANGE/main receipts are baseline evidence, not qualification of the combined tree.
No benchmark, acceleration, complete compliance, release or merge claim follows.
