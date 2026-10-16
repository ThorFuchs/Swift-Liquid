# Recurring date latency: wall and CPU follow-up

The investigation does not yet identify the cause of the recurring date flag.
A direct 1.3.0-to-main study did not reproduce the roughly 12% ordinary-source
slowdown. Process CPU and wall observations also do not support a waiting-only
explanation for the large caller-context difference on this runner. The production
engine remains unchanged; cancellation checks and released contracts are retained.

## Source and retained evidence

PR #17 merged as `e5291b040c046415f4b535903d23f56c49320c0e`.
The immutable baseline is 1.3.0 commit
`9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e`.
Both independent main builds have library fingerprint
`6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a`.
`DateParsing.swift`, `RubyDateParser.swift`, `DateFormatting.swift` and
`Renderer+FilterHelpers.swift` are byte-identical from that baseline to main.
This does not establish equal performance: other runtime code and compiled code
layout can affect a complete operation.

The [frozen plan](https://github.com/ThorFuchs/Swift-Liquid/blob/4ea222ca2079adf0d244450d49812c760ef91d12/Documentation/RecurringDateStudyPlan.md),
[driver](https://github.com/ThorFuchs/Swift-Liquid/blob/4ea222ca2079adf0d244450d49812c760ef91d12/Scripts/hosted_recurring_date_study.py)
and [probe](https://github.com/ThorFuchs/Swift-Liquid/blob/4ea222ca2079adf0d244450d49812c760ef91d12/Tools/DateCPUStudy/DateCPUProbe.swift)
precede timing. Their diagnostic branch must not be merged: it replaces the
workflow solely for this experiment. The
[successful study run](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38881324575)
retains `liquid-recurring-date-study`, including every raw observation, command,
source inventory, build log and development test stream. Actions artifacts have
30-day retention; download them while available. The source protocol and full
aggregate table below remain committed.

`recurring-date-study.json` SHA-256:
`31ef668a326cb8278e5fa1ef138068f39cbe32562b61a8cc9d769df5dea1fbdb`.
Independent recomputation verified all 72 runs, 1,344 raw records, 172 comparison
rows, output byte lengths and literal expected-payload FNV1a checksums, both clock
sample summaries, block effects, source fingerprints and every review flag.
No timing-driven retry or discarded observation was used.

## Measurement boundaries

First, unchanged main passed `Scripts/ci.py --lane development`: 81 test functions,
2,178 parameter cases, public consumers and CLI behavior. All six release binaries
built before timing: 1.3.0, main A and separately built identical main B, each with
the unchanged 1.3.0 common harness and the new probe. The common harness SHA-256
remains `2aed7fe384085e4b4b5ba26dcb2545f4006248822b21a864ef515cc51d3c985f`;
its manifest remains `aaf1bad0e6c4c7165b35320bf95878a2a3ac20a5efa9362066901ac9836b4439`.

Three serial blocks each run common release ABBA, common identical-source ABBA,
actor release ABBA, actor identical-source ABBA, concurrent release ABBA, then
concurrent identical-source ABBA. Each comparison has six runs per side. Every
record retains ten warmups, 25 measured samples and 100 repetitions per sample.
The common phase preserves all 26 original workloads and modes. This is a direct
1.3.0-to-main comparison; the prior study's phase ratios are not multiplied.

The public-consumer probe has equal bodies under explicit `@MainActor` and
`@concurrent` annotations, returning checked-Sendable `Data`. It covers the ISO
stamp and format from the common harness, integer epoch zero with the same format,
and the standard filter-chain control. Each measures template construction plus
source access, ordinary source/reused rendering and metrics source/reused rendering.
The integer path bypasses string date parsing; template construction does not
execute a date filter. These are controls, not an additive decomposition of render
cost. Output equality and hashing remain inside each timed loop.

Each probe sample brackets wall timing with `getrusage(RUSAGE_SELF)` user plus
system CPU accounting. [Apple documents those fields](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getrusage.2.html)
as process utilization. Here CPU covers all process threads and measurement
boundaries, with microsecond accounting granularity and call overhead. It is not
exclusive engine CPU, thread residence or an executor trace. CPU and wall medians
can cross because their samples and boundaries differ. Subtracting them is not a
wait-time estimate. The probe changes auditing and adds clock calls; do not
numerically equate its latencies with the unchanged common harness.

The runner reported Swift 6.4 (`swiftlang-6.4.0.34.1`), macOS 27, three virtual
Apple M1 CPUs and 7 GiB memory. One-minute guest load ranged from 1.229 to 1.828.
Physical-host contention, thermal state and frequency isolation are unknown.
Run-median ranges and MAD describe retained observations; they are not confidence
intervals or proof of independent samples. There is no process-memory claim.

## Results and decisions

The common date source median moved 50.112 to 48.987 microseconds (-2.245%), with
block effects +0.354/-9.189/-4.216%. Reused ordinary date moved -0.418%; source and
reused metrics moved +1.366/+1.519%. All four common date records have mixed block
signs. No date median-review flag appears under either caller or either clock.
These observations do not establish a speedup or equivalent performance.

The ISO probe's ordinary source changes were -4.832% wall/-3.566% CPU under the
actor caller, and +1.520% wall/+1.499% CPU under the concurrent caller. Ordinary
reuse changed -0.484/-0.328% and -0.546/-0.569%, respectively. Concurrent source
ISO changed about as much as its identical-source control (+1.410% wall/+1.460%
CPU). Template construction also has no median-review flag. The data do not
localize a recurring ISO-string parser or template-construction regression.

For main A in the release probe, actor ISO ordinary reuse observed 45.515
microseconds wall and 45.535 CPU; concurrent reuse observed 21.821 wall and 21.830
CPU. Caller sensitivity is present on both clocks, rather than a large wall-only
gap. This rejects a waiting-only account of these probe observations. It does not
attribute CPU to executor hops, identify the historical +12% cause, or provide a
normalization constant to subtract from a render. Both versions have this caller
sensitivity, and caller phases run serially rather than simultaneously.

Retain the adverse control result: concurrent filter-chain ordinary reuse rose
3.423 to 3.777 microseconds wall (+10.341%), and 3.430 to 3.780 CPU (+10.204%). All
three blocks are positive on both clocks (+9.116/+14.546/+7.157% wall and
+9.065/+14.431/+7.289% CPU). Identical-source effects are -0.254/-0.132% with mixed
block signs. This is a corroborated observation in this experiment, not a date
parser diagnosis. Epoch ordinary rendering also rose below the flag threshold:
source +7.192% wall/+7.245% CPU and reuse +7.001/+7.087%, all blocks positive.
The release comparison includes required cancellation changes and other runtime
work; it does not isolate a per-check cost. No cancellation check is removed.

Only those two filter-control clock rows trigger median review. All spread flags
are retained in the complete table below: 23 common release, 24 common identical,
23 actor release, 20 actor identical, 26 concurrent release and two concurrent
identical. There are no median flags in the other five phases. Large spread remains
material even where aggregate medians agree. Review both sides' ranges and every
block; neither a faster median nor a quiet control clears a historical flag.

The [fresh post-merge main comparison](https://github.com/ThorFuchs/Swift-Liquid/actions/runs/38880929675)
separately observed date ordinary source +0.417%, measured source +0.351%, ordinary
reuse +0.524% and measured reuse +0.678%, with mixed block signs. Its comparison
SHA-256 is `822f17605a39e32f65452f6b89ba07fe70802e3700e619d9bf53b9a790f26d23`.
All 50 common/metrics rows were recomputed and reviewed. Its one median flag,
custom-filter ordinary reuse -11.018%, has mixed blocks +4.285/-15.129/-6.931%;
it is not a reliable speedup claim. All 24 common and 23 metrics spread flags remain
retained. This main run does not replace the earlier observations.

The earlier PR #16 +12.005% and PR #17 +11.9367% date source flags remain
unresolved, including their all-positive blocks. This follow-up rules out neither
an intermittent version effect nor host/compiler/runtime interactions. It supplies
no production optimization and no release performance clearance. A causal next
experiment needs a reproduced date flag with paired CPU observations and retained
CPU/executor tracing, rather than another formatter rewrite or fewer checkpoints.
The root manifest, fixtures, API baseline, isolation and invocation-owned state
remain unchanged; final candidate qualification applies to its exact source tree.

## Complete aggregate observations

Positive change means higher time. Medians are microseconds; changes, three block
effects and two run-median ranges are percentages. `M` marks absolute median change
at least 10%; `S` marks either range at least 10%. A dash means no flag, not proof
of no regression. Release phases compare 1.3.0 to main A; identical phases compare
main A to main B. CPU and wall are distinct records. Values below are rounded;
raw artifacts retain all sample and summary precision.

### release-common

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| custom-filter/parse-and-render | 25.743 | 25.866 | +0.477 | +2.436/-1.768/+4.699 | 22.205/7.724 | S |
| custom-filter/parse-and-render-metrics | 27.236 | 27.090 | -0.534 | -1.495/-4.838/+1.263 | 14.286/5.614 | S |
| custom-filter/reused-template | 20.413 | 20.427 | +0.068 | -5.177/-0.355/-2.927 | 14.447/11.837 | S |
| custom-filter/reused-template-metrics | 20.800 | 21.194 | +1.891 | +3.392/-1.798/-0.086 | 13.273/8.068 | S |
| date/parse-and-render | 50.112 | 48.987 | -2.245 | +0.354/-9.189/-4.216 | 15.557/14.722 | S |
| date/parse-and-render-metrics | 50.193 | 50.879 | +1.366 | +2.872/-0.225/-5.527 | 14.121/17.276 | S |
| date/reused-template | 44.824 | 44.637 | -0.418 | +4.342/-6.278/-3.095 | 13.717/14.474 | S |
| date/reused-template-metrics | 45.647 | 46.340 | +1.519 | -0.994/-4.960/+2.210 | 17.934/10.284 | S |
| filter-chain/parse-and-render | 23.541 | 23.438 | -0.435 | +2.114/-3.262/+4.373 | 18.916/6.521 | S |
| filter-chain/parse-and-render-metrics | 23.378 | 24.081 | +3.008 | -1.265/-2.707/-1.999 | 23.657/13.062 | S |
| filter-chain/reused-template | 20.034 | 19.645 | -1.943 | +0.122/+1.843/-2.387 | 8.972/8.611 | — |
| filter-chain/reused-template-metrics | 19.840 | 19.744 | -0.482 | -2.257/-2.233/-0.144 | 5.517/1.429 | — |
| inspection/inspect-reused-template | 6.934 | 6.838 | -1.388 | -4.034/+3.935/+0.452 | 5.168/11.139 | S |
| inspection/parse-and-inspect | 17.551 | 17.486 | -0.366 | -5.868/+4.731/+3.339 | 13.990/10.975 | S |
| interpolation/parse-and-render | 20.181 | 20.244 | +0.313 | +1.357/-3.203/+0.931 | 15.582/9.960 | S |
| interpolation/parse-and-render-metrics | 21.130 | 21.190 | +0.284 | +0.144/-8.618/+0.297 | 21.692/11.086 | S |
| interpolation/reused-template | 19.527 | 18.404 | -5.750 | -7.835/+0.238/-14.725 | 41.767/20.502 | S |
| interpolation/reused-template-metrics | 20.582 | 21.029 | +2.171 | +6.859/+5.941/-0.338 | 25.825/34.672 | S |
| loop/parse-and-render | 42.719 | 41.907 | -1.900 | -2.031/-5.461/+2.443 | 14.814/11.633 | S |
| loop/parse-and-render-metrics | 42.950 | 43.317 | +0.854 | -0.176/-0.221/+4.329 | 14.534/8.179 | S |
| loop/reused-template | 35.309 | 35.105 | -0.578 | +3.721/-8.145/+1.955 | 14.498/14.260 | S |
| loop/reused-template-metrics | 35.820 | 35.498 | -0.898 | -3.165/-2.826/+1.892 | 12.376/5.426 | S |
| partial/parse-and-render | 28.292 | 28.452 | +0.563 | -1.778/+1.052/+0.482 | 11.676/7.633 | S |
| partial/parse-and-render-metrics | 28.678 | 29.383 | +2.458 | +2.673/-1.325/+3.336 | 11.039/6.340 | S |
| partial/reused-template | 21.185 | 21.937 | +3.549 | +0.458/+2.941/+2.739 | 9.503/9.366 | — |
| partial/reused-template-metrics | 21.780 | 21.718 | -0.285 | -4.538/-1.287/+2.073 | 12.127/11.012 | S |

### identical-common

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| custom-filter/parse-and-render | 26.126 | 26.775 | +2.484 | +3.797/-0.087/-1.271 | 14.215/14.860 | S |
| custom-filter/parse-and-render-metrics | 27.572 | 27.713 | +0.513 | +0.513/-0.569/-5.331 | 14.731/19.039 | S |
| custom-filter/reused-template | 20.992 | 19.906 | -5.170 | -6.429/-3.894/-1.948 | 10.165/12.071 | S |
| custom-filter/reused-template-metrics | 21.502 | 21.121 | -1.773 | -0.273/-4.008/-0.308 | 12.931/10.651 | S |
| date/parse-and-render | 49.981 | 49.939 | -0.084 | -0.084/+1.072/-0.198 | 19.651/20.035 | S |
| date/parse-and-render-metrics | 51.406 | 51.021 | -0.749 | -0.749/-1.251/-1.755 | 20.209/20.971 | S |
| date/reused-template | 46.396 | 46.584 | +0.404 | +0.404/-0.213/+2.308 | 20.302/17.877 | S |
| date/reused-template-metrics | 46.736 | 46.718 | -0.040 | -0.040/-2.358/+1.309 | 20.956/19.118 | S |
| filter-chain/parse-and-render | 24.582 | 23.678 | -3.677 | -3.677/+0.764/-0.588 | 17.564/15.982 | S |
| filter-chain/parse-and-render-metrics | 24.158 | 24.914 | +3.130 | +4.767/+3.584/-5.893 | 16.208/28.762 | S |
| filter-chain/reused-template | 19.657 | 20.033 | +1.912 | +4.581/+3.690/-0.244 | 10.196/3.869 | S |
| filter-chain/reused-template-metrics | 19.692 | 20.085 | +1.996 | +2.108/+1.293/+0.199 | 6.635/8.856 | — |
| inspection/inspect-reused-template | 6.862 | 6.866 | +0.055 | -0.446/+1.509/-3.553 | 7.244/8.612 | — |
| inspection/parse-and-inspect | 17.766 | 17.521 | -1.377 | -1.198/+3.293/-0.152 | 10.047/9.795 | S |
| interpolation/parse-and-render | 20.179 | 20.652 | +2.343 | +3.119/-5.494/+0.212 | 18.121/11.159 | S |
| interpolation/parse-and-render-metrics | 20.945 | 21.136 | +0.914 | +2.668/-3.699/-0.277 | 14.900/14.631 | S |
| interpolation/reused-template | 18.218 | 19.359 | +6.262 | +15.969/-3.449/-0.240 | 20.612/30.126 | S |
| interpolation/reused-template-metrics | 19.103 | 19.692 | +3.084 | +7.224/+1.008/+1.556 | 27.648/23.273 | S |
| loop/parse-and-render | 44.180 | 43.874 | -0.694 | -1.153/-0.124/-3.637 | 13.049/12.549 | S |
| loop/parse-and-render-metrics | 43.960 | 43.547 | -0.938 | -0.507/+0.708/-4.068 | 12.626/16.382 | S |
| loop/reused-template | 36.434 | 35.996 | -1.200 | +0.126/+1.744/-6.067 | 10.736/16.938 | S |
| loop/reused-template-metrics | 36.349 | 36.637 | +0.792 | +1.568/-1.867/-4.074 | 15.239/11.911 | S |
| partial/parse-and-render | 28.823 | 29.102 | +0.969 | +0.969/-0.475/-3.974 | 13.080/18.238 | S |
| partial/parse-and-render-metrics | 31.144 | 29.473 | -5.365 | -1.848/-1.012/-5.341 | 17.371/15.545 | S |
| partial/reused-template | 22.232 | 22.321 | +0.398 | +0.398/+1.104/-2.414 | 14.330/18.374 | S |
| partial/reused-template-metrics | 22.509 | 21.902 | -2.696 | -2.696/+0.594/+4.228 | 22.348/15.040 | S |

### release-actor

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| epoch/parse-cpu | 2.350 | 2.370 | +0.851 | -0.417/-1.461/+1.720 | 5.532/2.532 | — |
| epoch/parse-wall | 2.347 | 2.366 | +0.817 | -0.313/-1.687/+1.733 | 5.556/2.852 | — |
| epoch/reused-cpu | 21.305 | 21.815 | +2.394 | +3.159/+2.966/+1.056 | 12.110/7.655 | S |
| epoch/reused-metrics-cpu | 21.640 | 21.630 | -0.046 | +2.813/+1.296/-0.762 | 16.959/9.524 | S |
| epoch/reused-metrics-wall | 21.579 | 21.586 | +0.032 | +2.072/+1.451/-0.745 | 16.540/9.481 | S |
| epoch/reused-wall | 21.276 | 21.800 | +2.463 | +3.045/+2.539/+0.984 | 10.174/8.075 | S |
| epoch/source-cpu | 23.900 | 25.345 | +6.046 | +5.184/+1.416/+5.846 | 20.084/11.639 | S |
| epoch/source-metrics-cpu | 25.785 | 25.715 | -0.271 | +0.666/-2.911/+1.167 | 17.297/10.305 | S |
| epoch/source-metrics-wall | 26.061 | 25.695 | -1.407 | -0.261/-3.551/+1.153 | 16.204/10.112 | S |
| epoch/source-wall | 24.116 | 25.312 | +4.958 | +3.771/+0.656/+5.559 | 19.353/11.200 | S |
| filter/parse-cpu | 2.655 | 2.635 | -0.753 | -2.399/+2.439/+0.384 | 4.896/9.108 | — |
| filter/parse-wall | 2.648 | 2.632 | -0.582 | -2.151/+2.104/+0.472 | 4.910/8.326 | — |
| filter/reused-cpu | 20.360 | 20.025 | -1.645 | +5.697/-2.332/-1.089 | 12.967/2.797 | S |
| filter/reused-metrics-cpu | 20.225 | 19.925 | -1.483 | +5.511/-0.672/-4.425 | 11.718/9.285 | S |
| filter/reused-metrics-wall | 20.137 | 19.836 | -1.494 | +4.160/-0.445/-4.412 | 9.257/9.347 | — |
| filter/reused-wall | 20.172 | 19.913 | -1.289 | +5.023/-1.855/-0.758 | 11.495/3.235 | S |
| filter/source-cpu | 22.260 | 23.735 | +6.626 | +6.529/+1.302/+7.027 | 18.733/8.258 | S |
| filter/source-metrics-cpu | 23.520 | 24.630 | +4.719 | +4.609/+3.203/+0.066 | 6.378/10.759 | S |
| filter/source-metrics-wall | 23.813 | 24.580 | +3.225 | +2.897/+3.094/+0.120 | 6.259/10.596 | S |
| filter/source-wall | 22.512 | 23.724 | +5.383 | +5.394/+1.396/+6.946 | 18.128/8.118 | S |
| iso/parse-cpu | 2.625 | 2.610 | -0.571 | +0.760/-0.571/-5.166 | 6.857/3.065 | — |
| iso/parse-wall | 2.629 | 2.604 | -0.935 | +0.245/-0.429/-5.598 | 7.211/3.248 | — |
| iso/reused-cpu | 45.685 | 45.535 | -0.328 | +0.872/-4.325/-5.972 | 17.577/12.979 | S |
| iso/reused-metrics-cpu | 46.725 | 45.455 | -2.718 | -2.847/-2.721/-1.060 | 19.283/16.324 | S |
| iso/reused-metrics-wall | 46.996 | 45.392 | -3.413 | -3.545/-3.212/-1.025 | 18.436/15.912 | S |
| iso/reused-wall | 45.737 | 45.515 | -0.484 | +1.055/-4.602/-6.789 | 16.579/12.849 | S |
| iso/source-cpu | 50.475 | 48.675 | -3.566 | -1.041/-8.385/-5.406 | 19.574/11.505 | S |
| iso/source-metrics-cpu | 51.775 | 50.040 | -3.351 | -2.317/-4.741/-2.867 | 21.902/16.387 | S |
| iso/source-metrics-wall | 52.007 | 50.051 | -3.761 | -2.627/-5.124/-3.650 | 20.956/15.746 | S |
| iso/source-wall | 51.045 | 48.578 | -4.832 | -0.800/-9.079/-6.148 | 18.547/11.991 | S |

### identical-actor

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| epoch/parse-cpu | 2.360 | 2.355 | -0.212 | -0.421/-0.849/-0.422 | 8.475/2.123 | — |
| epoch/parse-wall | 2.359 | 2.350 | -0.354 | -0.720/-0.770/-0.167 | 8.109/2.003 | — |
| epoch/reused-cpu | 21.865 | 21.660 | -0.938 | +3.471/-2.805/-1.080 | 10.153/8.587 | S |
| epoch/reused-metrics-cpu | 22.255 | 22.620 | +1.640 | +2.778/-1.802/+1.881 | 12.087/9.726 | S |
| epoch/reused-metrics-wall | 22.447 | 22.587 | +0.625 | +1.794/-1.864/+0.852 | 11.716/9.653 | S |
| epoch/reused-wall | 21.833 | 21.601 | -1.062 | +2.580/-2.835/-1.958 | 8.677/8.379 | — |
| epoch/source-cpu | 24.750 | 24.420 | -1.333 | +1.682/-0.245/-1.715 | 9.333/9.746 | — |
| epoch/source-metrics-cpu | 25.915 | 26.010 | +0.367 | +4.619/-2.530/-6.073 | 9.107/19.454 | S |
| epoch/source-metrics-wall | 26.104 | 25.972 | -0.505 | +3.615/-2.410/-6.928 | 8.758/19.107 | S |
| epoch/source-wall | 25.079 | 24.379 | -2.791 | +0.205/-0.366/-2.850 | 9.070/9.286 | — |
| filter/parse-cpu | 2.650 | 2.630 | -0.755 | -1.473/-0.756/-3.670 | 11.698/3.802 | S |
| filter/parse-wall | 2.645 | 2.626 | -0.725 | -1.393/-0.843/-3.700 | 11.484/3.777 | S |
| filter/reused-cpu | 19.930 | 20.020 | +0.452 | +5.221/-0.917/+0.942 | 10.637/3.696 | S |
| filter/reused-metrics-cpu | 20.030 | 20.105 | +0.374 | +4.027/+0.125/+0.677 | 5.891/4.626 | — |
| filter/reused-metrics-wall | 20.078 | 20.081 | +0.016 | +2.213/+0.016/-0.488 | 5.207/4.911 | — |
| filter/reused-wall | 19.967 | 19.936 | -0.154 | +3.953/-1.001/-0.381 | 8.255/3.944 | — |
| filter/source-cpu | 23.145 | 22.885 | -1.123 | +0.919/-3.808/-0.835 | 13.005/4.501 | S |
| filter/source-metrics-cpu | 24.275 | 24.145 | -0.536 | -1.140/+0.021/-4.262 | 7.786/13.170 | S |
| filter/source-metrics-wall | 24.236 | 24.130 | -0.435 | -1.550/+0.028/-4.799 | 8.025/13.004 | S |
| filter/source-wall | 23.300 | 22.934 | -1.570 | +0.026/-2.866/-1.529 | 10.611/4.738 | S |
| iso/parse-cpu | 2.580 | 2.625 | +1.744 | -0.190/+0.962/+2.335 | 6.589/1.143 | — |
| iso/parse-wall | 2.577 | 2.629 | +1.997 | +0.254/+1.060/+2.451 | 6.386/1.268 | — |
| iso/reused-cpu | 45.680 | 45.525 | -0.339 | +0.522/-0.339/+2.192 | 12.785/10.873 | S |
| iso/reused-metrics-cpu | 45.690 | 46.205 | +1.127 | -1.537/+2.035/+0.071 | 12.694/11.211 | S |
| iso/reused-metrics-wall | 45.612 | 46.154 | +1.188 | -1.429/+2.057/+0.113 | 12.598/11.074 | S |
| iso/reused-wall | 45.558 | 45.443 | -0.254 | +0.322/-0.254/+2.101 | 12.814/10.898 | S |
| iso/source-cpu | 49.745 | 50.250 | +1.015 | +2.979/+0.671/-1.301 | 9.468/13.831 | S |
| iso/source-metrics-cpu | 49.350 | 49.765 | +0.841 | +0.195/+0.222/-0.930 | 14.022/11.494 | S |
| iso/source-metrics-wall | 49.312 | 49.760 | +0.910 | +0.239/+0.274/-0.855 | 13.781/11.297 | S |
| iso/source-wall | 49.535 | 50.208 | +1.358 | +2.828/+0.920/-1.307 | 9.577/13.744 | S |

### release-concurrent

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| epoch/parse-cpu | 2.265 | 2.300 | +1.545 | +3.974/-3.758/+1.325 | 11.921/6.522 | S |
| epoch/parse-wall | 2.261 | 2.295 | +1.511 | +3.930/-3.657/+1.355 | 11.685/6.336 | S |
| epoch/reused-cpu | 4.515 | 4.835 | +7.087 | +4.090/+8.719/+7.859 | 12.625/8.480 | S |
| epoch/reused-metrics-cpu | 4.820 | 5.100 | +5.809 | +2.530/+9.908/+4.531 | 8.921/10.000 | S |
| epoch/reused-metrics-wall | 4.814 | 5.094 | +5.821 | +2.508/+7.403/+4.553 | 13.477/9.938 | S |
| epoch/reused-wall | 4.514 | 4.830 | +7.001 | +4.073/+8.531/+7.921 | 12.794/8.437 | S |
| epoch/source-cpu | 6.970 | 7.475 | +7.245 | +6.254/+9.474/+5.612 | 8.465/8.294 | — |
| epoch/source-metrics-cpu | 7.425 | 7.845 | +5.657 | +5.657/+8.593/+4.390 | 9.966/8.540 | — |
| epoch/source-metrics-wall | 7.425 | 7.841 | +5.606 | +5.606/+8.697/+4.435 | 9.927/8.593 | — |
| epoch/source-wall | 6.970 | 7.471 | +7.192 | +6.292/+9.435/+5.625 | 8.447/8.226 | — |
| filter/parse-cpu | 2.540 | 2.570 | +1.181 | +0.394/+10.742/+0.787 | 1.969/14.397 | S |
| filter/parse-wall | 2.536 | 2.568 | +1.281 | +0.501/+11.712/+0.912 | 2.087/16.207 | S |
| filter/reused-cpu | 3.430 | 3.780 | +10.204 | +9.065/+14.431/+7.289 | 3.790/11.640 | MS |
| filter/reused-metrics-cpu | 3.600 | 3.930 | +9.167 | +9.865/+13.592/+8.287 | 7.778/11.705 | S |
| filter/reused-metrics-wall | 3.599 | 3.932 | +9.263 | +9.720/+13.376/+8.071 | 7.804/11.466 | S |
| filter/reused-wall | 3.423 | 3.777 | +10.341 | +9.116/+14.546/+7.157 | 3.798/11.672 | MS |
| filter/source-cpu | 6.085 | 6.385 | +4.930 | +3.234/+9.407/+3.480 | 11.011/13.939 | S |
| filter/source-metrics-cpu | 6.315 | 6.855 | +8.551 | +6.240/+11.842/+5.463 | 7.284/11.233 | S |
| filter/source-metrics-wall | 6.310 | 6.848 | +8.535 | +6.247/+11.882/+5.551 | 7.284/11.359 | S |
| filter/source-wall | 6.077 | 6.382 | +5.012 | +3.403/+9.547/+3.434 | 10.998/14.005 | S |
| iso/parse-cpu | 2.635 | 2.645 | +0.380 | -3.461/-4.270/-2.490 | 15.180/7.561 | S |
| iso/parse-wall | 2.632 | 2.642 | +0.364 | -3.487/-5.157/-2.393 | 17.094/7.412 | S |
| iso/reused-cpu | 21.955 | 21.830 | -0.569 | -2.611/+2.495/+0.677 | 11.660/12.552 | S |
| iso/reused-metrics-cpu | 22.225 | 23.325 | +4.949 | +1.523/-5.515/+3.533 | 42.520/13.548 | S |
| iso/reused-metrics-wall | 22.221 | 23.320 | +4.943 | +1.521/-5.715/+3.533 | 43.558/14.087 | S |
| iso/reused-wall | 21.941 | 21.821 | -0.546 | -2.568/+2.604/+0.697 | 12.351/13.477 | S |
| iso/source-cpu | 25.025 | 25.400 | +1.499 | -0.134/+0.293/+1.975 | 10.789/6.535 | S |
| iso/source-metrics-cpu | 25.505 | 26.595 | +4.274 | +1.721/+4.809/-0.101 | 12.194/14.063 | S |
| iso/source-metrics-wall | 25.499 | 26.591 | +4.284 | +1.708/+4.947/-0.090 | 12.197/14.330 | S |
| iso/source-wall | 25.016 | 25.396 | +1.520 | -0.146/+0.323/+1.953 | 10.735/6.538 | S |

### identical-concurrent

| Record | First µs | Second µs | Change % | Blocks % | Ranges % | Flags |
| --- | ---: | ---: | ---: | --- | --- | --- |
| epoch/parse-cpu | 2.285 | 2.265 | -0.875 | +0.661/+0.000/-0.875 | 1.313/3.974 | — |
| epoch/parse-wall | 2.280 | 2.262 | -0.822 | +0.884/+0.264/-0.950 | 1.279/4.256 | — |
| epoch/reused-cpu | 4.700 | 4.715 | +0.319 | -0.318/+2.769/+0.532 | 1.489/6.151 | — |
| epoch/reused-metrics-cpu | 4.910 | 4.950 | +0.815 | -1.195/+4.903/+0.712 | 5.092/9.293 | — |
| epoch/reused-metrics-wall | 4.907 | 4.946 | +0.790 | -1.323/+4.940/+0.619 | 5.264/9.317 | — |
| epoch/reused-wall | 4.701 | 4.714 | +0.270 | -0.402/+2.623/+0.590 | 1.595/5.922 | — |
| epoch/source-cpu | 7.190 | 7.125 | -0.904 | +0.418/+0.209/-1.247 | 1.113/4.632 | — |
| epoch/source-metrics-cpu | 7.445 | 7.460 | +0.201 | -2.827/+2.761/+2.451 | 6.447/6.166 | — |
| epoch/source-metrics-wall | 7.439 | 7.457 | +0.252 | -2.840/+2.788/+2.387 | 6.402/6.146 | — |
| epoch/source-wall | 7.190 | 7.119 | -0.979 | +0.398/+0.154/-1.263 | 1.043/4.624 | — |
| filter/parse-cpu | 2.550 | 2.585 | +1.373 | +2.549/+1.566/-0.778 | 1.569/3.868 | — |
| filter/parse-wall | 2.550 | 2.585 | +1.381 | +2.460/+1.534/-0.625 | 1.340/3.804 | — |
| filter/reused-cpu | 3.775 | 3.770 | -0.132 | -0.131/+1.065/-2.258 | 3.444/7.692 | — |
| filter/reused-metrics-cpu | 3.885 | 3.905 | +0.515 | -0.384/+3.364/+0.000 | 2.317/6.658 | — |
| filter/reused-metrics-wall | 3.879 | 3.895 | +0.408 | -0.432/+3.356/-0.081 | 2.492/6.590 | — |
| filter/reused-wall | 3.777 | 3.767 | -0.254 | -0.229/+1.105/-2.149 | 3.498/7.731 | — |
| filter/source-cpu | 6.370 | 6.495 | +1.962 | +0.915/+3.718/-1.022 | 4.553/7.236 | — |
| filter/source-metrics-cpu | 6.615 | 6.745 | +1.965 | -1.081/+3.506/-1.587 | 7.105/9.192 | — |
| filter/source-metrics-wall | 6.614 | 6.740 | +1.909 | -1.020/+3.364/-1.632 | 7.068/9.025 | — |
| filter/source-wall | 6.365 | 6.487 | +1.921 | +1.044/+3.692/-1.092 | 4.491/7.264 | — |
| iso/parse-cpu | 2.635 | 2.630 | -0.190 | -1.323/+5.545/+1.938 | 4.554/8.745 | — |
| iso/parse-wall | 2.632 | 2.629 | -0.095 | -1.716/+5.598/+2.112 | 4.608/8.716 | — |
| iso/reused-cpu | 21.670 | 22.035 | +1.684 | -1.719/+2.569/-0.369 | 6.645/6.762 | — |
| iso/reused-metrics-cpu | 21.985 | 22.565 | +2.638 | +0.366/+1.754/+1.197 | 8.051/8.287 | — |
| iso/reused-metrics-wall | 21.978 | 22.572 | +2.704 | +0.361/+1.803/+1.223 | 8.040/8.262 | — |
| iso/reused-wall | 21.663 | 22.029 | +1.691 | -1.724/+2.533/-0.334 | 6.707/6.698 | — |
| iso/source-cpu | 24.655 | 25.015 | +1.460 | -2.099/+8.162/+1.238 | 5.962/7.036 | — |
| iso/source-metrics-cpu | 25.050 | 25.685 | +2.535 | -1.015/+4.029/-0.599 | 7.784/11.446 | S |
| iso/source-metrics-wall | 25.043 | 25.678 | +2.536 | -1.011/+5.058/-0.605 | 7.777/13.368 | S |
| iso/source-wall | 24.657 | 25.005 | +1.410 | -2.096/+8.147/+1.241 | 5.964/7.009 | — |
