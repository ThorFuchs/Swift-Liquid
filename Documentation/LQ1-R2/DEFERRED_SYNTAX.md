# Deferred syntax and semantic decisions

Status: proposed review boundary; no additional implementation authorized in R2.
Signed **Codex, 2026-10-15**; maintainer decision pending.

The three implemented invariants exhaust R2's repair budget. Original failures
remain selected. This decision does not approve another parser refactor.

## Assignment targets and remaining parse acceptance

Twenty of the original 45 parser-phase differences concern assignment targets.
A whole-target ASCII-identifier check would be wrong: pinned Ruby strict2 rejects
`{% assign & = x %}`, but its unanchored assignment pregate accepts `@foo` as
`foo` and `foo$bar` as `bar`. It rejects `foo.bar` after token parsing and accepts
`foo--bar`. A reviewed repair must model both the pregate and selected parser,
with negative, Unicode, punctuation and prefix/suffix controls in all modes.
The recorded 81 minimized Ruby/Swift controls preserve these distinctions.
Numeric capture, `elsif` inside `case`, and three inline-comment boundaries are
separate invariants and are not bundled into an identifier patch.

## The 52 lax false rejections

| Source pattern | Cases |
| --- | ---: |
| Parentheses outside ranges | 2 |
| Negative-sign expression quirk | 1 |
| Malformed bracket lookup | 3 |
| Unknown conditional operator | 6 |
| Dot runs in numbers/ranges | 2 |
| Unconsumed expression suffix | 14 |
| Numeric-leading variable | 1 |
| Unanchored filter argument | 4 |
| Operator lexical tolerance | 1 |
| Empty/trailing filter arguments | 5 |
| Case-expression suffix | 4 |
| Cycle fragment tokenization | 7 |
| Tablerow attribute/expression suffix | 2 |

`TRIAGE_DETAIL.json` binds every case, source/result digest and native pinned Ruby
mode probe. All 52 parse in Ruby lax; 48 complete raising renders and four raise
runtime errors. Under strict, 39 reject during parse and 13 render; under strict2,
47 reject during parse and five render. Consequently, the whole set cannot be
called “lax-only syntax.” Some tags intentionally retain lax parsing in strict;
each relaxation needs a mode-specific contract. Original recovery-mode outcomes
remain in the real upstream runner matrix, separately from raising mode controls.

Proposed next acceptance matrix: exact original fixture plus a short equivalent,
all three parse modes, raising/recovered rendering, empty/nonempty/else branches,
unreachable expressions, quoted delimiters, Unicode, truncation, invalid suffixes,
source limits and cancellation. Approve a specific lexical/grammar invariant
before widening acceptance. No catch-all discard-to-delimiter or `try?` recovery.

A separate control shows Ruby accepts a comma immediately after initial
`reversed` in all modes; Swift still rejects it. The R2 ordering correction does
not silently implement this accepted-syntax expansion. Its receipt remains in
`RUBY_FOR_MATRIX.json` and the initial positive-test failure is retained in logs.

## Deferred output rules

Minimal explicit-map probes isolate global/static environments in `render`,
object-property size, dynamic include receivers/default aliases, nested loop
arguments and a null-containing case list. These are candidate core defects,
not invitations to change host reflection, globals, escaping, quota or recovery
policies. Eager validation of an unused malformed partial is instead an explicit
bundle-admission difference. A future repair must preserve finite admission and
local-versus-global scoping, with no ambient filesystem/network access.
