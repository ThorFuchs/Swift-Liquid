# Swift-Liquid 1.2 roadmap

## Adopted scope

The maintainer adopted this scope and authorized implementation on 2026-10-15.
Swift-Liquid 1.2 adds opt-in render metrics and a CLI JSON metrics file.
Applications could observe elapsed time and logical budget consumption while
retaining the same rendering behavior, explicit partial maps and immutable
engines. These are two parts of one observability feature, with no language
extensions or package dependencies.

This scope follows [1.1.0](Releases/1.1.0.md), which shipped typed custom
filters and AST inspection. The updated [RhoeLiquid review](Architecture/UpstreamFeatureReview.md)
compares the remaining features against that release. The
[metrics contract](Metrics.md) specifies the public API and CLI schema.
Publication requires a later explicit request and completed release gates.
Metrics and CLI implementation are complete. The [1.2.0 release notes](Releases/1.2.0.md)
cover the candidate, with matched 1.1.0 measurements and final release qualification.
The [adopted 1.1 roadmap](Roadmap.md) remains the
record of the previous scope decision.

## Why metrics next

The existing [inspection API](Inspection.md) describes syntax without executing
it. Runtime metrics answer how much work this particular invocation consumed,
including its partials and application filters. Both source rendering and
parsed-template reuse should be measurable.

RhoeLiquid's metrics combine phase timings with cache statistics, AST counts and
estimates of its custom string storage. Swift-Liquid already owns logical
counters in each invocation's `RuntimeBudget`, and uses native Swift strings.
Expose observations from the existing execution path rather than adding Rhoe's
cache, string representation or separate measured renderer. This also provides
evidence for deciding whether later optimization or cache work is needed,
without promising a speedup.

## Compatibility boundaries

- Retain Swift tools/compiler 6.4+, Swift language mode 6, one public `Liquid`
  library, one `liquid` executable and an empty root dependency graph.
- Preserve the 1.0 and 1.1 public APIs, default output, parser modes, errors,
  diagnostics and limits. Existing methods keep their signatures and perform no
  timing collection. Existing `analyze` JSON schema 1 is unchanged.
- Keep inputs, engines, templates and results checked Sendable. Mutable measurement
  state belongs to one invocation, shared by its nested work. No global counters,
  actors coordinating unrelated renders, registries, logging sinks or measurement
  callbacks.
- Keep the AST private and library I/O explicit. Metrics contain durations and
  counts, without source text, paths, context values or filter arguments.
- Preserve fixture bytes, pins, licenses and parser-mode metadata. Metrics are
  Swift API evidence, separate from Shopify rendering compatibility.

## Opt-in library metrics

Add measured entry points for source and parsed templates, with the same context,
partial and syntax-mode inputs as their existing counterparts. Return an
immutable, checked Sendable result containing output and metrics. Provide an
explicit counterpart for diagnostic rendering so callers can retain recovered
diagnostics without switching error policy. The [contract](Metrics.md) selects
`renderWithMetrics`, `renderWithDiagnosticsAndMetrics`, `LiquidRenderMetrics`
and `LiquidMeasuredRenderResult` for these boundaries.

Keep the initial payload small:

| Observation | Meaning |
| --- | --- |
| Total elapsed duration | Monotonic elapsed time from measured library entry through final output admission, including parsing when requested, value admission and suspended host callbacks; excludes caller and CLI I/O |
| Parse elapsed duration | Parsing work for the root and all supplied partial sources; present for source entry points, absent for already parsed templates |
| Source bytes | Admitted UTF-8 bytes of the root and all supplied partials, including unused supplied partials, matching the existing source capacity |
| Output bytes | UTF-8 bytes of final returned output; excludes captured or temporary buffers |
| Render steps | Capacity consumed from the invocation's existing evaluator-step budget |
| Loop iterations | Capacity consumed from the invocation's cumulative iteration budget |
| Admitted values | Capacity consumed from the context/custom-filter value budget, including repeated boundary admissions |

Use a monotonic clock such as `ContinuousClock`; the Liquid reference clock
continues to control date evaluation independently. Document timing boundaries,
including empty sources and partial parsing. Parse time is a subset of total
elapsed time, not an additional duration to add to it. Do not time individual
nodes, filters or partials in this release.

Snapshot existing budget consumption without extra evaluation, a second render
or an AST walk for metrics. Include nested `include`/`render`, loops and filter
boundary admission exactly as the current budgets charge them. These are logical
capacities consumed by this implementation version, not CPU instructions,
allocation counts, unique input values or a portable cost model. No heap/RSS
estimate, cache hit rate, static complexity score or inferred render time belongs
in this payload.

Measured throwing renders preserve the corresponding unmeasured error identity
and cancellation checks. Explicit diagnostic rendering may return metrics with
recovered output and diagnostics. Syntax, admission, quota, cancellation and
unexpected host failures still throw; 1.2 returns no partial metrics for failed
invocations and introduces no error wrappers. Successful metrics must never
certify output from a failed render.

## CLI metrics file

Extend `liquid render` with an explicit metrics-file option, provisionally
`--metrics PATH`. Write the same library observations as a separate UTF-8 JSON
document. Rendered output continues to use stdout or the existing output option;
metrics never share stdout with template output. With no new option, stdout,
stderr and exit behavior remain unchanged. `validate` and `analyze` gain no
runtime measurement mode.

The CLI keeps its existing preparation and error order, then uses the measured
parsed-template entry point. Its total elapsed duration excludes CLI parsing as
well as file I/O, and parse elapsed is absent. Measuring end-to-end command time
or introducing a second CLI timing model is outside this scope.

Before freezing the interface, specify required fields, integer duration units,
overflow handling and schema evolution in the CLI contract. Start a separate
metrics schema at version 1; distinguish absent parse time from a measured zero.
Serialization must not expose non-finite numbers or depend on locale. Retain the
existing inspection schema independently.

Validate the destination before rendering. Reject `-` and destinations that
alias the render output or any template/context/partial input, including symlink
aliases. Write a complete metrics document atomically only after a successful
render. Document that an older destination may remain after a failed run; it is
not evidence for that attempt. A metrics write failure must produce stderr and
a nonzero exit status, even if rendered output was already delivered. The two
output destinations do not form one atomic transaction.

## Acceptance cases

1. Compare measured and unmeasured output, diagnostics and error identity through
   source and parsed public entry points in all parser modes, using a fixed Liquid
   reference clock. Cover empty sources,
   Unicode bytes, unused partials, nested scopes, `break`/`continue`, captures and
   final output that differs from intermediate buffer sizes.
2. Assert exact logical counts for small public regressions tied to documented
   charging rules. Cover context admission, ranges, standard/custom filter chains
   and repeated boundary admission. Check source/parsed execution counts and their
   different parse-timing presence. Avoid timing thresholds in unit tests.
3. Exercise suspending callbacks, recoverable failures, foreign errors, quota
   exhaustion and cancellation. Elapsed time includes suspension; logical budgets
   do not bound host I/O, allocations or execution time. Preserve failure semantics
   without treating absent metrics as success.
4. Share parsed roots and partials across concurrent measured and unmeasured
   renders with different filters and limits. Verify isolation under ThreadSanitizer
   and regressions under AddressSanitizer. Add an independent metrics consumer;
   retain all three existing consumers.
5. Test CLI JSON types/units, parse-time absence, empty/Unicode output, explicit
   output files, input/destination aliases, unwritable destinations and render
   failure. Preserve existing commands and inspection JSON.

## Delivery sequence and release gates

| Step | Deliverable | Completion condition |
| --- | --- | --- |
| 1 | Adopt scope and write contracts | Settle result types, raising/diagnostic entry points, timing boundaries, counter meanings and CLI schema before changing execution. |
| 2 | Implement library metrics | Reuse the normal render path and invocation budget; qualify public regressions, consumer, cancellation and concurrent isolation. Record actual adaptations in the extraction manifest. |
| 3 | Add CLI and documentation | Present the library payload through the explicit metrics destination; qualify JSON, I/O failures and unchanged CLI behavior. Publish API and usage guides. |
| 4 | Qualify release candidate | Run all eight release lanes, review matched measurements and source compatibility, rebuild the clean archive, and prepare release notes and evidence. |

Run affected work through `Scripts/ci.py`. Final qualification retains native,
safety, reference, platforms, docs, performance, matched-performance and archive.
Keep successful renders, expected errors, recovered output, supported-domain
boundaries and reference failures distinct; exclusions or missing cases cannot
become passing renders. Retain macOS runtime and four simulator-SDK compile checks;
additional platform support needs its own actual runtime gates.

For 1.2 preparation, extend the matched harness deliberately to use immutable
1.1.0 commit `1107ec865b9ae7ed35e1245386ba882db3abd93d` as the baseline. Preserve
the 1.0/1.1 evidence and historical comparisons. Compare all common workloads,
including custom filters and source/reused inspection, with unchanged inputs,
outputs, checksums and sampling on one host/toolchain. Measure new metrics entry
points against corresponding unmeasured candidate paths, and the disabled path
against 1.1.0. Build before timing, retain raw samples and environment receipts,
review flags and investigate regressions. Report instrumentation overhead; an
elapsed-time field is not a benchmark result, and test counts cannot show speedup.

No other feature is a 1.2 stretch goal. If metrics cannot share existing semantics
safely, revise the proposal before broadening the runtime. Publication follows
qualification on the exact main commit, reviewed notes, source/DocC archives,
qualification evidence, checksums and an explicit maintainer publication request.

## Deferred work

Custom tags need a grammar, nested-content, scope and host-error design. Exact
output provenance needs source ranges and execution instrumentation; interactive
debugging adds bounded session state. Neither follows automatically from counters.
Caches, compiled paths and pooling need measured demand beyond
[application-owned parsed-template reuse](Reuse.md).

Recursive partial graphs need explicit input maps, dynamic-reference semantics,
cycles and graph limits. Additional filters can use the 1.1 host API. Data
adapters, filesystem/network/database loading, DOCX and services belong in
integrations depending on Swift-Liquid. Inheritance, macros, slots, contracts and
functions remain separate language decisions. Broader CLI commands, shell tooling
and WASI/Linux runtime qualification remain independent backlog items, without
a 1.2 commitment.
