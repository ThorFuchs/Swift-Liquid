# Controlled date-recognition CPU study

Freeze this protocol, bridge, consumer, input expectations and driver before any
hosted timing. PR #20 is merged as
`1ae8df16c6cc02caba75f83d6a46ea52f74a7d56`. Compare immutable 1.3.0
`9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e`, current A, and independently built
identical current B. Production core fingerprint remains
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.
No source optimization or cancellation change is proposed. Diagnostic branches
replace CI and must not be merged.

## Distinct binaries and boundaries

For each version build three release executables, all before timing: unchanged
1.3.0 common harness, byte-identical prior DateCPUProbe public consumer, and the
new synchronous component consumer. The first two link unmodified library sources.
The third links an isolated copy with exactly one added diagnostic bridge file.
Original library files stay byte-identical; retain both original and augmented
fingerprints. The bridge is not a production API. Its non-inlined methods return
checked-Sendable typed snapshots across a separate module boundary. Dynamic inputs
come from the frozen JSON file, preventing a constant-result benchmark.

The component consumer measures 29 explicit stage/input records:

- Five lowercasing, full recognition and matching date-snapshot audit controls.
- Four grammar construction/parse records and matching field-snapshot controls.
- Three known-date formatting records and matching output/step controls.

Inputs are the common fractional/offset ISO stamp, UTC ISO, RFC date, an invalid
string and a 129-byte length guard. The guard has no grammar/format record by
explicit shape; invalid recognition has no formatting record. Expectations are
fixed before timing; epoch values use independent Gregorian/offset arithmetic.
All outputs/fields, exact seven formatting steps and typed payload checksums are
audited. The local untimed preflight passed every record under both callers and
both orders. Hosted untimed admission repeats for all three binaries before timing.

Recognition receives the already-lowercased input and a fixed reference clock;
it includes the actual parseLiquidDate guards, grammar, defaults, offset/date
validation and cancellation checks, plus snapshot adaptation. Grammar includes
RubyDateParser initialization/normalization and parse plus its field adapter;
it has the helper's own cancellation behavior. Formatting includes date-value
validation and a fresh invocation-owned RuntimeBudget. Lowercasing is separate.
No checkpoint is removed or bypassed. An audit control returns the corresponding
expected typed value through a non-inlined method and uses identical checking and
hashing. These observations include adapters, calls, audits and loop/clock work.
Do not subtract controls as an exact cost, sum stages into render time, or treat
component module code layout as production code layout.

## Order and sampling

Use one hosted macOS 27 / Swift 6.4 runner, serially. Qualify unchanged main through
Scripts/ci.py development before modification; also qualify current A's augmented
library before creating its standalone component package. Retain raw test streams.
Build all nine binaries and all validation receipts before the first timing.
Use release and -Xswiftc -g consistently; retain commands, compiler, OS, hardware,
source inventories, input/probe/bridge hashes, binary hashes/UUIDs and symbols.

Three blocks retain the prior six phases in order: common release ABBA, common
identical ABBA, actor public release ABBA, actor public identical ABBA, concurrent
public release ABBA and concurrent public identical ABBA. Original common/public
policies remain ten warmups, 25 samples, 100 repetitions: 72 runs and 172 rows.
Each block then adds component release and identical ABBA under both callers;
block two reverses component caller phase order. Per component run the 29-record
order alternates forward/reverse by position, inverted in block two; every version
has one of each order per block. Component policy is ten warmups, 25 samples and
500 repetitions. That adds 48 runs, 1,392 raw records and 232 clock comparison rows.
Total: 120 runs, 2,736 raw records and 404 comparison rows. No timing-driven retry
or discarded run. Stop on a failed command/output admission and retain evidence.

Each sample externally brackets the synchronous batch with ContinuousClock and
getrusage(RUSAGE_SELF) user+system CPU. Components use explicit @MainActor and
@concurrent batch entry; synchronous bridge calls do not add a per-call async
boundary. Whole-process CPU has microsecond granularity and includes measurement
work and other process threads; it is not exclusive engine CPU. CPU minus wall
is not wait time. The prior public consumer still measures ordinary async entry,
metrics and parse controls separately. Caller phases are serial, not simultaneous.
Cold regex initialization occurs during warmups; no cold-start claim follows.

## Admission and interpretation

Independently recompute every sample summary, output payload/hash, six run medians,
block effect, MAD/range and both 10% median/spread flag lists. Preserve all flags,
including improvements and adverse controls. Component/production binaries and
caller contexts remain distinct. Do not multiply phase ratios or normalize by
identical-source results. Host isolation, contention, thermal state and frequency
are unknown. Zero CPU samples are retained and counted as accounting-resolution observations;
a positive median is required for a comparative ratio. Clock resolution and cheap
audit controls limit small-cost claims.
The study can isolate observed recognition work without identifying the cause of
historical +12% version flags. No release, speedup, equivalence, memory guarantee
or runtime adoption follows from mechanical success.

## Setup correction before timing

Attempt 38932664709 built the three baseline executables, then an assertion
incorrectly looked for the enum's source spelling in a Swift-mangled symbol table.
It stopped before any benchmark run or clock sample. Preserve its failed setup
and artifacts. Demangling the retained baseline table verifies all seven bridge
methods. Correct only that admission check to use swift-demangle and exact method
names, freeze again, and build/qualify all nine binaries on a fresh runner.
Inputs, bridge, consumer, clocks, ordering, sampling and interpretation stay fixed.
This correction selects no observed timing result.
