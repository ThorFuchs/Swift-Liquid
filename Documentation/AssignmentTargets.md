# Assignment target admission

This bounded correction addresses twenty original strict2 false-acceptance identities
in Shopify/liquid-spec parser_errors/assign.yml (twelve distinct target spellings).
The inputs are pinned at 84bf25e0edbca5f7e530574788b0f875ab331f50. The reference
is Shopify/liquid 4e39ae4cc3da73921923c0669e0fc84a66b2f696, Ruby 4.0.1.

The R2 deferred-syntax study establishes two stages: Assign::Syntax performs an
unanchored VariableSignature precheck; strict2 then requires an identifier. The
precheck rejects punctuation-only and quoted targets in every mode. Prefixes can
be ignored: @foo binds foo and foo$bar binds bar. Hyphens remain valid within an
identifier. A whole-target identifier check would incorrectly reject these cases.

The existing parser now admits the suffix captured by that precheck before
consuming the assignment operator and RHS. A bounded reverse byte scan matches
the pinned signature without regex backtracking; strict2 then validates the
captured identifier. It checks cancellation during scanning. Original source,
RHS parsing, mode selection, scopes and render recovery remain owned by their
existing implementations. Invalid targets fail during parsing and do not become
recoverable runtime diagnostics. No public API, second parser or message adapter
is added. Unsupported grammar outside this narrow target-token boundary remains
outside this correction; this is not a full assignment-grammar parity claim.

Strict2 also reports the established assignment precheck failure with the
offending token's source location for missing targets and for punctuation
directly before the assignment operator. Numeric targets retain the typed
expected-identifier reason. These diagnostics do not admit rejected templates.

## Regression provenance

AssignmentTargetCases.json retains each of the twenty original case IDs and exact
source strings, expanded to lax/strict/strict2 (60 cases). Separate supplementary
controls cover 27 targets in three modes (81 cases), including R2's unanchored
prefix, dot, bracket, numeric, Unicode and hyphen distinctions. These 81 controls
are fresh reference observations, not the recovered original R2 81-object study.
The R2 published studies remain the historical planning basis. Full upstream
MIT terms accompany the new derived test data in Licenses/ShopifyLiquidSpec.

Original cases exercise public parsing, raising rendering and diagnostic
rendering. Supplementary accepted cases compare source, parsed and recovered
rendering against pinned Ruby output. Other controls cover opaque blocks,
whitespace trimming, multiline liquid, unchanged source bytes, source quotas,
cancellation and healthy reuse. The explicit test inventory is updated by four
functions, 144 parameterized cases plus one ordinary function. Existing golden
fixtures, expectations and parser-mode metadata remain byte-identical.

Focused iteration failures and final exact-source qualification belong to the
external receipts. No full independent-suite rerun, predicted pass-count
subtraction, benchmark, performance clearance or release acceptance follows.
The recorded 1,858 mismatches, ten operational failures, exclusions, reference
concerns, provenance findings and performance holds remain historical facts.

Fixture SHA-256: 0fb8cda7ddd979358d6716f681dbda90a64862ef7b652a3c79a27e4fc265a30f.
