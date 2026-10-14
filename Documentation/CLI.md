# CLI reference

Build with `swift build -c release`. The executable product is `liquid`.
Use `swift run liquid --help` while developing, or the built release executable.

| Command | Behavior |
| --- | --- |
| `render TEMPLATE` | Render a UTF-8 file or `-` for stdin |
| `validate TEMPLATE` | Parse a UTF-8 template and fail on invalid syntax |
| `analyze TEMPLATE` | Inspect parsed references without rendering (unreleased 1.1) |
| `--version` | Show the package version (`Swift-Liquid 1.0.0`) |
| `--help` | Show commands and options |

Render options:

| Option | Behavior |
| --- | --- |
| `--data PATH` | Read a JSON object as the context |
| `--partials DIRECTORY` | Load `.liquid` files recursively under one explicit directory |
| `--output PATH` | Atomically write completed output to a file |
| `--syntax-mode lax\|strict\|strict2` | Select parsing behavior; default lax |
| `--strict-filters` | Fail on unknown filters |

Rendering emits only rendered content on stdout. Successful validation prints
`Valid Liquid template.` Diagnostics go to stderr. Success exits 0; syntax,
input, runtime, and usage failures exit 1. Output files are written only after a
complete successful render. Existing output remains unchanged on render failure.

Partial names use paths relative to the supplied directory without their `.liquid`
suffix. The CLI skips hidden entries and symbolic links within that directory.
The library itself never performs filesystem access. JSON input preserves object
member order and rejects duplicate keys; the root context must be an object.

```sh
printf '{"name":"Ada"}' > context.json
printf 'Hello, {{ name | escape }}!' > greeting.liquid
swift run liquid render greeting.liquid --data context.json
swift run liquid validate greeting.liquid --syntax-mode strict
```

## Template analysis (unreleased 1.1)

`liquid analyze TEMPLATE` prints variable roots, filter names, literal partial
names and whether dynamic include references occur. It uses the library's AST
inspection and never evaluates filters or opens partials. Variable roots describe
syntactic reads, including locals and conditional paths; they are not required
context keys.

Use `--format json` for the versioned machine-readable summary, or `--format text`
(the default) for four labeled lines. Both accept `--syntax-mode lax|strict|strict2`.
Other render options are rejected. Files and stdin follow the same UTF-8/source
capacity rules as validation. Failures emit no summary, write diagnostics to
stderr, and exit 1. See [inspection](Inspection.md) for the field meanings, exact
Unicode ordering and schema 1 evolution policy.

```sh
liquid analyze page.liquid --syntax-mode strict2 --format json
printf '{{ name | upcase }}' | liquid analyze -
```
