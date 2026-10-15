# Documentation

Start with the [README](../README.md) and the [public consumer](../Examples/Consumer).
The [DocC catalog](../Sources/Liquid/Documentation.docc) contains API reference and
guides that are compiled from the public Swift symbol graph.

| Guide | Purpose |
| --- | --- |
| [Language](Language.md) | Syntax, standard surface, coercion, and compatibility boundaries |
| [Errors](Errors.md) | Throwing and recovered output, diagnostics, and invocation ownership |
| [Custom filters](CustomFilters.md) | Typed engine-scoped callbacks, arguments, admission and failures |
| [Inspection](Inspection.md) | AST summary, syntactic references, limits and CLI JSON schema |
| [Metrics](Metrics.md) | Opt-in elapsed durations, logical budget counts, recovery and CLI metrics schema |
| [Application reuse](Reuse.md) | Retained root/partial bundles, explicit domain mapping and bounded application caches |
| [Dates](Dates.md) | Input coercion, Gregorian arithmetic, fractions, offsets, and formatting |
| [CLI](CLI.md) | Rendering files and JSON input, validation, analysis, options, and exit behavior |
| [Architecture](Architecture/README.md) | Extraction, values, parser, renderer, and concurrency |
| [Conformance](Conformance.md) | Pinned fixtures, reference comparisons, counts, and limitations |
| [Performance](Performance.md) | Repeatable release-mode measurements |
| [Release plan](ReleasePlan.md) | Required gates for 1.0 and subsequent work |
| [1.1 roadmap](Roadmap.md) | Adopted custom filters, template inspection, delivery sequence and release gates |
| [1.2 roadmap](Roadmap-1.2.md) | Adopted opt-in render metrics, CLI JSON file, compatibility boundaries and qualification |
| [1.3.0 release notes](Releases/1.3.0.md) | Additive dependency tooling, compatibility, measurements and release assets |
| [Dependency inspection](Dependencies.md) | Bounded explicit-bundle graph, findings, capacities and CLI schema |
| [1.3 roadmap](Roadmap-1.3.md) | Adopted bounded partial-dependency inspection, explicit CLI mode and acceptance gates |
| [Upstream feature review](Architecture/UpstreamFeatureReview.md) | RhoeLiquid capabilities, implementation findings and scope decisions |

Run `python3 Scripts/ci.py --lane docs` to compile the catalog. Generated files go
under Artifacts and remain outside source control.
