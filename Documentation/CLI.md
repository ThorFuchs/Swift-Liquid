# CLI reference

Build with `swift build -c release`. The executable product is `liquid`.
Use `swift run liquid --help` while developing, or the built release executable.

| Command | Behavior |
| --- | --- |
| `render TEMPLATE` | Render a UTF-8 file or `-` for stdin |
| `validate TEMPLATE` | Parse a UTF-8 template and fail on invalid syntax |
| `--version` | Show the development version |
| `--help` | Show commands and options |

Render options:

| Option | Behavior |
| --- | --- |
| `--data PATH` | Read a JSON object as the context |
| `--partials DIRECTORY` | Load `.liquid` files recursively under one explicit directory |
| `--output PATH` | Atomically write completed output to a file |
| `--syntax-mode lax\|strict\|strict2` | Select parsing behavior; default lax |
| `--strict-filters` | Fail on unknown filters |

The CLI emits only rendered content on stdout. Successful validation prints
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
