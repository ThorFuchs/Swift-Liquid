# Release process

Version tags use semantic versions such as `1.0.0`. Never move a published tag.
The maintainer must explicitly request publication; CI does not create releases.

1. Complete the [1.0 release gates](Documentation/ReleasePlan.md) at the exact
   candidate commit. Run native, safety, documentation, and performance lanes.
2. Review fixture pins, actual evaluated counts, reference differences, source
   provenance, all public API/CLI documentation, and the public file inventory.
3. Update the changelog and compatibility statement. Build the public source and
   DocC archives; extract the source into a clean directory and rerun native checks.
4. Create an annotated version tag at the qualified commit. Prepare release notes,
   qualification and benchmark receipts, source/DocC archives, and SHA-256 checksums.
5. Verify exact-commit GitHub Actions, repository reporting routes, and assets.
   Publish the release and check version resolution from a separate SwiftPM consumer.

If a required gate fails, keep the repository at development status and record
the gap. A green fixture suite alone does not qualify a stable release.
