# Measured maintenance

Sprint 4 retains observations that explain performance and cancellation behavior
without changing the released 1.0–1.3 engine contracts. The standalone
`Tools/MaintenanceBenchmarks` package links only the local public Liquid library.
The root package retains one library, one CLI and no package dependencies.

```sh
python3 -B Scripts/ci.py --lane performance
python3 -B Scripts/ci.py --lane matched-performance
```

Run timing on an otherwise idle host. Matched qualification requires a clean
candidate and the immutable 1.3.0 commit described in [performance](Performance.md).
CI serializes the matched job after the initial qualification matrix. The provider
may share physical resources; this does not establish thermal or scheduling isolation.

## Review variability

The matched comparison retains three serial ABBA blocks, six runs per side and
25 raw samples per record. Schema 4 adds observed run-median distributions:
minimum, maximum, median, median absolute deviation (MAD), relative MAD and range
as a percentage of the median. Absolute median changes of at least 10% retain
the existing change-review flag. A run-median range of at least 10% on either side
adds a separate variance-review flag. Equal medians do not suppress that flag.

Inspect all observations and flags before drawing a conclusion. A wide range can
reflect scheduling, workload effects or environmental variation; the flag does
not identify a cause. Samples within a run and runs on one host are not assumed
independent. MAD and range are descriptive, not confidence intervals or proof of
a speedup. Preserve flagged runs and investigate a specific hypothesis before
any repeat. Do not rerun until a preferred result appears.

The next release's comparison pins 1.3.0. Released 1.0–1.3 notes and measurements
remain historical records. A source-bound, checksum-bound review acknowledges
both change lists and both variance lists before release packaging.

## Measure larger inputs

The maintenance tool emits six larger-workload records: source and parsed calls
for each shape. It uses five warmups, 25 samples and one call per sample.

| Workload | Shape | Verified output |
| --- | --- | --- |
| `large-loop` | 1,024 UTF-8 string values | The same ordered row repeated 1,024 times |
| `large-escape` | 8,192 copies of an HTML-like string | Independently assembled escaped text |
| `partial-fanout` | 256 isolated render calls to one partial | The exact partial repeated 256 times |

Timing begins immediately before the public render call and ends after its
result returns. Source calls include their own parsing and admission. Parsed
roots and partials are prepared outside timing. Expected-output comparison and
FNV-1a hashing are outside this timing boundary, unlike the historical common
harness. These records must not be compared as if their boundaries were equal.
Each retains all samples, median, p95, minimum, maximum, input shape, cumulative
source bytes, final output bytes and checksum. They are candidate observations,
not cross-version regressions or peak-memory measurements.

## Observe cancellation at a real boundary

Cancellation observations cover source/parsed calls and all four public rendering
policies: ordinary, diagnostic, measured and diagnostic/measured. Each runs with
two host behaviors, producing 16 records with five warmups and 25 measured samples.
The driver uses an explicit `@concurrent` entry and detached workers; callback
construction does not inherit the executable entry point’s serial MainActor.
See Swift’s [async-main semantics](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0323-async-main-semantics.md)
and [explicit concurrent execution](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md).
A checked actor barrier signals actual callback entry before cancellation. There
is no sleep, workload-size race, production hook or timing threshold.

A cooperative callback suspends in a cancellable `AsyncStream` wait. Cancellation
ends that wait successfully, requiring the engine's own post-callback check to
throw `CancellationError`. An explicit-release callback suspends in a checked
continuation that intentionally ignores cancellation. The controller verifies
that it has not exited, then releases it. The engine cannot preempt arbitrary host
code; cancellation becomes observable after that code returns or throws.

The outer clock records cancellation request to awaited worker completion. That
interval includes task cancellation, host resumption, actor/executor scheduling,
the engine check and task-result delivery. For explicit release, raw samples also
split it into request-to-release and release-to-completion intervals. Release is
recorded immediately before the controller's actor call. No synthetic delay is
introduced, and the split is not a bound on arbitrary real host work.

Every observation requires `CancellationError`, no later filter evaluation and a
healthy subsequent invocation of the same engine. A separate deterministic Swift
Testing regression also covers a noncooperative callback that returns successfully
or throws a recoverable filter failure, across all four policies and both source
forms. Tests release the host before checking the outcome; they assert behavior,
never a microsecond deadline.

Eight additional `runnable-escape` records cover all four policies and both source
forms. Their callback signals entry and returns immediately before a 128 KiB
HTML-escaping input. An independent Dispatch controller waits for that signal,
stamps the request and
cancels the worker. Only the Dispatch thread blocks on a semaphore; the Swift
cooperative executor never performs a blocking wait. A start stream admits the
worker only after the controller is installed. Worker completion also signals the
controller so an entry failure cannot strand its wait. There is no suspension
barrier holding the callback. This placement prevents a busy Swift executor from
deferring the controller task until after rendering completes; Dispatch scheduling
and the request/check race still affect the observations. Retain all 25 outcomes:
`cancelled`, `completed-before-request` or `completed-racing-request`, with a signed
completion-time offset from the request. The worker stamps completion immediately
after the public return or error, before result delivery to the driver. Normal
completions must match the exact
escaped output. Completed observations are not cancellation successes.

Cancellation-only median/p95 summaries are conditional on the cancelled subset;
they are null when that subset is empty. Always read the denominators and raw
outcomes alongside those summaries. A completed call can race the request after
its last engine check, so that outcome is recorded rather than declared a
cancellation failure. The signal does not identify an arbitrary internal filter
instruction, and these observations cannot establish its exact interrupt point.
No late request is discarded to improve the response distribution.

The coordinated records establish cancellation at an entered callback boundary. They do
not establish response at an arbitrary parser, Foundation filter or synchronous
graph instruction. Synchronous inspection retains entry-cancellation coverage.
Host callbacks remain responsible for their I/O, allocations and cooperation.

## Admit and retain evidence

`Scripts/maintenance_evidence.py` requires all shapes and scenarios exactly once,
finite positive operation/coordinated samples, finite signed runnable offsets,
recomputed summaries, expected output shapes
and checksums, successful coordinated cancellation accounting, interval consistency, exact
runnable outcome accounting and engine reuse. Negative regressions reject missing/duplicated scenarios, changed outputs,
invalid samples, misleading summaries and inconsistent cancellation intervals.
Slow but internally valid observations are admitted; admission is not a speed
verdict. The performance receipt binds them to source, compiler and host metadata.
Release preparation requires this evidence alongside the existing graph records.

Keep logical source/output/value/step quotas, elapsed latency and process memory
separate. No RSS, peak allocation, hard deadline, universal response time or
cross-engine superiority is inferred. The runnable observations exposed normal completion after cancellation during
last-filter work. Output admission now checks cancellation before its byte quota,
including final delivery, without consuming evaluator steps or changing quotas.
A deterministic internal budget-boundary regression covers empty, fitting and
oversized output, cancellation precedence and unchanged logical counters. Public
rendering tests and measurements cover integration. This adds a checkpoint; it
does not preempt the synchronous helper or eliminate the final request/return race.
Public APIs, successful output, fixture pins and the dependency graph are preserved.
