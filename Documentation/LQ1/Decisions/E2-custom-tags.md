# E2 — Custom tags and blocks

Status: design study; deferred. Signed **Codex, 2026-10-15**; maintainer review pending.

Problem: peer engines permit parser plugins, while Swift-Liquid only exposes
engine-scoped filters. Tag registration is a grammar/AST ownership decision,
not a filter alias. LQ1 adds no tag syntax or registry.

A possible design would separate immutable parse-time plugin definitions from
typed, scoped async execution callbacks. A parsed template must retain a safe,
Sendable representation and an explicit plugin identity/version, never a mutable
global environment or captured arbitrary host model. Standard tag names, closing
names and aliases must be protected by exact lookup and reviewed validation.

Before API design, specify parser ownership: who consumes tokens and the closing
delimiter, which expression productions are available, how nested blocks are
parsed, and how source spans survive. An opaque callback that receives source
and reparses nested bodies risks a second dialect and uncharged work. Plugins
must neither replace the standard parser nor construct arbitrary internal AST.

Execution needs typed values, a scoped view with defined read/write semantics,
charged outputs/context visits/steps/depth, pre/post-await cancellation and
recoverable-vs-foreign error rules. Async callbacks must not keep invocation state
or bypass budgets. Nested blocks need explicit break/continue and partial behavior.
No arbitrary host reflection, filesystem, network or ambient registry is implied.

Required evidence: grammar ambiguity and nested-close tests, standard-name
protection, source/parsed reuse across tasks, reentrant callbacks, quota and
cancellation boundaries, recovery locations and a public consumer. Reject a broad
plugin proposal if it cannot state these contracts in a small typed API. The
independent suite does not require nonstandard tags, so this is not the next
implementation priority.
