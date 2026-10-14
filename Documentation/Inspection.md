# Template inspection

Unreleased 1.1 API. Inspect one template's parsed syntax without rendering it:

```swift
import Liquid

let engine = LiquidEngine()
let source = "{{ user[key] | escape }}{% render 'card', title: title %}{% include selected %}"
let summary = try engine.inspect(template: source, syntaxMode: .strict2)
// variableRoots: ["key", "selected", "title", "user"]
// filterNames: ["escape"]
// literalPartialNames: ["card"]
// hasDynamicPartials: true

let parsed = try LiquidTemplate(source, syntaxMode: .strict2)
let sameSummary = try engine.inspect(parsed)
assert(summary == sameSummary)
```

`LiquidTemplateInspection` is an immutable, checked Sendable value. Both engine
methods use one traversal of the internal AST. Source inspection uses the same
`LiquidTemplate` parser as rendering. The reused overload retains the template's
already selected parser mode; it does not reparse its source.

## Reference semantics

| Field | Meaning |
| --- | --- |
| `variableRoots` | Root names read by parsed expressions, including bracket keys, filter argument values, loop collections/bounds, conditions and dynamic include names |
| `filterNames` | Filter identifiers in parsed pipelines, including unknown and application filters |
| `literalPartialNames` | String literals supplied to `include` or `render`, with their exact spelling and no path/suffix normalization |
| `hasDynamicPartials` | At least one parsed include has a nonliteral name |

Each list is unique by exact UTF-8 spelling and sorted in ascending UTF-8 byte
order. Canonically equivalent Unicode spellings remain separate. Summary equality
also compares exact spellings. The result is independent of engine filter
registration, strict-filter policy, context values and reference clock.

Variable roots are syntactic reads, **not required context keys**. Local variables,
loop variables and `forloop` appear when read. Assignment/capture targets, named
argument labels, literal property names, and increment/decrement counter names do
not themselves count as reads. Every retained branch and loop body is inspected,
even if it would never execute. Raw text, raw blocks, comments and documentation
blocks do not contribute references. Parser modes can reject or discard syntax;
inspection reports the resulting AST, including the parser's retained argument
values when names are repeated. It does not scan ignored source tokens.

For example, `{{ user['name'] }}` reads `user`; `{{ user[key] }}` reads `user` and
`key`. `{% assign local = input %}{{ local }}` reports `input` and `local`.
`{% include 'card' %}` reports a literal name, while `{% include card %}` reports
the `card` variable and a dynamic reference. Dynamic `render` names remain invalid
under the existing language contract.

## Work and errors

Inspection never evaluates an expression, invokes a callback, loads a partial,
accesses a context, or renders output. Missing partials and unknown filters do not
fail inspection. There is no recursive partial graph traversal; inspect supplied
partial templates separately. The AST remains private.

The engine validates its limit profile and applies `sourceBytes` to this one
source and `nestingDepth` to syntax nodes and expressions. These capacities also
apply to a template parsed earlier with looser limits. Rendering capacities
(`outputBytes`, `loopIterations`, `renderSteps`, `contextValues`) are not consumed.
There is no evaluation, and walking the finite AST is bounded by admitted source
and depth. Limits are logical capacities, not process-memory or time guarantees.
Cancellation is checked at entry and throughout traversal and remains
`CancellationError`. Syntax, invalid-limit and source/depth errors retain their
normal `LiquidError` cases. No partial summary is returned on failure.

## CLI and JSON schema

```sh
liquid analyze page.liquid
liquid analyze page.liquid --syntax-mode strict2 --format json
printf '{{ name | upcase }}' | liquid analyze - --format json
```

Text is the default presentation, with four labeled lines. Lists use compact JSON
array notation so quotes, control characters and Unicode names are unambiguous.
Use JSON for automation; text labels and whitespace are presentation details.

Schema version **1** is one UTF-8 JSON object followed by a newline:

```json
{
  "filterNames": ["escape"],
  "hasDynamicPartials": true,
  "literalPartialNames": ["card"],
  "schemaVersion": 1,
  "variableRoots": ["key", "selected", "title", "user"]
}
```

All five fields are required. `schemaVersion` is the integer 1; the three name
fields are arrays of strings with the ordering/uniqueness rules above;
`hasDynamicPartials` is a boolean. Empty lists remain arrays and the boolean is
always present. Output contains no source path or inferred dependency graph.
Object keys are emitted in sorted order; consumers must parse JSON and must not
rely on indentation, key order, or escape choices.

Compatible additions may add optional fields within schema 1. Consumers must
ignore unknown fields and reject unsupported schema versions. Removing/renaming
fields, changing types, or changing the meaning of these fields requires a new
schema version. No environment-dependent timestamps or counts are included.

Only `--syntax-mode` and `--format text|json` are accepted by `analyze`. It reads
one file or stdin with the default 1 MiB UTF-8 source capacity, following existing
CLI input rules. It writes the summary to stdout, errors to stderr prefixed with
`liquid:`, and exits 0 on success or 1 on syntax, input or usage failure. Analysis
failure emits no summary. It does not accept context, partial-directory, output
file, or filter options. See [CLI reference](CLI.md).

The [independent consumer](../Examples/InspectionConsumer) exercises both public
entry points, Sendable conformance, and a callback that must never execute.
Inspection tests are Swift API evidence, separate from Shopify rendering counts.
