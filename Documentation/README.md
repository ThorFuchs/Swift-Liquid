# Documentation

Start with the [documentation site](https://thorfuchs.github.io/Swift-Liquid/),
the [README](../README.md) and the [public consumer](../Examples/Consumer).
The [DocC catalog](../Sources/Liquid/Documentation.docc) contains API reference and
guides that are compiled from the public Swift symbol graph.

| Guide | Purpose |
| --- | --- |
| [Documentation tooling](DocumentationTooling.md) | Public comment coverage, compiled examples, site routes and local previews |
| [Contribution isolation](ContributionIsolation.md) | Hosted runner provenance, fork approval and publishing boundaries |
| [Package discovery](PackageDiscovery.md) | Published-URL installation and index status |
| [Quality sprints](QualityRoadmap.md) | Public quality work, acceptance gates and subsequent audits |
| [Language](Language.md) | Syntax, standard surface, coercion, and compatibility boundaries |
| [Errors](Errors.md) | Throwing and recovered output, diagnostics, and invocation ownership |
| [Custom filters](CustomFilters.md) | Typed engine-scoped callbacks, arguments, admission and failures |
| [Inspection](Inspection.md) | AST summary, syntactic references, limits and CLI JSON schema |
| [Metrics](Metrics.md) | Opt-in elapsed durations, logical budget counts, recovery and CLI metrics schema |
| [Application reuse](Reuse.md) | Retained root/partial bundles, explicit domain mapping and bounded application caches |
| [Dates](Dates.md) | Input coercion, Gregorian arithmetic, fractions, offsets, and formatting |
| [CLI](CLI.md) | Rendering files and JSON input, validation, analysis, options, and exit behavior |
| [Architecture](Architecture/README.md) | Extraction, values, parser, renderer, and concurrency |
| [Peer API crosswalk](Comparisons/README.md) | Pinned task-oriented API comparisons and evidence grades |
| [LQ1-R3 runtime review](LQ1-R3/README.md) | Local runtime integration, case/size and adopted host-input semantics; historical deferral retained |
| [LQ1-R2 triage](LQ1-R2/README.md) | Three bounded semantic repairs, diagnostic ledger and source-aware RFC |
| [LQ1 independent conformance](LQ1/README.md) | Isolated liquid-spec tooling, exact failures and next review gate |
| [Conformance](Conformance.md) | Pinned fixtures, reference comparisons, counts, and limitations |
| [Performance](Performance.md) | Repeatable release-mode measurements |
| [1.3.1 benchmark review](PerformanceReview-1.3.1.md) | Prior flags, independent study and release review policy |
| [Interpolation investigation](PerformanceReview-Interpolation.md) | Controls, rejected hypotheses and bounded synchronous execution |
| [Caller and date investigation](PerformanceReview-CallerDate.md) | Executor diagnostics, retained variability and rejected formatter hypothesis |
| [Recurring date investigation](PerformanceReview-RecurringDate.md) | Direct release comparisons, process CPU observations and unresolved historical flags |
| [CPU and executor tracing](PerformanceReview-DateTracing.md) | Recorded execution paths, repaired symbol coverage, retained failures and unresolved date flags |
| [Date-recognition CPU costs](PerformanceReview-DateRecognition.md) | Controlled component boundaries, typed audit controls, complete comparisons and unresolved flags |
| [Parser operation costs](PerformanceReview-ParserOperations.md) | Normalization, matching, captures, original helpers and complete variability review |
| [Measured maintenance](MeasuredMaintenance.md) | Larger inputs, observed spread and cancellation response |
| [Release plan](ReleasePlan.md) | Required gates for 1.0 and subsequent work |
| [1.1 roadmap](Roadmap.md) | Adopted custom filters, template inspection, delivery sequence and release gates |
| [1.2 roadmap](Roadmap-1.2.md) | Adopted opt-in render metrics, CLI JSON file, compatibility boundaries and qualification |
| [1.3.1 release notes](Releases/1.3.1.md) | JSON depth and cancellation fixes, quality gates and retained measurements |
| [1.3.0 release notes](Releases/1.3.0.md) | Additive dependency tooling, compatibility, measurements and release assets |
| [Exact registry graphs](ExactRegistryDependencies.md) | Two exact-name overloads, atomic admission and runtime parity |
| [Dependency inspection](Dependencies.md) | Bounded explicit-bundle graph, findings, capacities and CLI schema |
| [1.3 roadmap](Roadmap-1.3.md) | Adopted bounded partial-dependency inspection, explicit CLI mode and acceptance gates |
| [Upstream feature review](Architecture/UpstreamFeatureReview.md) | RhoeLiquid capabilities, implementation findings and scope decisions |

Run `python3 Scripts/ci.py --lane docs` to compile the catalog. Generated files go
under Artifacts and remain outside source control.

- [Maintained development and CI operations](Maintenance.md)

## Development exact-name primitive

[Exact template registry](ExactTemplateRegistry.md) documents the additive U1
registry and resolver. [Exact registry rendering](ExactRegistryRendering.md)
describes the additive U2 runtime bridge. Graph inspection, the CLI and Vapor
retain their existing APIs; dictionary behavior remains unchanged.
