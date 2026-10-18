# Exact template registry — development U1 primitive

`LiquidTemplateRegistry` is an additive development API for immutable named raw
or parsed content. U2 connects it to the existing renderer through required `registry:` APIs; see
[exact registry rendering](ExactRegistryRendering.md). Dependency inspection, the
CLI and Vapor retain their existing APIs. Existing `templates:` dictionaries retain Swift's
canonical String identity. No exact graph overload or new release/dependency pin is implied.

Entries preserve caller order. Names compare exact UTF-8 bytes using the existing
internal ScalarKey: composed `é` and decomposed `e` plus U+0301 coexist, as do K
and Kelvin sign. Identical bytes are a duplicate error. Names remain opaque;
empty, relative-looking, absolute-looking, percent-encoded and NUL-containing
strings have no filesystem meaning here. Hosts decide allowed names and access.

`resolve` first checks the exact requested name, then only on miss appends ASCII
`.liquid`. It returns the actual stored index, spelling and content. It never
strips extensions or tries canonical siblings. Indexes identify only one registry
snapshot. Entries and results are checked Sendable immutable values; modifying
the original array or a returned array copy cannot mutate the private index.

Limits default to 4,096 entries, 262,144 aggregate name bytes and 1,024 bytes per
declared/requested name. Limits are nonnegative; zero permits only empty use.
Construction checks cancellation, invalid limits, entry count, then each name's
byte capacity, aggregate bytes and duplicate identity in declaration order.
Capacity errors identify a typed `Capacity`; duplicate errors retain the second
name's raw spelling and may contain private data. They are not safe public HTTP
messages. A missing lookup is nil; overlong requests and cancellation throw.

UTF-8 scanning consumes at most the per-name cap plus one byte before rejecting,
without computing cap+1 or overflowing Int.max. It polls cancellation every64
bytes and on completion. Suffix allocation is skipped unless seven more bytes
fit. Dictionary hashing/equality and copy-on-write operations remain synchronous;
checks surround dictionary access. Cancellation is cooperative, not a hard
deadline. Capacities bound logical name work, not caller allocations, process
RSS, every standard-library operation or a single cumulative render ledger.

Raw content is retained without parsing or source admission. Parsed content keeps
its existing immutable AST/mode. Even enormous or syntactically invalid raw text
can be stored if the **names** fit. This is intentional, not a rendering readiness
certificate. U2 admits root plus all content, including unused entries, against engine source
limits before parsing/evaluation and shares this resolver throughout runtime. U3
exact graph integration remains deferred. No cache, loader, I/O, context
projection, escaping change or new language syntax is introduced.

The standalone [public consumer](../Examples/RegistryConsumer) imports only Liquid
and demonstrates raw/parsed entries, stored byte spelling, suffix fallback, typed
capacity and concurrent reads. Independent compilation, native test receipts,
current limitations and explicit next-gate approval belong to the U1 return.
