# Changelog

## Unreleased

- Extract a focused Liquid runtime from RhoeLiquid under Apache-2.0.
- Introduce one public Liquid library and a liquid command-line tool.
- Add checked Sendable values, ordered objects, reusable templates, and explicit partials.
- Pin the independent 1,098-case Golden Liquid corpus with its MIT license.
- Establish Swift 6.4 builds, consumer qualification, DocC, and release benchmarks.
- Match date input coercion, RFC/asctime and ordinal parsing, fixed offsets, exact
  parsed fractional precision, proleptic Gregorian dates, and strftime flags.
- Add 122 date compatibility probes and operational limit regressions.
- Report recovered reference errors separately instead of counting them as renders.
- Compare fixture outputs as UTF-8 and keep operational failures distinct from language errors.
- Add a date workload to the release benchmark package.
