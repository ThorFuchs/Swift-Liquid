# Documentation

Start with the [README](../README.md) and the [public consumer](../Examples/Consumer).
The [DocC catalog](../Sources/Liquid/Documentation.docc) contains API reference and
guides that are compiled from the public Swift symbol graph.

| Guide | Purpose |
| --- | --- |
| [Language](Language.md) | Syntax, standard surface, coercion, and compatibility boundaries |
| [Errors](Errors.md) | Throwing and recovered output, diagnostics, and invocation ownership |
| [Custom filters](CustomFilters.md) | Unreleased typed engine-scoped callbacks, arguments, admission and failures |
| [Dates](Dates.md) | Input coercion, Gregorian arithmetic, fractions, offsets, and formatting |
| [CLI](CLI.md) | Rendering files and JSON input, validation, options, and exit behavior |
| [Architecture](Architecture/README.md) | Extraction, values, parser, renderer, and concurrency |
| [Conformance](Conformance.md) | Pinned fixtures, reference comparisons, counts, and limitations |
| [Performance](Performance.md) | Repeatable release-mode measurements |
| [Release plan](ReleasePlan.md) | Required gates for 1.0 and subsequent work |
| [1.1 roadmap](Roadmap.md) | Adopted custom filters, template inspection, delivery sequence and release gates |
| [Upstream feature review](Architecture/UpstreamFeatureReview.md) | RhoeLiquid capabilities, implementation findings and scope decisions |

Run `python3 Scripts/ci.py --lane docs` to compile the catalog. Generated files go
under Artifacts and remain outside source control.
