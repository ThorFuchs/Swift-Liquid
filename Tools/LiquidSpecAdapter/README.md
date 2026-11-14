# Independent Liquid specification adapter

Development-only, macOS JSON-RPC 2.0 executable using the public `Liquid` module.
It adds no products or dependencies to the root package. The companion Ruby driver
uses Shopify's real pinned `AdapterRunner#run_single` and its unchanged comparator.
It runs functional checks only, including the partials suite without timing.

## Reproduce

Use clean checkouts outside the repository at the commits in [Pins.json](Pins.json).
Use Ruby 4.0.1, Date 3.5.1 and Time 0.4.2. Install the development gems from
[Gemfile](Gemfile) into an external `GEM_HOME` with Bundler, then preserve its lockfile
with the run. The packet records every loaded gem; neither Ruby nor these gems are
runtime dependencies of Liquid. Do not evaluate templates as Ruby code.

```sh
export LIQUID_RUBY=/path/to/ruby-4.0.1/bin/ruby
export PATH="$(dirname "$LIQUID_RUBY"):$PATH"
# Set GEM_PATH to the isolated development gem installation.
python3 Scripts/ci.py --lane liquid-spec \
  --spec-path /path/to/pinned/liquid-spec \
  --reference-path /path/to/pinned/liquid
```

`Artifacts/liquid-spec/independent/` contains command logs and a source-bound receipt.
Its `spec/` directory contains `ELIGIBILITY_MATRIX.json`, `SPEC_RUNS.json` and raw
JSON-RPC traces with source/context/partial inputs replaced by SHA-256 digests.
Nonzero exits are expected while mismatches remain; they are never a qualification
pass. Each excluded variant has a reason. A source case may expand into multiple
parser-mode variants; unsupported `warn` records remain visible.

The adapter intentionally replaces the upstream JSON-RPC Ruby wrapper: at this pin
that wrapper handles compile `result.error` but loses render `result.error`.
Our bridge preserves it. The upstream subprocess also kills immediately after
`quit`; our subclass waits for clean exit and records status. Failed exchanges
fail the current case; the next compile can initialize a fresh process. No case
is retried to obtain a passing result. Both adaptations are local to tooling.

Read [the LQ1 contract and verdict](../../Documentation/LQ1/README.md),
[adapter limits](../../Documentation/LQ1/ADAPTER_LIMITS.md) and the
[pinned upstream protocol](https://github.com/Shopify/liquid-spec/blob/84bf25e0edbca5f7e530574788b0f875ab331f50/docs/json-rpc-protocol.md).

R2 records the original upstream `result.passed?` unchanged in `upstreamVerdict`
and `comparison`. The separate `qualificationComparison` retains LQ1's stricter
phase/operational checks. Diagnostic dimensions are explanatory, never a
replacement comparator. See [R2 evidence semantics](../../Documentation/LQ1-R2/README.md).
The observed phase follows the JSON-RPC operation: syntax errors returned while
rendering a lazily parsed partial are render-phase failures, while their
reported error family and original partial-local line remain syntax evidence.

## Reviewed reference conflicts

The raw `liquid-spec` lane remains unchanged and reports the upstream verdict,
including its nonzero exit when the five cases in [issue #170](https://github.com/Shopify/liquid-spec/issues/170)
fail. The separate reviewed profile runs that same lane first and admits only
the exact pinned case identities, fixture digests, modes, outcomes and independent
Ruby observations in `ReviewedConflicts.json`:

```sh
python3 -B Scripts/ci.py --lane liquid-spec-reviewed \
  --spec-path /path/to/liquid-spec --reference-path /path/to/liquid \
  --output-root /path/outside/the/checkout
```

Its successful status is `passed-with-reviewed-reference-conflicts`, with zero
unexpected failures. The five remain raw failures, not passes. `review/REVIEWED_RESULT.json`
records both views, pinned source and checksums; `review/EXCLUSION_AUDIT.json`
lists each not-executed case and its recorded reason. The raw runner's complete
evidence remains under `independent/`. Changed fixtures, selections, conflict
outcomes, missing evidence, new failures or a conflict that starts passing fail
the reviewed profile until it is reassessed. No suite result grants release or
complete-language acceptance.

The historical population contained 488 unexecuted variants. `ExclusionCandidates.json`
identifies 56 filesystem-callback cases with no `include` or `render` word in their
supplied sources and two range-metadata cases without resource limits. These 58
are individually admitted only while their identity, fixture bytes and relevant
conditions remain unchanged. `review/ADMISSION_AUDIT.json` records each actual
suite and Ruby-reference outcome. Other exclusions remain separately visible.

Five further individually identified cases cover a comment-only filesystem
callback, three missing-file diagnostics and the pinned loader's exact
100,000-character `LongString` materialization. Their narrowly checked feature
exceptions never bypass unrelated transport checks or change the comparator.
