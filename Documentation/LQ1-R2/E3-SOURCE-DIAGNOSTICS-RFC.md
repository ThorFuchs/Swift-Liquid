# E3 RFC: source-index diagnostics and scope-aware inspection

Status: design-only; sole API study proposed for a later reviewed release.
Signed **Codex, 2026-10-15**; maintainer approval pending. Supersedes no API.
Builds on [the LQ1 decision](../LQ1/Decisions/E3-source-analysis.md).

## Problem and evidence

The original independent track has 1,857 parse-diagnostic mismatches; 1,328 lack
enough explicit reason evidence to establish equivalence. Existing token errors
sometimes have no location, and multiline `liquid` parsing rewrites source.
Authors also need to distinguish external input paths from local bindings.
Precise origins can reduce reproduction work. They cannot substitute for a
correct acceptance boundary or turn a comparator failure into a pass.

## Source identity and coordinates

Propose an immutable source index per admitted root/explicit partial. A host
supplies an opaque, exact-scalar source ID; a content digest identifies its
revision separately. Root and each partial map entry have distinct identities,
even when bytes match. Aliases may resolve to the same source ID only through an
explicit binding; no filesystem canonicalization, inferred URL or network lookup.
Duplicate IDs with differing bytes must fail admission. Case and Unicode spelling
remain exact; source IDs never depend on process addresses or dictionary order.

Canonical spans are half-open UTF-8 byte ranges at Unicode-scalar boundaries.
Line and column are one-based Unicode-scalar coordinates; CRLF is one newline,
a lone CR or LF is one newline, tabs occupy one scalar column. Combining marks
and joined emoji contain multiple columns. No normalization, grapheme counting
or silent UTF-16 conversion. An editor bridge may explicitly convert via the
index. Tests must cover empty input, EOF, delimiter trimming, composed/decomposed
strings, non-BMP scalars, CRLF and invalid range boundaries.

Tokens, tag/filter names, expression nodes and delimiters retain origin ranges.
A rewritten multiline `liquid` token must carry an original-source mapping, never
claim the synthetic template's offset as the author's position. Include/render
findings identify the referenced partial and call-site chain without flattening
coordinates into the root. Dynamic or unresolved partials remain explicit unknowns.

## Parse failure and recovery

Current `LiquidTemplate` and inspection throw on parse failure. Preserve that
contract and all parser-mode defaults. Internal diagnostic enrichment may retain
an offending token and insertion/end-of-input span; it must not invent a Ruby
stack trace or fabricate a span from message text. Any future tolerant editor
analysis requires a distinct result with `incomplete` coverage, recovered regions
and diagnostic provenance. Recovered nodes must never be rendered or passed off
as a valid `LiquidTemplate`. Recovery work consumes finite steps and cancellation.

## Paths, scopes and static nonexecution

A prospective additive analysis result could distinguish literal/dynamic path
segments, read/write spans, definite local bindings, possible locals and external
roots. Track assign/capture declarations, branch joins, loop aliases/forloop,
separate increment/decrement counters, shared include scope and isolated render
scope. Preserve supplied static environments separately from caller-local state;
R2's render minimal demonstrates why those cannot be conflated. Reads before a
binding remain external; branch-dependent writes yield uncertainty. A dynamic
key or partial prevents a complete required-input claim.

Never evaluate expressions, invoke filters/tags, inspect Swift model members,
render conditions, load files or fetch data. Analyze only an explicit source or
parsed bundle. Walk all syntactic branches and bound total source/index bytes,
AST visits, graph nodes/edges, recursion and retained findings. Cancellation must
leave immutable indexes/templates reusable; no process-wide registry/cache.

## Compatibility and approval gate

No public types, schema changes or implementation in R2. First prototype internal
source maps and compare a representative diagnostic set without changing expected
bytes. Before proposing an additive public result, review coordinate conventions,
source/parsed equivalence, incomplete coverage, include/render scope, aliases,
cycles, dynamic edges, finite-work/cancellation tests and allocation admission.
Existing inspection JSON and 1.0–1.3 declarations remain unchanged. E1 strict
variables, E2 tags, E4 host loader/output sink and E5 Swift-JSON fidelity bridge
remain deferred; none is needed to implement source provenance.
