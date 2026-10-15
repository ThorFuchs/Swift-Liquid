# LQ1: independent conformance and developer contract

Status: local implementation and qualification; maintainer review pending.
No push, tag, release or public API change is authorized by this gate.

LQ1 adds an independent track from Shopify's
[liquid-spec at the audited pin](https://github.com/Shopify/liquid-spec/tree/84bf25e0edbca5f7e530574788b0f875ab331f50).
It preserves the published Golden Liquid, authored/date and host-extension inputs
and all prior release receipts. Its verdict cannot revise a historical release.

The [isolated adapter](../../Tools/LiquidSpecAdapter/README.md) compiles with Swift
6.4 and calls only public Liquid APIs. Its real upstream runner compares outputs
and errors, with separate parser and raising/recovery modes. The source manifest's
5,099 cases expand into 5,112 mode variants, including six unsupported `warn`
variants. Advertised counts come from the pinned upstream README; observed counts
come from the matrix. They are different measurements.

The first full repaired run selected 4,536 variants: 2,205 comparator matches, 2,321
mismatches and 10 operational quota failures. Another 576 variants were not
executed with visible reasons. This is a failed independent conformance gate,
not full language compliance. `parser_errors` alone has 1,902 mismatches under the pinned comparator:
1,857 reject during parsing but differ in diagnostics, 43 render successfully,
and two fail only during rendering. Rejection and exact diagnostic compatibility
are separate axes. Complexity readouts cover eligible cases only and make no
language-wide claim. Matches use the unchanged upstream output/error-pattern comparator plus an explicit
parse/render phase check. They do not all mean byte-identical diagnostics. No
throughput, latency or allocation comparison was run.

One verified core defect was repaired: nonpositive `truncate` lengths retain the
ending, including overflow-safe handling of `Int.min`. A new public Swift Testing
regression cites `basics/filter-edge-cases.yml:282`. Original failures remain in
the return packet; no fixture expectation was changed. Other observed differences
remain open until minimal reproduction, pinned Ruby verification and domain review.

| Record | Purpose |
| --- | --- |
| [Baseline ledger](BASELINE.md) | Sources, toolchains and concurrent-work reconciliation |
| [Adapter limits](ADAPTER_LIMITS.md) | Transport, quotas, clock, types and unsupported features |
| [Mismatch review](MISMATCHES.md) | General-rule findings and exact failure accounting |
| [API crosswalk](../Comparisons/README.md) | Task-oriented peer API mapping and evidence grades |
| [Scope decisions](SCOPE_DECISIONS.md) | Five studies and one deferred implementation candidate |
| [Next gate](NEXT_GATE.md) | Review requirements and reproducible acceptance boundary |

Raw matrices, run receipts, protocol traces, gate logs, source diff/archive and
checksums are delivered as a local return packet. Large generated results stay
outside Git. A failing independent lane must remain failing until its selected
mismatches and operational errors are resolved or individually reviewed in scope.
