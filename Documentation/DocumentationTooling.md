# Documentation qualification

Swift source comments define the public API reference. A native Swift 6.4 symbol
graph and DocC catalog provide the reference and guides; Python tooling uses only
the standard library. The root package needs no documentation plugin or dependency.

## Build and preview

Run the documentation lane from the repository root:

```sh
python3 -B Scripts/ci.py --lane docs
```

| Output under `Artifacts/docs` | Purpose |
| --- | --- |
| `symbols/Liquid.symbols.json` | Fresh public graph identified by the current Swift invocation |
| `coverage.json` | Summaries and named-parameter coverage for authored declarations |
| `api-compatibility.json` | Published 1.3.0 declaration compatibility; additions remain allowed |
| `readme-examples.log` | Exact README Swift fences compiled with their documented stdout |
| `Liquid.doccarchive` and `Liquid.doccarchive.tar.gz` | Native API reference and guides for offline use |
| `site` | Landing page, existing DocC routes and generated public build information |
| `site.json` | Route/asset checks, file hashes and source identity |
| `receipt.json` | Lane source inventory, toolchain, commands and results |

The graph must belong to the current checkout and contain authored Liquid
symbols. Coverage excludes compiler-synthesized declarations and extension
containers; it requires useful summaries and named parameters on every authored
public declaration. The published baseline contains 126 authored declarations
extracted from qualified 1.3.0 source. A removed or changed declaration fails;
compatible additions are allowed. This source-level check supplements public
consumers and does not claim binary ABI compatibility across compiler versions.

To preview the site while preserving its production base path:

```sh
mkdir -p Artifacts/docs/preview
ln -sfn ../site Artifacts/docs/preview/Swift-Liquid
python3 -m http.server 8771 --directory Artifacts/docs/preview
```

Open `http://localhost:8771/Swift-Liquid/`. The preview alias is outside the site
and is excluded from deployment. Open `Liquid.doccarchive` in Xcode for offline
reference. All generated files stay outside Git.

## Keep examples and links honest

All six runnable README Swift examples are committed as a separate public
consumer. The first two Swift fences are installation fragments; subsequent
fences are standalone programs within separate scopes. Their print statements
include expected stdout. After editing an example:

```sh
python3 -B Scripts/documentation_catalog.py --write-readme-examples
python3 -B Scripts/ci.py --lane docs
```

The lane compares the exact generated source, compiles and runs it, and checks
stdout against the README. Compilation alone cannot certify an example's output.
The five feature consumers still qualify the public integration contracts.

DocC warnings are errors. Site qualification checks required guide/data routes,
client-rendered reference and navigator routes, local HTML links and assets,
project-base containment, symlinks and private-content
markers. It records file hashes. External websites are linked as authorities and
reviewed separately; the offline gate does not treat network availability as a
runtime conformance result. Negative tooling regressions ensure missing comments,
changed public declarations, empty graphs, stale examples and broken site assets
cannot silently pass.

Existing articles retain `/documentation/documentation/…` URLs. Swift 6.4's DocC
renderer treats their first component as an optional locale when loading the
navigator. The builder copies the unchanged compiler index to that requested
path and checks byte equality, preserving article URLs and generated JavaScript.

## Publication and provenance

GitHub Pages receives only `Artifacts/docs/site`. Compiler graphs, command logs
and maintainer records are not website content. The deployment job runs on `main`
after all eight qualification lanes pass, with Pages/OIDC permissions confined
to that job. PRs compile and verify the site without deploying it. Actions are
pinned by commit.

Raw DocC and site trees contain Swift declaration filenames with colons. They are
excluded from the general ZIP evidence artifact, whose uploader rejects those
characters. Evidence retains the compiled DocC tar archive and site file manifest;
the separate Pages tar artifact carries the complete qualified site.

`build-info.json` identifies clean source, compiler and CI run. Dirty local builds
are marked as local previews and do not claim their HEAD commit represents the
modified source. The website tracks `main`; a release's compiled DocC archive
remains associated with that version's source and qualification evidence.
