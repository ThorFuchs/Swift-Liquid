# Inspect templates without rendering

Read variable roots, filters and partial references from a template's parsed AST.

## Overview

The unreleased 1.1 inspection API returns an immutable
``LiquidTemplateInspection``. Inspect source or reuse a ``LiquidTemplate``:

```swift
let engine = LiquidEngine()
let source = "{{ user[key] | escape }}{% render 'card' %}{% include selected %}"
let summary = try engine.inspect(template: source, syntaxMode: .strict2)
let parsed = try LiquidTemplate(source, syntaxMode: .strict2)
let reused = try engine.inspect(parsed)
assert(summary == reused)
// Roots: key, selected, user; filters: escape; literal partials: card.
// A dynamic include reference is present.
```

The lists are unique by exact UTF-8 spelling and sorted in ascending UTF-8 byte
order. Canonically equivalent spellings remain distinct. Roots include local
variable reads and every retained branch; they are not a required-input schema.
Literal property keys, assignment targets and counter names do not count as reads.
Filter argument values and dynamic bracket keys do. Raw/comment/documentation
blocks do not contribute references. Parser-discarded tokens do not appear.

Inspection never evaluates expressions, invokes callbacks, renders output or
loads partials. Unknown filters and missing partials are permitted. Inspect each
partial independently; no partial graph is followed. Engine filter registration
and strict-filter policy have no effect on the summary.

Source inspection uses the normal parser mode. Reused inspection checks the
engine's source and nesting limits without reparsing. It checks cancellation
throughout traversal; rendering capacities are not consumed. Errors return no
partial summary. All public configuration, templates and summaries are checked
Sendable and each traversal owns its temporary sets.

## Command line

```sh
liquid analyze page.liquid --syntax-mode strict2 --format json
```

The default text presentation uses four labeled lines. JSON schema 1 contains
`schemaVersion` (integer 1), `variableRoots`, `filterNames`, `literalPartialNames`
(string arrays), and `hasDynamicPartials` (boolean). Every field is present,
including empty lists. Consumers ignore unknown fields and reject unsupported
schema versions; changes to existing field names, types or meaning require a new
version. Formatting and key order are not part of the schema.

The command reads one UTF-8 file or `-` for stdin. It accepts only parser mode and
format options, writes summaries to stdout, and uses the existing stderr/exit-1
failure convention. No context or partial sources are loaded.
