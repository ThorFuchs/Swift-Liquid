# Date CPU and executor tracing — frozen protocol

PR #18 passed all nine gates and its complete benchmark review, and merged as
`1313f82ac03b6f51224d6c4219fc26ad0a598ddf`. This protocol is frozen before engine observations.
The product library remains unchanged. No version publication is requested.

Question: can paired untraced CPU/wall observations and actual CPU stacks/task
executor events localize a repeatable cross-version date effect? Earlier roughly
12% ordinary-source flags remain unresolved. Quiet repetitions do not erase them.
If this experiment does not reproduce the date flag, profiles describe execution
on this host and do not establish the cause of those historical observations.

Before engine qualification or timing, run a standalone hosted 100-call capture
preflight. Require normal target completion, complete signpost scope, nonempty CPU
samples and the known 100 Main Actor/global transitions in each direction. A
failure here is a capture limitation and produces no new engine timings. Preserve
the setup source, logs and raw trace. These event counts calibrate this fixed
noinline setup function, not the Liquid renderer.

Compare immutable 1.3.0 (9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e) to main commit `1313f82ac03b6f51224d6c4219fc26ad0a598ddf`, with a separate identical main B build. Host Swift 6.4/macOS 27.
First qualify unchanged main through Scripts/ci.py development (81 functions,
2,178 parameter cases and public consumers/CLI). Preserve all raw test evidence.
All nine release binaries build before any timing: three library versions, each
with the unchanged pinned common 1.3.0 harness, the unchanged prior 15-record
wall/CPU public probe, and a new signposted trace probe. Apply identical -g flags
for useful symbols; retain exact flags, binary/dSYM UUIDs, source identities and
checksums. No assumption of binary equivalence with earlier studies follows.

Untraced phase: preserve 25 measured samples, ten warmups, 100 repetitions/sample
and output equality/FNV auditing. Three serial blocks each run common release
ABBA, common A/A ABBA, actor CPU-probe release ABBA, actor A/A ABBA, concurrent
CPU-probe release ABBA, concurrent A/A ABBA. Retain all 72 runs/172 comparisons,
all >=10% median changes in either direction, all >=10% run-median ranges and
all three block effects, even below thresholds. Both process CPU and wall samples
remain observations of the complete audited loop, not exclusive engine costs.

Then record a fixed trace matrix. For CPU then executor captures; for actor then
concurrent; for release then identical controls: one ABBA block. Total 32 traces,
16 per instrument setup. This is exploratory profiling, not a new latency verdict.

CPU uses Time Profiler plus Points of Interest, 20,000 measured renders and 100
warmups per batch. Executor uses Swift Concurrency, 100 renders and ten warmups.
Both probes cover ISO date, integer epoch and filter-chain source/reused calls:
six named signpost intervals per trace. Every output is checked byte-for-byte and
hashed; inspect target exit status, exact outputs and complete interval endpoints.
A standalone local setup probe showed that 10,000 dense async calls can trigger
logging quarantine; retain that failed setup and the successful bounded 100-call
setup. A later six-interval standalone setup exited normally but its recorder
failed to save the trace. Local free space then measured 2.4 GiB; causation is
unknown and this capture is not successful evidence. Require at least 6 GiB free
before hosted builds and 2 GiB before each capture. It is not engine data. Do not mix large CPU sampling and dense executor
logging in the same capture or treat instrumented latencies as ordinary renders.

Require normal target exit and six complete intervals, nonempty relevant tables,
no quarantine/dropped-event/overflow warning, and at least 50 active CPU samples
per ISO batch. Record unresolved self-frame weight and preserve unknown symbols.
Capture/export failures are limitations, never successful observations. Keep all
raw traces, table XML, recorder logs and source/binary identities. Symbolication
may improve an existing trace without re-recording; retain commands and failures.
No timing-driven retry, discarded adverse observation or checkpoint removal.

CPU analysis filters the target PID and signposted intervals, reports self-symbol
sample weights and separately labelled inclusive date-parser, formatter and
source-parser groups. Inclusive groups may overlap and are not an additive cost
model. Sampling weights are statistical observations; zero samples do not prove
zero cost. Executor analysis uses actual acquired/enqueued actor identities and
Running/Enqueued/Suspended events. Clip durations to intervals. Running interval
occupancy is not CPU time; consecutive recorded running-segment transitions are
not a count of every attempted hop. Report missing identities and unknown events.
Do not derive a per-cancellation-check cost or normalize by subtracting a constant.

Keep public execution semantics, cancellation points, budgets, dependency graph,
fixtures and API baseline unchanged. Adopt no runtime optimization without a
separate specific, compatibility-tested and controlled measurement case. Finish
with source-bound evidence and a focused reviewable report; release publication
and follow-up merging require separate maintainer requests.
