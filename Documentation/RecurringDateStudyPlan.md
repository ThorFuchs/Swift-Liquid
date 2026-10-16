# Recurring date latency: frozen wall/CPU investigation

This is a diagnostic-only branch. Never merge its CI replacement or probe into
production. The product remains merged main e5291b040c046415f4b535903d23f56c49320c0e.
The preceding +12.005% and +11.9367% ordinary source date flags remain unresolved.
No production patch or performance improvement is assumed.

Hypothesis: caller scheduling can contribute to whole-call wall latency beyond
added process CPU work. Test directly against immutable 1.3.0
9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e, rather than multiplying the previous
study's separate phase ratios. Identical-source separately built main A/B controls
bound interpretation. Agreement is not proof of equivalence or historical cause.

Before timing, run main's Scripts/ci.py development lane (81 functions and 2,178
parameter cases), then build all six release binaries: three versions (1.3.0,
main A, identical main B), each with the unchanged pinned 1.3.0 common harness
and a new public-consumer probe. No builds between measurements. Keep every run,
raw sample, output checksum, command, failure, source inventory and review flag.
No timing-driven retries or dropped observations.

Three serial blocks, each in this fixed order: common release ABBA, common A/A
ABBA, explicit MainActor probe release ABBA, MainActor A/A ABBA, explicit
@concurrent probe release ABBA, concurrent A/A ABBA. Total 72 complete runs.
Common runs preserve all 26 original records and sampling policy. Probe runs
measure ISO timestamp, integer epoch bypassing string date parsing, and filter
chain control. Each has template construction plus source access, ordinary
source/reused renders, and metrics source/reused renders: 15 records per run.
All 25 measured samples, ten warmups, 100 repetitions/sample; output equality and
FNV1a verification stay within timing. Actor/concurrent bodies match except the
explicit executor annotation, returning Sendable Data across the boundary.

Probe samples retain wall and whole-process user+system CPU (getrusage RUSAGE_SELF).
CPU calls bracket wall timing, include their own overhead and work on all process
threads, and have microsecond accounting granularity. These are sample-loop CPU
observations, not exclusive engine CPU, thread residence, scheduler traces, RSS,
wall-minus-CPU wait estimates or per-check costs. Both clocks retain raw samples.
Do not numerically compare probe and unchanged-harness latencies as equal workloads.
The probe changes auditing and clock instrumentation; it supplements the original.

Report every >=10% aggregate median-change flag (both signs), every >=10% run-median
range flag, all three block effects, and date rows regardless of flags. No
confidence intervals or sample-independence claim. Inspect parse-only, integer
and ISO paths under both callers before attributing the observed release effect.
If clock deltas disagree beyond controls, that supports further scheduler tracing;
it does not alone establish executor hops as the root cause. If the recurring
flag does not reproduce, retain earlier observations and report attribution as
unresolved. Cancellation checks, budgets, public isolation, package dependencies,
fixtures and API baselines must remain byte-identical to merged main.
