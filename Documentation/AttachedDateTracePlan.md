# Coordinated attachment: recorder lifecycle experiment

Original study 38889400923 retains all 72 untraced runs and six admitted CPU
captures. The next recorder did not return for over thirteen minutes after its
target completed all six batches and wrote normal completion output. Retention
succeeded after cancellation. Hosted recovery 38894241807 then reproduced a
recorder stop problem in the standalone 100-call preflight: target completed,
recorder stayed at Stopping recording, watchdog returned 124 after 190 seconds.
No engine capture or benchmark measurement ran in that recovery.

These observations do not establish the recorder's internal cause. A standalone
local experiment instead attached to a coordinated live target, stopped recording
at the declared time limit, then released the target to exit normally. Recording
and target both exited zero and the trace saved. Freeze this lifecycle experiment
before applying it to the engine consumer. Keep all previous failures and partial
captures. No benchmark run is repeated or selected based on timings.

On a new hosted Swift 6.4 runner, download the original artifact, retain the six
complete and one incomplete captures separately, and recalibrate a 100-call
attached setup. Require the exact recorded 100 transitions in each direction.
Build three trace executables against the same immutable 1.3.0/current/identical
source versions, with the same release and -g flags. The private consumer adds
only ready/start/done/release coordination outside all signposted batches. Public
library sources and the actual actor/concurrent batch bodies stay unchanged.
Retain new probe bytes, executable/dSYM UUIDs, compiler and hardware separately.
These are new diagnostic binaries, not the original untraced executables.

Before each capture, start the target and wait for readiness. Register one Darwin
notification, attach Instruments to that owned PID, and start the workload only
after xctrace's tracing-start notification. Keep the target alive after it writes
complete results. Use declared recording windows of five seconds for the bounded
executor capture and twenty seconds for CPU sampling. After the recorder stops
and saves normally, release the target and require its normal zero exit. These
wall windows are recording coordination, not performance deadlines for Liquid.
A workload missing any complete signpost or output result is an invalid capture.

Collect the same complete 32-capture matrix, executor first then CPU, with the
original iterations, warmups, output audits and explicit callers. Bound commands
to 180 seconds with streaming logs and owned-process cleanup. Retain failures,
continue after an isolated invalid capture, stop after three consecutive failures,
and never count an incomplete matrix as passed. No timing-driven retries.

The original untraced measurements, original partial profiles and attached traces
are distinct host/cohort observations. Instrumentation and coordination add work.
Do not compare their elapsed times as ordinary latencies or claim the historical
date cause without a reproduced, localized effect. Preserve raw archives, XML,
unknown symbols, CPU sample coverage, source inventories and every review flag.
The core remains dependency-free and no cancellation, API, fixture or published
release asset changes are made.
