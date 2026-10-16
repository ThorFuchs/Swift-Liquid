# Source-origin prerequisite for one diagnostic family

Status: proposed internal handoff to LQ3; design only, no API approval.
Signed Codex, 2026-10-16. This narrows the existing
[E3 source-diagnostic study](../LQ1-R2/E3-SOURCE-DIAGNOSTICS-RFC.md).

R5's next executable step is unexpected-character provenance, after LQ3 provides
its source authority. It must not introduce another coordinate scanner, regex
parser, global source registry or public diagnostic type in parallel.

The minimum internal information is: an immutable original-source identity for
the root or explicit partial; the existing typed lexical reason and offending
scalar/byte range; the containing construct's original markup range and start;
and a mapping from synthetic multiline `liquid` tokens back to the supplied
source. Preserve the distinction between an offending position, construct start
and Ruby's formatted markup. No particular new Swift type spelling is approved.

LQ3 must own range validation, UTF-8 boundaries, newline/column conventions and
rewritten-source mappings. The E3 RFC's scalar-based coordinate conventions remain
proposed until reviewed; Ruby does not supply a column in the examined errors.
R5 must never label a hypothetical column convention as established parity.

After that interface is reviewed, one producer-side diagnostic formatter can
consume typed reason plus source origin. It must preserve the existing public
`LiquidError.syntax` surface, parser acceptance/order, parser defaults and all
runtime recovery rules. An optional partial identity must not become ambient I/O.
No JSON-RPC bridge may reconstruct a Ruby error from pattern text or fixture IDs.

Acceptance requires root/source/parsed entry agreement; all parser modes; raising
and explicit recovery retaining syntax failure; original versus rewritten Liquid
markup; LF/CRLF and Unicode boundaries; exact partial identity and local lines;
quotes/backslash; opaque blocks; empty/EOF boundaries; cancellation and finite
source/index budgets. Keep original independent expectations and all D1–D4 IDs
fixed. Retain before/after failure receipts and actual source-qualified raw and
qualified comparisons. D3 reason-order and D4 grammar acceptance remain separate.

The source-based integration candidate is reviewable locally. Approval to merge,
publish or change the minimum OS is neither requested nor implied by this RFC.
