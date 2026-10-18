# Deferred grammar and other runtime findings

R3 changes no accepted grammar, parser default or reference expectation.
The same 25 remaining wrong-phase parser acceptances and 52 lax parse rejections
are retained by case identity, fixture digest and observed phase in the packet.

The 25 comprise 20 assignment pregate/lexer forms, one numeric capture target,
one case-branch admission and three comment boundaries. Ruby's unanchored assign
pregate accepts some prefixes while rejecting bare punctuation. A whole-target
identifier regex would not preserve those rules.

The 52 span 13 classes: non-range parentheses (2), negative-sign expression (1),
malformed brackets (3), unknown conditional operators (6), numeric/range dot runs
(2), unconsumed expression suffixes (14), numeric-leading variable (1), unanchored
filter arguments (4), operator tolerance (1), empty/trailing filter arguments (5),
case suffixes (4), cycle fragments (7) and tablerow suffixes (2). All parse in
pinned Ruby lax; strict accepts 13 and strict2 accepts five. No generic lax discard
rule is authorized. The R2 81 assignment controls, complete mode matrix and
[deferred syntax record](../LQ1-R2/DEFERRED_SYNTAX.md) remain unchanged evidence.

Dynamic include receivers/default aliases and dotted for limits belong to a
separate grammar/partial wave. Mixed-type sort error behavior needs a filter
semantics review. An unused malformed partial is an eager-bundle hosting policy
difference; it does not justify ambient filesystem/network loading. `self` receiver
syntax acceptance alone does not establish root-self render parity. The E3
source-index RFC remains unchanged and design-only.
