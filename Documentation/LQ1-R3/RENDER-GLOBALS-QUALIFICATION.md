# Approved host-input correction

The maintainer adopted Ruby's isolated-render host-global semantics on
2026-10-16, authorized correcting the one conflicting authored assertion and
requested a complete gate rerun. The [decision record](RENDER-GLOBALS-ADR.md)
retains the earlier failed experiment and explains the precise semantic change.
This correction remains local: no merge, release, tag or public API addition.

Original host inputs are admitted once and retained beneath invocation-local
scope overlays. An isolated render discards caller assignments, captures, loop
locals and counters, then applies its explicit bindings over those original
inputs. Nested render sees the original inputs unless values are passed explicitly.
Includes retain shared scope. Null bindings mask host roots; missing values do
not accidentally import a caller local. The implementation adds no loader,
reflection, global mutable state, core dependency or implicit I/O.

Only `InspectionTests.concurrentRendersAndInspectionShareOnlyImmutableTemplates`
changes an existing expectation: its root uppercases the host name and its partial
now reads the original host name, giving `N7n7` instead of `N7`. Its forty tasks
and inspection checks are unchanged. Supplementary controls cover the exact case
in lax, strict and strict2 through source/parsed raising and recovered rendering.
All historical Golden, Ruby, date, host-extension and liquid-spec fixtures remain
byte-for-byte unchanged, as do expected bytes, pins and comparator policy.

Public regressions also exercise named overrides, nested render, render-for,
include sharing, caller-local hiding, null/missing, explicit host loop fields,
counter/cycle isolation, partial errors and locations, healthy siblings after
cancellation and shared-template concurrent reuse under all four render policies.
Finite context admission, output, evaluator work and nesting remain enforced;
measured admission demonstrates that repeated partials do not readmit host roots.

The return compares against both the original R3 `8ab1632` and exact R2 at the
unchanged population: 5,099 source cases, 5,112 variants, 4,624 selected and 488
excluded. It preserves raw and phase-qualified verdicts separately, including
all continuing failures, operational outcomes and reference concerns. Old C
experimental matches are historical evidence, not new-run results.

Every final gate must bind to one clean SHA after all code/docs edits: native
Debug/Release and public consumers, safety ASan/TSan, docs/DocC, simulator compile,
immutable published 1.3.0 installation, pinned Ruby reference and independent
liquid-spec. The independent lane continues to exit 1 while failures remain.
The packet retains commands, exits, source and fixture hashes, raw traces,
before/after controls, the exact assertion patch and checksums. Native macOS and
simulator compilation have distinct scopes; no benchmark claim is made.

The pre-existing case-operand reevaluation difference, four continuing range
property failures, 25 parser-phase acceptances and 52 lax rejections remain
deferred. This authorization does not extend to those repairs or to a release.
