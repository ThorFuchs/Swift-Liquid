# SL21-02A.3 — proposed source ownership and recovery contract

This is a bounded design proposal and a test-first checkpoint, not a statement
of complete compatibility. It preserves the SL21-02A.2 reference observations,
security witnesses and unchanged historic tests.

1. **Framing owns source.** An original template is an immutable UTF-8 byte
   sequence admitted under existing source limits. Its existing lexer determines
   construct boundaries and complete quoted literal ranges before any lax
   expression recovery. A complete quoted range remains inert even when its
   bytes contain a sequence that resembles an outer delimiter or a Liquid
   opener. Opening a new construct from inside that range is forbidden.
2. **Recovery has a bounded range.** A recovered expression can inspect only
   the byte range assigned to that expression inside its already-framed
   construct. It cannot change the outer frame, claim bytes from another
   construct, or create AST nodes from bytes in a protected quoted range. The
   existing parser, resource limits, cancellation and UTF-8 origin accounting
   remain authoritative.
3. **Ambiguity fails closed.** If existing framing cannot establish ownership
   without deciding whether an apparent delimiter or opener is literal or
   executable, preserve the old inert interpretation or reject the source.
   Do not infer safety from a particular filter, partial name, rendered output,
   or the absence of a callback in a single test run.
4. **Independent constructs stay independent.** A complete construct followed
   by another genuinely outside every protected range is still framed and
   evaluated normally. This does not grant recovery authority over the second
   construct. A malformed opening whose range could encompass the second
   construct is not an established independent boundary.
5. **Parser modes and errors remain separate.** Strict and strict2 use their
   established parsing, error phase and valid source ownership. Lax recovery
   may only reuse the existing expression parser within the owned frame. A
   Ruby language failure cannot be satisfied by cancellation, a resource limit,
   transport failure or arbitrary host error. Reference lines and Swift-only
   columns are recorded separately.
6. **Capabilities are observed, not guessed.** Security controls instrument
   host object lookup, custom filters and partial resolution. Tests assert
   output, invocation counts, template inspection and dependency inspection;
   positive controls prove explicit registered capabilities still work outside
   protected text. Raw, comment and quoted text are not executable authority.

The reference frames `{{ '}}' }}` at the first `}}`, while the preserved Swift
source treats the delimiter as quoted text. This is a proposed explicit
security-preserving reference divergence in each mode, not a raw match. The
same distinction applies to `%}` inside quoted tag markup. The previously
approved historical expectation dispositions apply only if they remain
consistent with the ownership rule and retained security evidence.

The original 96- and expanded 75-observation reference matrices remain
unchanged. The 21 prior differences require individual dispositions; no
aggregate result establishes feature coverage. If making a recovery safe
requires changing framing ownership or adding a general parser architecture,
the correction is outside this increment and requires a separate decision.
