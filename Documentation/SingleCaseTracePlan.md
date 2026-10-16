# Single-case executor capture diagnostic

Freeze before compilation/capture. Hosted full-batch capture has exceeded its
watchdog on its first engine trace, despite successful standalone setup. Preserve
that failure and all original benchmark/CPU records. No benchmark is remeasured.

Build two private release/-g consumers from immutable 1.3.0 9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e
and merged main 1313f82ac03b6f51224d6c4219fc26ad0a598ddf, using the same Swift 6.4
compiler on this local shared macOS host. Verify each library source fingerprint.
Consumer coordination and the original per-call output equality/hash body stay
unchanged. Select only one ISO source or reuse batch per recording: 100 measured
calls after 10 warmups. Both binaries build before captures. This is a new,
explicitly narrower instrument cohort, not an ordinary latency comparison.

Fixed order actor/source v130,current; actor/reused current,v130;
concurrent/source v130,current; concurrent/reused current,v130 (eight captures).
Swift Concurrency template, attach owned target PID after ready, Darwin notify
start, 5-second record window, target alive until recorder saves, then normal
exit. Watchdog 90 seconds plus owned-child cleanup. No timing-driven retry; stop
after two invalid captures and retain all files. Admit only complete selected
signpost endpoints, expected output hash, actual target/record exit zero, PID,
nonempty executor running states and no drop/quarantine warning. Preserve raw
trace before symbolication/export, XML, symbols/UUIDs and unknown functions.

Report recorded executor identities and consecutive running-segment transitions
per task within the selected interval. Do not infer all attempted hops, per-check
cost, clock speed, a cross-version performance effect or the historical date cause.
Shared host load and instrumentation make elapsed values ineligible as benchmarks.
