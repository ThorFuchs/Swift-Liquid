# Command-line workflows

Render, validate and inspect templates using the `liquid` executable.

## Run from a checkout

```sh
swift run -c release liquid render page.liquid --data context.json --partials ./partials
swift run -c release liquid validate page.liquid
swift run -c release liquid analyze page.liquid --format json
swift run -c release liquid analyze page.liquid --dependencies --partials ./partials --format json
```

Rendering writes template bytes to stdout or an explicit `--output` file. Diagnostics
go to stderr. A template path of `-` reads stdin. Build with the supported Swift 6.4
compiler; SwiftPM chooses the binary output directory for that toolchain.

## Keep reports separate from output

`render --metrics PATH` writes an independent JSON metrics file, preserving rendered
stdout. Use <doc:RenderMetrics> for timing boundaries and counter meanings.

Ordinary `analyze` emits a single-template AST summary. `analyze --dependencies`
emits the separate dependency schema, with optional `--partials DIR`. Findings such
as missing references, cycles and dynamic includes exit successfully; consumers
choose their own rejection policy. Operational failures emit diagnostics and a
nonzero exit status. Read <doc:TemplateInspection> and <doc:PartialDependencies>.

The [CLI reference](https://github.com/ThorFuchs/Swift-Liquid/blob/main/Documentation/CLI.md)
defines flags, defaults, containment rules, exit behavior and versioned JSON schemas.
The CLI does not discover application callbacks or host integrations.
