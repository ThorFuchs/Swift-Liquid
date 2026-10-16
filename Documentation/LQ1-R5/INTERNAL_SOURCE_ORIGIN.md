# Internal source origins and unexpected-character diagnostics

Implemented after the historical R5 return. Signed Codex, 2026-10-16.
The maintainer authorized this workstream to take ownership after no separate
LQ3 owner was found in the available task inventories. The independent reviewer
agreed the v2 boundary and reviewed the producer/byte-authority separation.
This does not create a public source-map API or an editor implementation.

## One byte authority, one producer boundary

`DiagnosticSourceSnapshot` owns an immutable view of the already admitted UTF-8
bytes. It validates half-open ranges and scalar boundaries, checks the actual
reason character against those bytes, and derives one-based engine positions.
Lines advance on LF; CRLF advances at LF and lone CR stays on its current line.
Columns count Unicode scalars, including combining marks and tabs individually.
This is an explicit engine diagnostic view. Ruby does not supply a column in
the examined errors; future zero-based LSP/UTF-16 conventions remain separate.

Legacy lexer line/column counters are not this authority. Some ASCII/opaque paths
do not track LF consistently. They remain untouched: new diagnostic positions
come from the original bytes, without repairing other lexer/parser locations.
Source identities distinguish anonymous, root and exact-scalar partial names.
The existing public parser supplies no identity, so its identity stays anonymous;
binding a parsed template to a partial name never mutates it.

The **lexer producer**, after its existing first rejection, selects only a
presentation-context candidate. Its bounded, error-only selector follows pinned
Shopify `tokenizer.rb#next_tag_token/#next_variable_token` first terminators and
brace transitions, and `block_body.rb` header whitespace/trim handling. Existing
native token spelling must match the original header bytes. Tag markup follows
`ParserSwitching#markup_context`; variables and echo use the source-established
`Variable#markup_context` wrapper. The byte authority only validates the candidate
and computes coordinates: it does not recognize tags, search delimiters or emit AST.

The source remains Shopify Liquid `4e39ae4cc3da73921923c0669e0fc84a66b2f696`.
Fourteen supplementary native-reference controls cover quotes/backslash, trim,
LF/CRLF/lone CR, scalar-distinct source, multiline headers and legacy counter drift.
All three Ruby modes and both rendering policies are observed separately: lax
acceptance in those controls is not represented as Swift acceptance parity.

## The correction and its limits

Only an already-thrown `LexerError.unexpectedCharacter` can be enriched. Its
typed reason, character and first failure remain unchanged. A resolved error
adds the verified source excerpt and construct/header anchor through the existing
`LiquidError.syntax(message:line:column:)`. No adapter normalizes its output.
All other error families, parser modes/defaults and recovery policies are untouched.

Original bytes are necessary but do not establish every Ruby context. A quoted
delimiter can make the two tokenizer frames disagree; such a candidate remains
unmapped. An outer `liquid` lexical error does not prove the inner command's
markup or line, so that context remains unmapped. Rewritten/default lexer inputs
also remain explicitly unmapped until a real original mapping is supplied; this
wave supplies no guessed or placeholder exact mapping. Synthetic inline-comment
headers and reason/source-scalar disagreements conservatively keep the existing
error. Unknown partial identity is never invented.

These unresolved cases retain the existing failure/message and absent locations.
They are not successful diagnostic parity. D2 reason uncertainty, D3 rejection
ordering and D4 grammar acceptance remain separate work. Suite pattern matches
are not proof of exact text, complete source coverage or full Liquid compliance.

## Admission, cancellation and qualification

The normal source-byte admission runs first. Candidate selection, validation and
position work are linear in that admitted source and use no per-scalar index,
global cache or host I/O. New traversal loops check cancellation; a cancelled
provider never converts an operational cancellation into a language diagnostic.
The error-only view retains at most admitted bytes and derived bounded text.
Successful tokenization does not invoke this diagnostic provider.

New supplementary tests preserve every prior authored assertion, fixture byte,
license/pin, public declaration, package product/dependency and Apple minimum.
They cover source parsing/rendering/inspection, raising/recovery, partial-local
coordinates, finite admission, exact scalar identity, cancellation and shared
engine/template reuse. The seven unchanged `Scripts/ci.py` lanes and 594 prior
controls qualify a final clean source. The full independent suite, raw/qualified
comparisons and retained failures remain a separate evidence track. No benchmark
or performance claim is part of this correction.
