# Dependency-report schema qualification

An isolated public consumer of published Swift-JSON 1.3.0 (`JSON`, `JSONSchema`).
Its exact version and resolved revision are pinned here. No package dependency
is added to Swift-Liquid's root manifest, library, CLI or downstream consumers.
This tool requires Swift 6.4 and macOS 27, matching Swift-JSON's declared minimum.

The native/development lane invokes `Scripts/check_dependencies.py` against the
actual CLI. It compiles the Draft 2020-12 dependency-report schema offline, then
validates successful CLI reports and deliberate invalid shapes/versions. Optional
unknown metadata is accepted. Compilation, evaluation and resource failures throw;
only completed invalid-instance verdicts count as negative cases. No networking
occurs during schema evaluation; SwiftPM initially fetches the public dependency.

```sh
python3 -B Scripts/ci.py --lane native
```

The schema qualifies report shape. API/CLI regressions separately qualify graph
relationships, byte ordering, resolution and finding semantics. See the
[complete contract](../../Documentation/Dependencies.md).
