# Swift-Liquid 2.1 roadmap

Status: **adopted by the maintainer** as the development and qualification
sequence. Adoption is not an implementation, conformance verdict, benchmark
result or authorization to publish. It uses the released 2.0.0 source at
`390016a96a64a558bdc7844a0a456bf601156307` and its retained evidence as the
starting point. A future 2.1 candidate and all its evidence must be identified
independently.

## Starting position

The exact-main reviewed conformance evidence covers five configured suites at
liquid-spec `84bf25e0edbca5f7e530574788b0f875ab331f50`, with Ruby Liquid
`4e39ae4cc3da73921923c0669e0fc84a66b2f696` as a separate reference. Its 5,112
recorded variants comprise 4,682 matches, five reference conflicts and 425
unexecuted variants. The upstream verdict remains failed for the five conflicts;
the separate reviewed profile has zero unexpected failures. The 425 are neither
passes nor measured failures. The [case-by-case review](LQ1/UNEXECUTED-CASE-REVIEW.md)
retains identities, fixture digests and first recorded exclusion reasons.

The counts below are mutually exclusive **first recorded reasons**, not a proof
that each case has only one requirement. Cases can have overlapping feature tags
and additional barriers that appear only after the first one is addressed.
Counts are mode variants, not distinct source fixtures.

| Recorded first boundary | Variants | Proposed disposition |
| --- | ---: | --- |
| Standard `drops` alone | 56 | First investigate the pinned standard test-drop library and the exact behaviors needed. Admit only semantics faithfully represented and validated end to end. |
| `drops` plus a template factory | 3 | Keep separate until both the drop and host-factory contracts are defined; solving one does not admit the other. |
| Ruby-native drops, including class-identity cases | 137 | Keep excluded from the portable profile unless a separately justified host-object capability preserves the actual behavior. |
| Ruby security test objects | 93 | Keep excluded until a faithful object and security-boundary design exists; do not replace them with unrestricted dictionaries. |
| Non-string object keys | 76 | Keep excluded from string-keyed JSON input; investigate only with an explicit, lossless value-domain contract. |
| Other Ruby host-object conversions | 22 | Review the actual object and conversion behavior individually; avoid generic reflection. |
| Ruby `Date` and `Time` objects | 7 | Distinguish typed host values from ISO strings; no implicit conversion without a fidelity contract. |
| Non-UTF-8 binary data | 5 | Retain the binary boundary until an explicit byte-oriented representation is designed. |
| Cyclic value or Ruby symbol | 2 | Preserve explicit rejection; cycles and symbols are not JSON values. |
| Shopify/range resource-score policies | 11 | Do not equate Ruby scores with Swift logical budgets. Study independently only if useful to the portable scope. |
| Unsupported `warn` parser variants | 6 | Study the parser-mode contract and whether a nonbreaking opt-in representation is justified. |
| Integers outside native `Int` | 7 | Preserve rejection; any wider numeric domain requires an explicit arithmetic and API decision. |
| **Total** | **425** | No case changes selection or outcome until its exact inputs and remaining requirements are checked. |

This population is not the whole upstream repository: the pinned configuration
also excludes benchmark, Shopify production-recording and Dawn suites as suites.
They need their own portability and host-feature review; do not add their source
case counts to the 425 variants above. Hosted storefront objects, tags and filters
are outside the dependency-free open-source Liquid core.

The existing `LiquidValue` is a checked-Sendable, finite primitive/array/object
domain. The opt-in `closedSystemV1` environment supplies resident decorated
values; it is not a general lazy Drop or arbitrary host-object callback API. The
adapter currently rejects `_rpc_drop`, and its Ruby bridge rejects unexpected
callbacks. The pinned [protocol](https://github.com/Shopify/liquid-spec/blob/84bf25e0edbca5f7e530574788b0f875ab331f50/docs/json-rpc-protocol.md)
distinguishes portable standard test drops from host-owned callback drops. A
test-drop value must not be flattened into a primitive when that changes dynamic
lookup, iteration, truthiness, errors or identity.

## 2.1 priorities

### 1. Complete the outstanding 2.0.0 performance assessment

This is a post-release evidence supplement, not a claim that the 2.0.0 release
originally passed its waived gates. Preserve the published tag, release assets,
waiver and all blocked host cohorts. Use the exact 2.0.0 commit and tree in an
isolated checkout, with the pinned 1.3.0 baseline commit
`9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e` and the unchanged canonical harness,
manifest, fixtures, output checksums, ordering and sample policy in
[performance measurements](Performance.md).

Before a new finite cohort, verify source, baseline objects, toolchain, output
preservation, capacity and the effective environment. Select a genuinely quiet
or dedicated host and record its ownership/availability; a snapshot does not
reserve it. Retain the established host admission: AC, no known interference
or affirmative restriction, two consecutive fresh snapshots at least 60 seconds
apart, one-minute load at most half the logical CPU count and five-minute load
at most the CPU count. At most three snapshots per lane; stop if admission is
impossible. Record unavailable thermal status as unknown. Do not claim internal
phase power or thermal stability from invocation-boundary observations.

Run the unchanged `performance` lane once, then the unchanged
`matched-performance` lane once only after its own fresh source, environment,
output and host admission. Preserve all partial or failed results. Review the
full distributions, checksums, three ABBA blocks, all four change/variance flag
lists and historical findings in a source- and comparison-hash-bound record.
Mechanically valid results are not automatically a performance verdict; retain
any unresolved material regression. Publish a clearly dated evidence supplement
only after review, without replacing the original 2.0.0 qualification archive
or changing the historical release decision. If the host is blocked, retain
the result and arrange an appropriate host rather than repeatedly selecting runs.

For 2.1 itself, repeat the final-source release gates and benchmark review on
the final 2.1 commit. The current canonical matched lane is pinned to **1.3.0**;
it does not already implement a 2.0.0 baseline. If a direct 2.1-versus-2.0
comparison is desired, propose and validate that as a separate source-bound
protocol before execution, retaining the canonical comparison until an explicit
reviewed policy change. No benchmark thresholds, workloads or sampling are
weakened merely to clear a gate.

### 2. Standard test-drop feasibility and narrow first slice

First produce a case-to-capability matrix for the 56 drop-only variants: pinned
fixture and mode, constructor input, required lookup/iteration/value behavior,
other feature tags, expected errors, and whether current public values can
faithfully represent the object. Verify behavior with the pinned Ruby reference
and the standard [test-drop contract](https://github.com/Shopify/liquid-spec/blob/84bf25e0edbca5f7e530574788b0f875ab331f50/docs/test_drops.md).
The 56 are an upper bound for this first slice, not a promised pass count.

The [first capability study](LQ1/STANDARD-DROPS-2.1.md) found seven differences
in 78 Ruby controls between boxed drops and primitive substitutions. Therefore
do not flatten boxed drops in general; any narrower representation must first
prove equivalence for its complete supported contract. Do not precompute dynamic properties, turn
opaque objects into dictionaries, execute fixture text, or special-case expected
outputs. Admit individual cases only after their complete inputs, identity and
other prerequisites are verified. Keep raw upstream and qualified outcomes,
original denominators and case-level evidence visible.

If the matrix requires dynamic lookup, iteration or error-producing objects,
write a separate public API proposal before implementation. It must decide
typed checked-Sendable interfaces, explicit exposure/allowlisting, missing versus
null, async and reentrancy behavior, value admission, per-render ownership,
quotas, cancellation and host errors. Compare native standard test drops with
the optional bidirectional RPC design; neither implies arbitrary Ruby reflection
or implicit I/O. Public API, security and downstream compatibility review are
prerequisites, not a count-driven promise for 2.1. Preserve the root's empty
dependency graph and one library/one executable product.

### 3. Make conformance evidence easier to trust

- Correct the current adapter-limits document: the current adapter compiles the
  root and supplies partial sources for lazy selection, rather than eagerly
  parsing every partial. Recheck its stated bounds and protocol version against
  the code before changing the document.
- Preserve each exclusion's full identity, mode, fixture digest and reason;
  distinguish first reasons from overlapping tags and separately excluded suites.
  Retain the 63 individually admitted historical candidates and their evidence.
- Track [Shopify liquid-spec issue #170](https://github.com/Shopify/liquid-spec/issues/170)
  and reassess the five exact conflicts if the reference, fixture or upstream
  decision changes. Do not rewrite expectations or silently convert them to
  passes. Any upstream pin update is a separately reviewed comparison, not an
  in-place rewrite of the released baseline.
- Keep the original and reviewed verdicts separate in CLI/dashboard and public
  documentation. A no-unexpected-failures profile is not complete conformance.

### 4. Bounded follow-up studies

Review the six `warn` variants and eleven score-policy variants individually.
Determine whether each belongs to the open-source language target and whether
an additive contract is useful. Keep Ruby score semantics separate from Swift
budgets; cancellation, quota failures and host failures remain operational.
The seven wide-integer variants require a separate exact-number/domain proposal;
a Swift-JSON companion cannot by itself extend Liquid arithmetic or justify a
new core dependency. Defer binary values, arbitrary Ruby classes, dynamic plugin
systems, implicit I/O and hosted theme behavior unless separately scoped.

## Sequence and acceptance

| Step | Deliverable | Exit evidence |
| --- | --- | --- |
| 1 | Repair the current adapter documentation and freeze the exact 2.0.0 baseline. | Documentation checked against code; original release/waiver and all 425 records preserved. |
| 2 | Complete post-release 2.0.0 timing when an admitted host is available. | Both exact-source lanes, raw receipts and four-list review, or a clearly retained blocked/failed result. |
| 3 | Standard test-drop capability matrix and smallest faithful prototype proposal. | Exact case-level inputs and reference observations; identify any need for a public API decision. |
| 4 | Implement only an adopted narrow slice. | Public consumer and focused regression tests, unchanged pinned fixtures/comparator, full per-case raw and reviewed results, and extraction-manifest adaptations for actual changes. |
| 5 | Prepare 2.1 release candidate. | Re-run affected `Scripts/ci.py` checks and complete the final-source correctness, archive, performance and matched-performance gates; review any compatibility changes and benchmark flags. |

The smallest useful next task is **Step 1 plus the read-only case-to-capability
matrix in Step 3**. It can proceed while the separate timing host is arranged.
No new Drop API, fixture admission, pin change or release follows from this
roadmap without the relevant design and qualification work.
