# Public dependency-inspection consumer

This independent Swift 6 package imports only `Liquid`, exercising source and
parsed bundles, capacity configuration, Sendable results, missing/dynamic findings
and cyclic supplied partials. Its host callback must never run.

```sh
swift run --package-path Examples/DependencyConsumer LiquidDependencyConsumer
```

Native and documentation gates run this consumer. See the
[dependency contract](../../Documentation/Dependencies.md).
