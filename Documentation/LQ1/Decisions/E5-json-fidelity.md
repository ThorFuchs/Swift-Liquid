# E5 — Optional Swift-JSON fidelity bridge

Status: design study; deferred. Signed **Codex, 2026-10-15**; maintainer review pending.

Problem: the public Liquid value domain is native Int plus finite binary Double.
Swift-JSON has richer JSON and JSON Schema capabilities, but importing it cannot
make Liquid arithmetic arbitrary precision. Preserve zero core dependencies.

Study an isolated companion package that depends on the published
[Swift-JSON](https://github.com/ThorFuchs/Swift-JSON) and Liquid public APIs. Use
Swift-JSON's real schema implementation for optional schema validation rather
than writing a partial validator. Pin its version and test the schema dialect
separately; validation success does not establish lossless Liquid conversion.

Default conversion should reject an integer outside native Int and any decimal
that cannot satisfy a declared fidelity policy. Define whether finite fractional
numbers require exact binary representation or an explicitly accepted rounded
binary domain. An opt-in string marshal may preserve decimal text for display,
but changes template arithmetic and must be clearly named and documented.
No silent Double conversion, overflow saturation or alternate-engine evaluation.

Preserve object ordering, exact Unicode scalar keys, null, array order and error
paths. Explicitly reject or define duplicate keys, excessive nesting, nonfinite
numbers, unsupported number spellings and cyclic host structures. Keep admission
finite before building a large copied value tree. Do not add reflection or
implicit model conversion as a convenience bridge.

Required evidence: Int min/max and neighbors, integers beyond 2^53, decimal and
exponent extremes, underflow/signed-zero policies, scalar-distinct keys,
round-trip representation tests, strict schema positive/negative vectors and a
public consumer proving Liquid still links without Swift-JSON. The current LQ1
adapter already rejects out-of-Int integer lexemes; a bridge is not required to
run portable primitive-JSON cases and is not the next implementation priority.
