# Local Liquid conformance console

A small browser control center for the existing Shopify `liquid-spec` adapter.
The interface uses HTML, CSS and vanilla JavaScript; its local bridge uses Python's
standard library. The root Swift package still has no dependencies and exposes
only `Liquid` and `liquid`. No Shopify-hosted endpoint is required.

## Run

Use Python 3.9+, Swift 6.4+, Ruby 4.0.1 and clean upstream checkouts at the
[existing pins](../LiquidSpecAdapter/Pins.json). Keep both checkouts outside this
repository. The console verifies their actual HEADs and cleanliness before each run.

```sh
python3 -B Tools/ConformanceConsole/server.py \
  --spec-path /path/to/liquid-spec \
  --reference-path /path/to/Shopify-liquid \
  --ruby /opt/homebrew/opt/ruby/bin/ruby \
  --gem-path /path/to/development/gems
```

Open the private launch URL printed by the server. It sets a local session cookie
and redirects to the console. Choose **Check setup**, then **Run suite**. The
console requires a clean committed source checkout; working edits cannot receive
a source-qualified result. Settings can change the local input paths while idle.

The default address is `127.0.0.1:8765`. `--port 0` selects an available port.
Run records default to `~/Library/Application Support/Swift-Liquid/Conformance`;
`--state-root /private/path` selects another directory outside the checkout.
One console owns that directory at a time. The adapter currently targets macOS;
the console establishes no Linux, Windows, device or minimum-OS runtime claim.

### Development gems

The existing adapter Gemfile and lockfile define the development-only Ruby tools.
Install them into a private directory, using copies of those inputs so Bundler
can add registry checksums without altering the preserved repository lockfile:

```sh
mkdir -p "$HOME/Library/Application Support/Swift-Liquid/bundle-input"
cp Tools/LiquidSpecAdapter/Gemfile Tools/LiquidSpecAdapter/Gemfile.lock \
  "$HOME/Library/Application Support/Swift-Liquid/bundle-input/"
BUNDLE_GEMFILE="$HOME/Library/Application Support/Swift-Liquid/bundle-input/Gemfile" \
BUNDLE_PATH="$HOME/Library/Application Support/Swift-Liquid/gems" \
  bundle install
```

Pass the resulting `gems/ruby/4.0.0` directory in `--gem-path`, together with the
Ruby installation's existing default gem directory if needed, separated by `:`.
The console reports missing versions and never installs or upgrades them itself.
Do not add a frozen-Bundler override to the historical lockfile's empty checksum
entries. Neither Ruby nor these gems become Liquid package dependencies.

## Results and evidence

Each click runs `Scripts/ci.py --lane liquid-spec` with a unique external output
root. It reuses the Swift adapter, Ruby bridge, real pinned upstream comparator,
five functional suites, mode expansion, fixed clock and finite quotas. No case is
retried to obtain a pass; benchmarks and hosted storefront suites are not selected.

The case table supports search, suite/outcome filters and pagination. Select a case
to inspect the original upstream verdict, stricter qualified verdict, parser and
render modes, expected/actual observations, exclusions and Ruby-reference result.
The Evidence tab downloads original receipts, the complete case matrix, diagnostic
ledger, suite accounting, RPC traces and logs. These are data, not executable HTML.

**Conformance failed** means the complete source-bound run retained nonmatching
or operational outcomes. **Runner error**, **Cancelled**, **Timed out** and
**Interrupted** are separate states. Partial checkpoints are not final results.
Excluded variants never count as matches. A completed run is not a complete-core,
performance or release acceptance; the historical failed snapshots stay intact.

The console compares receipt source identities and full inventories to the launch
snapshot, verifies report hashes/accounting, and preserves every run directory.
It does not change fixtures, comparators, exclusions, budgets, parser messages or
reference pins. Stop run signals only the current console's owned process group;
partial outputs remain. Closing the server also drains its own active run.

## Local boundary

The server binds only to IPv4 loopback. A random launch token establishes an
HttpOnly SameSite=Strict cookie; Host/Origin checks and JSON-only mutation routes
reject foreign browser requests. Static assets and downloadable evidence use
fixed routes; arbitrary filesystem browsing and shell commands are not exposed.
Source processes execute with a small explicit environment. Templates do not gain
file or network loaders. This is local development tooling, not an OS sandbox or
a network service to expose through a proxy, port forward or public host.

## Check the tool

```sh
python3.14 -B Scripts/ci.py --lane conformance-console \
  --output-root /private/path/console-checks
```

Use the existing qualification Python 3.14 for the repository-wide workflow and
archive controls in this lane. The console server itself also works with Python
3.9. The controls cover authentication/origin confinement, receipt corruption, original
versus qualified verdicts, explicit exclusions, interrupted runs and deterministic
cancellation of an owned child. Their synthetic inputs are not conformance cases.
See the [architecture](../../Documentation/ConformanceConsole.md) and
[existing adapter limits](../../Documentation/LQ1/ADAPTER_LIMITS.md).
