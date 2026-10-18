# E4 — Optional host loader and output sink

Status: design study; deferred. Signed **Codex, 2026-10-15**; maintainer review pending.

Problem: hosts may want async partial loading or output delivery without building
their own orchestration. The core's explicit-bundle and complete-String contracts
remain useful. Do not add filesystem/network effects to Liquid.

Study a separate opt-in module/package with a typed Sendable host callback and
explicit policy. The application must define name normalization, allowed roots,
symlink/path handling, cache capacity/identity, content revisions, maximum source
bytes/counts, deadline and cancellation. No default filesystem or URL loader.
A loader should produce an admitted snapshot before rendering where possible;
otherwise specify deterministic first-use failures and nested dependency behavior.

An output sink needs bounded async backpressure and a single invocation owner.
Define whether chunks are UTF-8 complete, how escaped output and quota accounting
cross boundaries, and who flushes/completes the destination. A thrown render can
leave delivered bytes: offer an explicitly transactional staging/commit path or
state partial-output semantics. Never claim general rollback for sockets. Sink
failures and cancellation stay operational and preserve their original identity.

Review interaction with custom async filters, metrics timing, diagnostics and
partial recursion. A consumer must be able to distinguish render completion from
transport completion, retain prior output on a failed atomic-file render, and
cancel a blocked sink. No synchronous blocking wrapper should be inferred.

Required evidence: slow/failing/cancelled loader/sink actors, finite buffers,
source changes, traversal aliases, nested loads, exact byte accounting, output
completion/rollback and independent concurrent invocations. This study is not a
license to introduce hidden I/O into the conformance adapter or core renderer.
