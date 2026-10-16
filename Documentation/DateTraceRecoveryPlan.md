# Date trace recovery: infrastructure correction

The original frozen study at 5da238f5a8228fc2dba263c5f8b03a33820f5aba ran all
72 untraced comparisons and completed six CPU captures. The next CPU recorder
stopped returning, despite its target completing all six 20,000-render batches
and writing normal completion output. It remained inside the record command for
more than thirteen minutes, beyond the 60-second recording limit. We cancelled
run 38889400923 to invoke its retention step; that step successfully retained
all observations. This is an incomplete capture cohort, not a successful study.
There is no demonstrated engine hang or proof of the recorder's internal cause.

Recover exact retained trace executables, dSYMs, source inventories, all untraced
runs, six completed profiles and the incomplete seventh capture from artifact
12042343639. Verify executable SHA-256 values before launching. Do not rebuild the
engine or repeat any benchmark measurement. Keep the original source-bound
protocol, observed adverse changes and incomplete data intact.

The recovery runs on a fresh hosted Xcode 27/Swift 6.4 machine. Record its hardware
and compiler separately. Recalibrate 100 known setup transitions in each direction.
Use the original binaries, inputs, auditing, iteration counts, signpost boundaries,
output verification and trace admission. Stream subprocess output directly to
retained files. Bound each command to 180 seconds, then stop its owned process
group with SIGINT, SIGTERM and SIGKILL if necessary; record exit 124 explicitly.
A command timeout is an invalid capture even when the render target completed.

Collect a new complete 32-capture cohort, executor first then CPU. Each instrument
has actor and concurrent callers, release and identical-source ABBA controls.
This order correction obtains bounded executor evidence before long CPU capture
work. Keep the six earlier complete CPU profiles as a separate supplementary
cohort; do not treat them as interchangeable runs or discard them. Keep failed
capture files and record every failure. No capture gets a timing-driven retry.
Continue after isolated failures to retain other planned captures; stop after
three consecutive invalid captures. A missing capture disqualifies the complete
cohort and is never counted as passed.

The retained untraced measurements belong to the original host. Recovery traces
belong to a second host and include instrumentation overhead. Do not infer the
cause of the historical date flag from cross-host timing or compare instrumented
durations as ordinary latencies. CPU samples describe captured work; executor
events describe recorded state transitions, not every attempted hop. Retain unknown
symbols, all spread flags and source hashes. Adopt no production optimization from
these exploratory observations alone. Public APIs, cancellation checks, budgets,
fixtures, dependencies and published assets remain unchanged.
