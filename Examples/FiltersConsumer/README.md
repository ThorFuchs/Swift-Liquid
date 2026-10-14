# Custom filter consumer

This independent package imports only `Liquid`. Run it from the repository root:

```sh
swift run --package-path Examples/FiltersConsumer LiquidFiltersConsumer
```

It checks an engine-scoped typed filter, positional/named arguments, standard
filter composition, and explicit diagnostic recovery. The unchanged neighboring
`Consumer` package continues to qualify the 1.0 public API.

The example also retains a parsed root and partial map across invocations, maps
an application `Article` explicitly to `LiquidValue`, and preserves context entry
order. See [application reuse](../../Documentation/Reuse.md).
