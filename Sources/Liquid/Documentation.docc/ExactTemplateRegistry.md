# Exact named content

Store ordered raw or parsed content using ``LiquidTemplateRegistry`` and resolve
an exact UTF-8 name with ``LiquidTemplateRegistry/resolve(_:)``. Canonically
equivalent spellings can be independent entries. Exact duplicates fail; suffix
fallback appends literal `.liquid` only when its exact base is missing.

```swift
import Liquid

let names = try LiquidTemplateRegistry([
    .init("é", .raw("first")),
    .init("e\u{301}", .raw("second")),
    .init("card.liquid", .parsed(try LiquidTemplate("{{ title }}")))
])
let selected = try names.resolve("card")
// selected?.name is the stored spelling "card.liquid".
```

This development U1 primitive is not connected to rendering or dependency
inspection. Existing `templates:` APIs keep their legacy identity behavior.
No Vapor migration or exact partial-rendering claim follows from constructing it.

## Limits and ownership

``LiquidTemplateRegistry/Limits`` caps entry count, total declared-name bytes and
per-name/request bytes. Zero permits the corresponding empty use; negatives fail.
Content source bytes are not admitted here, and raw strings are not parsed.
Cancellation and typed capacity errors throw; only a genuine missing lookup is nil.

The registry and its parsed content are immutable Sendable snapshots. Resolution
returns stored spelling/content/index, not an authorization grant. Hosts control
name access and safe error/log presentation. No path normalization, disk access,
network loading, global cache or automatic escaping occurs.
