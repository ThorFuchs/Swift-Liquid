# LQ1-R3: runtime semantics and integration

Status: **partial by scope**. Two runtime rules are implemented; render-global
visibility is deferred with a [compatibility decision record](RENDER-GLOBALS-ADR.md).
This is a local evidence milestone, not a release or independent-conformance pass.

## Integration before repairs

R2's exact `2b64383` commit and ten coherent commits were restored from its Git
bundle. The 2,686 packet checksums and 219 source hashes verified. All ten commits
were replayed onto qualified main `2a9e787`, retaining quality sprint 4's output
cancellation, tests, measured-maintenance/release scripts, workflow and policies.
Conflicts in changelog, provenance and test-count documentation were reconciled
explicitly. CI and the test inventory were merged and audited for both tracks.

The clean integration-only commit `a3d83c0` passed native Debug/Release and public
consumers. Its independent results equal R2, including semantic result digests:
5,099 source cases, 5,112 variants, 4,624 selected, 488 excluded, 2,253 qualified
matches, 2,361 mismatches and ten operational errors. Integration earns no repair
credit. PR #15 and its separate release-candidate worktree remain untouched;
main/release state is timestamped in the return packet, rather than inferred.

## Two qualified rules

| Rule | General correction | Independent evidence |
| --- | --- | --- |
| Case branch identity | Internal `when(expression, body)` and `otherwise(body)` cannot collide with legal null values. Every matching when renders; an else considers preceding matches only. | Pinned Ruby `tags/case.rb`; liquid-spec `liquid_ruby/specs.yml:6701` and `:6728`; two additional qualified matches |
| Property size | Preserve dot-command versus bracket-key identity. An actual size key wins; otherwise typed maps count entries, strings count scalars, arrays count elements and native integers retain their storage size. A missing bracket size key is nil; length requires an actual key. | Pinned Ruby `variable_lookup.rb`; `partials/partials.yml:1022`, type/filter and security probes; ten additional qualified matches |

Case traversal, multiline-liquid normalization, blank suppression, dependency
inspection and immutable Sendable AST ownership use the explicit branch type.
The size command shares one supported-value calculation with the standard filter;
the filter retains its zero fallback for nil/unsupported values. Engine loop
records retain their explicit length field; they are not public host maps.

Supplementary public Swift Testing controls cover all three parser modes,
source/parse-once entry points, raising/recovered rendering, repeated and early
else branches, duplicate matches, unreachable errors, partials, exact Unicode keys,
nested/dynamic access and output/step/cancellation bounds. The reference probes
record 55 controls × three parser modes × two render policies; the C subset
remains research evidence. An additional all-mode shared-template concurrency regression exercises both rules. Existing concurrency tests and all pinned fixtures
are retained unchanged. Current inventory: 84 functions, 2,144 argument cases,
16 repeated adversarial/cancellation functions and seven TSan functions.

Post-A/B independent results are 2,265 qualified matches, 2,349 mismatches and ten
operational errors. The raw upstream comparator reports 2,292 matches and 2,332
mismatches. All twelve improvements are exact previously failing identities;
there are no qualified match-to-failure transitions. Eligibility, source digests,
expected bytes and the comparator are unchanged. The gate still exits 1.
These finite measurements are not a language-wide compatibility percentage.

## Render globals: evidence retained, implementation reverted

The C experiment preserved original admitted roots under local scope overlays and
matched the Ruby static-environment controls. Its full historical run exposed a
conflicting authored concurrency assertion: a root rendered `N7` and a partial
was expected to hide host `name: n7`; Ruby and C instead render `N7n7`.
All forty concurrent instances failed that unchanged assertion. The experiment's
targeted tests passed, but that does not qualify it against the existing contract.

R3 does not change that expectation. C was explicitly reverted; final runtime
bytes equal the qualified A/B implementation. Its two independent improvements
are **not** credited to the return. The packet retains the attempted commit,
revert, patch, full failed gate and exact all-mode reproduction. Approval of the
[scope decision](RENDER-GLOBALS-ADR.md) is required before another implementation.

## Remaining boundaries and next gate

The original 25 wrong-phase parser acceptances and 52 lax parse rejections remain
[deferred grammar](DEFERRED_GRAMMAR.md). Dynamic include receivers/default aliases,
dotted loop arguments, mixed-type sorting, render's include prohibition and
unused-partial eager admission remain separate findings. The two complex partial
cases are distinct: object-size correction repairs the cart case; nested-layout
host visibility remains unresolved after deferring C. Ten pinned-Ruby expectation
concerns and all operational failures remain explicit, not successful renders.

The 1.0–1.3 API/CLI schemas, 126 declarations, one library/CLI, empty root dependency
graph, supported numeric domain, escaping, parser defaults, recovery, quotas and
cancellation remain intact. No new loader, host reflection, tags or JSON bridge.
The [E3 RFC](../LQ1-R2/E3-SOURCE-DIAGNOSTICS-RFC.md) is unchanged and design-only.

Final qualification must run on one clean SHA after the last documentation edit:
native, safety, docs, simulator compilation, immutable published installation,
pinned reference and full liquid-spec. The return binds every lane to that SHA
and retains raw reports, commands and actual exits. No performance lane runs.
macOS runtime and simulator compilation remain distinct platform claims.

Recommended next gate: review the C historical-contract conflict and authorize or
defer a narrowly scoped host-input visibility decision before any further source
integration, semantic change, public API proposal, merge or release.
