# SL21-02A.2 — recovery study and RED controls

This checkpoint adds authored controls only. It follows the unqualified WIP;
it does not modify production parsing or rewrite the original 96-case matrix.
The fixed Ruby harness generates three mode-expanded observations per source
using the clean Shopify Liquid 5.14.0 pin, a fixed input context and strict
filter errors. Test sources are data; no fixture expression is evaluated as Ruby.

## Four remaining lax contracts

| Case | Source UTF-8 bytes | Reference outcome | WIP outcome |
| --- | --- | --- | --- |
| single escaped delimiter | `123 123 32 39 97 92 39 98 39 32 125 125` | render `97 92` | parse error, nil line/column |
| double escaped delimiter | `123 123 32 34 97 92 34 98 34 32 125 125` | render `97 92` | parse error, nil line/column |
| single unclosed | `123 123 32 39 97 92 110 32 125 125` | render empty with the original empty context | parse error, nil line/column |
| double unclosed | `123 123 32 34 97 92 110 32 125 125` | render empty with the original empty context | parse error, nil line/column |

In a context containing `a.n = NESTED`, the same unclosed `a\\n` fragment
renders `NESTED` in Ruby. Empty output is therefore not a substitute for the
reference lookup. Related historical native assertions reject the unmatched
quote and are retained unchanged; their disposition is pending review.

## Distinct reference stages

* `liquid/tokenizer.rb` first frames template output and tags from outer
  delimiters without treating a quoted string as a protected nested region.
* `liquid/lexer.rb` accepts matching quoted spans literally and does not treat
  backslash as an escape. Invalid strict lexical input throws syntax errors.
* `liquid/variable.rb` tries the strict parser before falling back in lax mode.
  Its fallback searches `QuotedFragment` for the first expression, then scans
  filter fragments and arguments separately. `expression.rb` interprets the
  resulting expression; an unclosed quote can be skipped before a lookup.
* `parser_switching.rb` also has a separate selected-parser dispatch. `assign`
  chooses its own parser and constructs a `Variable` for the right side;
  `echo` constructs a `Variable` directly. Other tags such as `if` and `for`
  have their own lax parsing and must not be assumed to share Variable fallback.
* Ruby source framing, lexical recovery, expression evaluation, and host error
  handling are distinct phases. Strict reference errors carry a line number;
  this does not provide a Ruby column or justify dropping a Swift origin.

The rejected WIP experiment skipped any unmatched quote in a closed output and
synthesized lookup separators. It happened to satisfy the small empty-context
matrix, but could reinterpret filter arguments or trailing markup and changed
historical expectations. Those effects cannot establish a general recovery
contract. The expanded 75 observations cover filters, tags, delimiter framing,
multiple outputs, trailing markup, controls and lookup context before another
production change. A matching assertion must have the same error phase and
language-error category; operational failures are not accepted as language
errors. The generator and raw reference observations are source-bound fixtures.

The original RED, prior experiment, original test assertions and receipts are
preserved separately; this document does not approve an expectation change.
