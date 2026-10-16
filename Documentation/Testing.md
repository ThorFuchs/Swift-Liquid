# Adversarial tests and execution evidence

Tests protect the released 1.0–1.3 contracts while keeping the root dependency graph
empty. Run affected qualification through `Scripts/ci.py`; the native lane includes
debug/release tests, repeated boundary tests, public consumers and CLI checks. The
safety lane runs the full suite with AddressSanitizer and the thirteen shared-engine
concurrency tests with ThreadSanitizer.

## Reproduce a boundary

`Tests/LiquidTests/AdversarialTests.swift` uses seeds `0`, `1`, `0xc0ffee` and
`UInt64.max`, with bounded input sizes and a one-minute cooperative suite limit.
Failures identify the seed and input where useful. A seed is part of the test
contract; changing it needs review, just like changing an expected result.

The Unicode oracle works from Unicode scalars, preserving composed/decomposed
spellings, controls, joined emoji and delimiters. It checks size, first/last,
slicing and empty-separator splitting against independently assembled output.
JSON cases encode UTF-16 units explicitly, including surrogate pairs, check
ordered scalar-distinct keys and reject every proper scalar-boundary prefix of
an outer container. Small malformed-surrogate/number/duplicate-key cases retain
specific reproductions; JSON error offsets must remain within the input bytes.
A separate example admits 128 nested arrays, objects and alternating containers,
checks their contents and rejects 129 levels. It reproduced sanitizer stack
exhaustion in the recursive JSON reader; parsing now uses a bounded explicit stack
while preserving the same public nesting boundary.

Nested Liquid cases place delimiter-like text inside quotes and raw/comment
blocks, with expected output constructed independently. All three parser modes
must preserve those boundaries; universal malformed examples must produce syntax
errors. Source and output capacities admit the exact UTF-8 byte count and reject
one byte below, including unused supplied partials and diagnostic rendering.
These cases qualify invariants; they add no Shopify conformance-render count.

## Coordinate cancellation

`TestSuspensionGate` uses checked actor isolation and cancellable `AsyncStream`
waits. Tests wait for callback entry before cancelling a render. The callback can
return successfully after cancellation, so the engine's own cancellation check
must prevent later filters from running. A healthy sibling render and a later
reuse check protect invocation-owned state. Existing measured/recovering callback
cases also check that cancellation remains `CancellationError`.

Synchronous inspection and cycle detection expose no public suspension point.
Their tests deliberately cover cancellation at coordinated entry, direct SCC
entry and independent reuse. They do **not** establish cancellation at a chosen
mid-traversal instruction or a latency bound. No sleep, workload-size race or
production-only test hook is used to make that claim. Suite limits are cooperative
and are not process watchdogs; CI retains an outer job timeout.

## Admit structured evidence

The native and safety lanes request Swift Testing's version `0` JSON Lines event
stream explicitly. See [Swift's JSON ABI proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0002-json-abi.md)
and [event schema](https://github.com/swiftlang/swift-testing/blob/main/Documentation/ABI/JSON.md).
`Scripts/test_evidence.py` checks the stream independently of human-readable
success messages. Admission requires:

- One complete run, paired test/suite starts and ends, and a zero process exit.
- Exact function membership and per-function parameter counts from the reviewed
  `Tests/TestInventory.json`; source line changes do not change logical identities.
- Every declared parameter case started and completed exactly once, with matching
  identities within that run. Parallel case interleaving is permitted.
- No skips, recorded issues (including known issues), test cancellation, empty
  parameter collections, missing functions or incomplete events.

The adapter currently requires Swift 6.4's underscored `_testCases`/`_testCase`
metadata for case identity, plus its source-qualified function-ID shape. Those
fields are implementation details, beyond the stable v0 envelope. Missing or
changed metadata, versions or event kinds fail qualification pending adapter
review; they never silently reduce the evidence to function counts. Case IDs are
compared only within one process and are not claimed stable across releases.

`*.events.jsonl`, `*.tests.json` and human logs remain under `Artifacts/<lane>/`.
Summaries contain observed skip/issue/cancellation counts and identities, including
failed parameter-case identities when supplied by the adapter, function/case completion,
process exit, and event/inventory SHA-256 hashes. The lane receipt binds them to
the source snapshot and toolchain. Failure paths retain streams and summaries,
including when the process exits unsuccessfully. Counts describe runner execution,
not successful Liquid renders: recovered reference errors and the 35 date-year
policy boundaries retain their separate [conformance accounting](Conformance.md).

The native lane repeats the 22 selected adversarial/cancellation/barrier functions
twice under normal parallel execution, each with its own exact inventory. The
full current baseline is 114 functions and 2,250 parameter cases; nonparameterized
functions do not emit case events. Published 1.0–1.3.1 receipts remain unchanged.
The thread selector is `concurrentRenders`; the repeat selector is
`AdversarialTests|cancellation|suspension`. New members of those profiles must
match their selector as well as the exact inventory. Admission rejects missing
members even when the test process exits successfully.

`Scripts/check_test_evidence.py` rejects truncated, malformed, duplicated,
reordered, incomplete and filtered evidence. Its separate dependency-free
`Tools/TestEvidenceProbe` package verifies the adapter against the real runner's
passing, failing (including a parameter-case failure), disabled, known-issue,
empty-parameter and zero-match executions.
Deliberate probe failures are expected rejection evidence, never Liquid tests or
conformance successes. Their raw streams, logs, commands and admission decisions
are retained in the native lane's `runner-probe/` directory. Update the reviewed
inventory alongside intentional test additions; never regenerate it automatically
as part of qualification.

## Noncooperative hosts

`CancellationMaintenanceTests` adds 16 source/policy/host-result combinations. A
checked continuation requires an explicit release after cancellation; both a
successful return and a recoverable host error must preserve `CancellationError`,
prevent subsequent filter evaluation and leave sibling/reused invocations healthy.
The release happens before assertions and no sleep or timing deadline determines
success. Separate [response measurements](MeasuredMaintenance.md) report elapsed
observations and scheduling limits without making correctness timing-sensitive.

The internal output-admission regression cancels a task before admitting empty,
fitting and oversized output. Cancellation must precede quota errors, while a
healthy budget retains exact byte boundaries and unchanged step/value/iteration
counters. This reproduces the missing final-delivery checkpoint without relying
on when another thread interrupts a filter. Together with the public measurements
and existing consumer cases, it qualifies the checkpoint without a timing assertion.
