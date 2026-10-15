# Swift-Liquid 1.3 roadmap

## Adopted scope

Swift-Liquid 1.3 adds bounded partial-dependency inspection to the library
and an explicit dependency mode to `liquid analyze`. Applications inspect
a root and their supplied partial map to find literal dependencies, missing
references, dynamic includes and cycles without rendering the bundle.

This is one tooling feature with two entry points. It builds on the AST
inspection shipped in 1.1 and preserves the opt-in metrics shipped in
[1.2.0](Releases/1.2.0.md). The [RhoeLiquid feature review](Architecture/UpstreamFeatureReview.md)
records the source findings and the other capabilities that remain deferred.
The maintainer adopted this scope on 2026-10-15. The [dependency contract](Dependencies.md)
freezes the public API, capacities and separate CLI report schema. JSON Schema
qualification uses the published Swift-JSON package in isolated tooling, keeping
the root dependency graph empty.

## Why dependency inspection next

The current [inspection API](Inspection.md) describes one template and deliberately
does not follow partials. Hosts already retain explicit root/partial bundles for
[reuse](Reuse.md), so they can supply every source without introducing a loader
into the library. A dependency report helps editors, build tools and applications
inspect those bundles before choosing what to render or invalidate.

RhoeLiquid's analysis exposes template references alongside authoring contracts,
file resolution, macros and heuristic scores. Its standard-reference manifest is
a direct AST summary. The adopted bounded graph is a new Swift-Liquid design
using that analysis idea and the existing parser; it is not an upstream graph
implementation ready for extraction.

| Candidate | Disposition for 1.3 | Reason |
| --- | --- | --- |
| Partial-dependency inspection | Adopted scope | Extends existing AST tooling over explicit inputs without adding language or hosting policy. |
| Runtime custom tags | Separate design | Grammar, nested content, scope mutation and host failures need a larger execution contract. |
| Cache, optimizer and renderer pooling | Continue application-owned parsed reuse | Metrics and small release workloads do not establish demand for a new shared-state subsystem. |
| Exact provenance and debugging | Separate observability work | Source/output ranges, suspension and captured values need their own bounded contracts. |
| Data adapters, loaders, DOCX and services | Independent integrations | Keep format dependencies, I/O and operational policy outside the engine. |

## Compatibility boundaries

- Keep Swift tools/compiler 6.4+, Swift language mode 6, one `Liquid` library,
  one `liquid` executable and an empty root dependency graph.
- Preserve all 1.0–1.2 public declarations and behavior: rendering, filters,
  diagnostics, parser modes, inspection, metrics, limits and cancellation.
  Existing inspection JSON schema 1 and metrics JSON schema 1 keep their meaning.
- Add opt-in operations with checked Sendable inputs and immutable results.
  Traversal, visited sets and capacities belong to one invocation. Engines and
  parsed templates retain no mutable graph, cache or callbacks for this work.
- Keep the AST private and use the same parser and inspection traversal authority.
  Inspection evaluates no expressions or filters and accepts no runtime context.
- Preserve fixture bytes, metadata, licenses, checksums and reference pins.
  Graph tests are tooling evidence, separate from Shopify render accounting.

## Library dependency inspection

Provide source and reusable parsed-template entry points accepting a root and an
explicit named partial map, matching the existing composition model. Source
inputs use the selected parser mode. Parsed inputs keep each template's original
parser mode and do not reparse it. The [dependency contract](Dependencies.md) specifies the public names and signatures.

Admit and inspect the whole supplied bundle before constructing the graph,
including unused partials. Apply cumulative source admission and syntax-depth
checks to both entry points. An unused malformed source therefore fails the
source operation; a parsed template admitted under looser limits must still pass
the current inspection limits. Return the graph reachable from the root through
literal references. Unused supplied templates do not become reachable simply
because they are present in the map.

The immutable result describes:

| Observation | Contract |
| --- | --- |
| Root and reachable partial nodes | Distinguish the root identity from every possible partial name; retain each node's existing inspection summary. |
| Literal edges | Retain the originating node, requested literal spelling and resolved supplied key when present. Repeated identical references can share one edge; this is not an occurrence or execution count. |
| Missing literal references | Report the origin and requested name as data, without loading or inventing a template. |
| Dynamic includes | Mark their originating nodes as unresolved dynamic references; do not evaluate names or connect them to every supplied partial. |
| Cycles | Report deterministic strongly connected groups, including self-loops, without enumerating every possible cycle or traversal path. |

Resolve names with the existing renderer's lookup order: the requested key first,
then that name plus `.liquid`. Preserve the requested spelling separately from
the actual supplied key, and perform no filesystem path normalization. The
current `[String: ...]` maps use [Swift String equality](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/StringsAndCharacters.md#string-and-character-equality), so canonically equivalent
keys cannot represent separate entries. The contract must preserve that lookup
behavior while retaining exact UTF-8 spellings in reported names; adding a new
name-resolution model is outside this scope.

The [dependency contract](Dependencies.md) defines deterministic UTF-8 ordering,
exact-spelling equality, edge deduplication and cycle-group ordering. Traversal must visit each
resolved template once and use bounded worklists. Shared dependencies in a
diamond graph must not cause repeated expansion or an exponential path list.

The report describes retained syntax, including conditional branches and loops.
It cannot prove which templates execute, that inputs are sufficient, or that a
render succeeds. Missing references and cycles are report findings, not syntax
errors or a general validity verdict. Dynamic `render` names retain their
existing rejection; valid dynamic `include` names stay unresolved.

## Work limits and errors

Retain the current `sourceBytes` and `nestingDepth` meanings. Add an explicit,
finite analysis capacity profile for supplied template count, cumulative supplied
name bytes and retained edges. Count the root and all supplied entries before
allocating graph storage; empty sources must not bypass the count bound. Count
admitted names and literal references with overflow-safe arithmetic. The
[dependency contract](Dependencies.md) records finite defaults and exact charging rules.

Keep syntax depth distinct from graph cycles and graph size. Implement cycle
detection without unbounded call-stack recursion. Do not spend or reset rendering
capacities such as `renderSteps`, `loopIterations`, `contextValues` or output
capacity. These are logical work/storage limits, not heap/RSS or time guarantees.

Validate capacity profiles before work and check cancellation during admission,
inspection, graph expansion, cycle detection and result assembly. Preserve
`CancellationError` and existing syntax/admission error identities. Define new
analysis-capacity failures explicitly, without relabeling a missing partial as a
quota failure. Failures return no partial graph; graph findings remain successful
observations even when they describe missing references or cycles.

## Explicit CLI dependency mode

The adopted opt-in form is:

```sh
liquid analyze page.liquid --dependencies --partials ./partials --format json
```

Without `--dependencies`, retain the existing one-template behavior, accepted
options, text output and inspection JSON schema 1. Only dependency mode accepts
the partial directory; the directory can be omitted to inspect an explicit empty
partial map. Root stdin remains available. No context or application callbacks
are loaded.

Keep filesystem work in the CLI. Reuse its explicit `.liquid` discovery and
relative-name mapping, with cumulative source, template-count and name-byte
admission before retaining/parsing the bundle. Preserve hidden-file, symlink and
directory-containment rules. Specify deterministic failure for ambiguous
discovered names under the map's equality rules; do not silently replace a
partial. This mode must not expand file discovery beyond the supplied directory.

Use a separate dependency-report JSON schema, starting at version 1 with an
explicit report-kind discriminator. Freeze required types, node identities,
ordering, missing/dynamic references, cycle groups and evolution rules before
implementation. Include no absolute source paths or timestamps. The existing
single-template schema does not acquire graph semantics.

Text and JSON present the library result. A completed report exits 0 even when
it contains missing references, dynamic references or cycles. Syntax, input,
usage, capacity and cancellation failures exit nonzero through the existing
stderr convention and emit no graph. An automatic CI rejection policy or a new
`--check` mode is separate work; consumers can inspect the explicit JSON findings.

## Acceptance cases

1. Exercise chains, diamonds, repeated references, exact-key/suffix precedence,
   alias names, self-loops and multiple cycle groups. Return stable results for
   permutations of the same accepted map entries and preserve Unicode spelling.
   Separately cover canonical-equivalence lookup and names resembling a root label.
2. Cover missing and dynamic references in retained branches, raw/comment blocks,
   multiline `liquid`, captures and loops. Unknown filters remain inspectable;
   a registered callback that fails if invoked must remain untouched.
3. Compare source and parsed bundles built under matching parser modes; separately
   verify mixed parsed-mode retention. Check unused malformed/over-limit inputs,
   current-limit admission, empty-source template-count exhaustion, long names,
   wide graphs, deep chains and edge-capacity exhaustion.
4. Cancel during traversal and cycle analysis. Concurrent graph inspections and
   ordinary/measured renders of the same roots/partials must share no mutation.
   Add an independent public consumer and meaningful sanitizer regressions.
5. Verify the separate CLI schema, deterministic output, stdin, supplied-directory
   boundaries, duplicate names, limits and visible failures. Preserve all existing
   commands, inspection schema 1, metrics schema 1 and the four existing consumers.

## Delivery sequence and release gates

The implementation in PR #9 was merged for release preparation on 2026-10-15.
The [1.3.0 candidate notes](Releases/1.3.0.md) describe the delivered API and CLI.
Final qualification compares all 26 common 1.2 records and the 24-pair candidate
metrics phase; the four new graph workloads remain separate observations.

| Step | Deliverable | Completion condition |
| --- | --- | --- |
| 1 | Adopt scope and freeze contracts | Settle result identity, name resolution, admission, capacities, findings, failures and CLI schema. |
| 2 | Library dependency inspection | Implement one parser/inspection authority, bounded graph expansion and cycle groups; record actual adaptations in the extraction manifest. |
| 3 | CLI and documentation | Add the explicit dependency mode and public consumer, with no changes to ordinary analysis or rendering. |
| 4 | Release qualification | Retain every prior gate, review matched measurements, rebuild clean archives and prepare release notes/evidence. |

Run affected checks through `Scripts/ci.py`. Final qualification retains all eight
lanes: native, safety, reference, platforms, docs, performance, matched-performance
and archive. Preserve the 1.2 baseline's 116 public declarations, four consumers,
54 test functions and 60 CLI cases, then add meaningful graph acceptance cases.
Keep successful renders, expected/recovered errors, supported-year boundaries
and reference failures distinct. Retain macOS runtime qualification and all four
simulator-SDK library builds; new platform claims require actual runtime gates.

For 1.3 release preparation, pin immutable 1.2.0 commit
`8676da8059e71905632c233cffb438f8edbf51d2` as the comparison baseline. Preserve its
common render, inspection and metrics workloads, harness/manifest identities,
sampling and output checksums when adapting the matched gate. Add source/parsed
graph workloads with stable expected results, including shared dependencies and
cycles. Separate graph construction costs from existing render/metrics costs.
Build before timing, retain all measurements/environment receipts and review
every threshold flag. Neither graph size nor test count supplies a speedup claim.

No other feature is a 1.3 stretch goal. Publication requires completed exact-main
gates, reviewed notes, source/DocC archives, qualification evidence, checksums and
an explicit maintainer publication request.

## Deferred work

Runtime custom tags, inheritance, macros, slots and input declarations retain
their separate language and execution decisions. Exact output provenance and
interactive debugging need instrumentation and privacy/suspension contracts.
Cache APIs, compiled paths and pooling need measured demand beyond explicit
parsed-template reuse. Data formats, automatic value conversion, filesystem or
network loaders, DOCX and services belong in independent integrations. CLI batch,
scaffolding, completions/man pages, and Linux/WASI runtime qualification remain
independent backlog items.
