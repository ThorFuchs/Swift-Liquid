# Release process

Version tags use semantic versions such as `1.0.0`. Never move a published tag.
The maintainer must explicitly request publication; CI does not create releases.

1. Complete the [release gates](Documentation/ReleasePlan.md) at the exact
   candidate commit. Run native, safety, reference, platforms, documentation,
   performance, installation and matched-performance lanes. Review matched comparison flags.
   The reference lane requires the clean pinned checkout and recorded Ruby/Date/Time versions.
2. Review fixture pins, actual evaluated counts, reference differences, source
   provenance, all public API/CLI documentation, and the public file inventory.
3. Run `python3 Scripts/ci.py --lane archive` on the clean candidate commit. It
   compares repeated source-archive bytes, audits the tracked inventory, rebuilds
   from a clean extraction, and prepares source/DocC assets with checksums.
   Finalize the changelog and compatibility statement before qualifying a new
   candidate commit.
4. Create an annotated version tag at the qualified commit. Prepare release notes,
   qualification and benchmark receipts, source/DocC archives, and SHA-256 checksums.
5. Verify exact-commit GitHub Actions, repository reporting routes, and assets.
   Publish the release and check version resolution from a separate SwiftPM consumer.

If a required gate fails, keep the repository at development status and record
the gap. A green fixture suite alone does not qualify a stable release.

Current development matched measurements use the immutable 1.3.0 harness and library commit;
see [performance](Documentation/Performance.md). Download every successful lane
artifact and save `gh run view --json status,conclusion,headSha,url` output as
`github-run.json` in the evidence directory. From the clean candidate checkout:

```sh
python3 -B Scripts/prepare_release.py --version NEXT_VERSION --evidence /path/to/evidence \
  --run-url https://github.com/ThorFuchs/Swift-Liquid/actions/runs/RUN_ID
```

Before packaging, add `benchmark-review.json` to the evidence directory. Record
`status: "reviewed"`, `releaseQualification: "passed"`, the exact comparison file's
`comparisonSHA256`, `baselineCommit`, `candidateLibrarySHA256`, and the complete
`reviewedCompatibilityFlags`, `reviewedMetricsFlags`,
`reviewedCompatibilityVarianceFlags` and `reviewedMetricsVarianceFlags` arrays. Retain prose
explaining the distributions, flags and material limitations. Unresolved material
regressions cannot be accepted by setting a status field.

The script verifies all nine receipts against the current source inventory,
compares every source-archive file, recomputes all 26 common and 24 metrics
comparisons, validates retained samples, four graph benchmark records and complete larger-workload/
cancellation observations,
checks the bound review and archive checksums, and prepares
three archives, checksums, release notes and a manifest under `Artifacts/release`.
It performs no publication or tag mutation. A PR qualification may test a GitHub
merge commit with the same tree; after merging, qualify the actual release commit
again before creating the immutable version tag. Review the candidate's matched
benchmark distributions/flags separately; packaging is not a performance verdict.


Routine `Repository correctness` and its clean archive establish engineering
correctness evidence only. They do not replace either timing lane, the explicit
benchmark review, a current compatibility decision, exact-release-commit checks
or the maintainer's publication request. The nine-receipt packaging validator and
all released obligations remain unchanged. Manual benchmark and documentation
workflows grant no release authority. Retain each actual workflow/run identity;
a routine correctness run alone does not certify nine release lanes.
