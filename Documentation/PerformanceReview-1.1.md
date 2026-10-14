# Swift-Liquid 1.1 benchmark review

The initial matched comparison used the pinned 1.0.0 harness on an Apple M1 Max,
macOS 27.0, Swift 6.4 (`swiftlang-6.4.0.34.1`). It ran three ABBA blocks, six
runs per version, after both release binaries were built. Both versions produced
identical output checksums under the original sampling policy.

The measured Liquid library source fingerprint is `abd59342ca315fd45ff4ca747cd8d1334cc805fed9d44dd25c667c21583b0f5c`.
This fingerprint covers sorted relative Swift source paths and their SHA-256
digests, as implemented in `Scripts/compare_benchmarks.py`. Documentation, CLI
version metadata and consumer examples do not alter this library measurement.

| Workload | Mode | 1.0.0 µs | 1.1 candidate µs | Change |
| --- | --- | ---: | ---: | ---: |
| date | parse-and-render | 39.52 | 38.91 | -1.5% |
| date | reused-template | 35.09 | 35.97 | +2.5% |
| filter-chain | parse-and-render | 16.95 | 16.69 | -1.5% |
| filter-chain | reused-template | 14.28 | 12.40 | -13.1% |
| interpolation | parse-and-render | 15.73 | 14.35 | -8.8% |
| interpolation | reused-template | 12.23 | 11.44 | -6.5% |
| loop | parse-and-render | 35.13 | 35.59 | +1.3% |
| loop | reused-template | 28.28 | 28.72 | +1.5% |
| partial | parse-and-render | 20.57 | 21.02 | +2.2% |
| partial | reused-template | 15.51 | 14.76 | -4.8% |

Values are medians of run medians; positive change is slower. No slowdown crosses
the 10% review threshold. The reused filter chain crosses it in the faster direction
(-13.1%). That result is reviewed as inconclusive for a speedup: baseline run
medians span 11.8–15.4 µs and candidate medians span 12.0–14.2 µs. They overlap,
the host load was high (one-minute load about 15–17), and some date/loop runs
had substantial outliers. No implementation change or speedup claim follows
from this noisy difference.

Final candidate CI repeats the complete comparison after other qualification
jobs. Its retained `comparison.json` is the authoritative numerical record for
that exact candidate; inspect its flags and distributions before publication.
A new material slowdown requires investigation rather than inheriting this review.

These measurements cover five small workloads, not process memory, complete
language behavior or superiority to another engine. Raw logs/receipts remain
generated artifacts outside Git and accompany prepared release evidence.
