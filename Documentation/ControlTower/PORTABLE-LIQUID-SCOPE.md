# Portable Liquid scope proposal — SL21-01

Status: **proposed for Control Tower review**, not an approved ADR or release
qualification. The target is the documented open-source Shopify Liquid core
within the value and hosting profile below. Reference behavior is evidence, not
a promise to implement Ruby's object model or Shopify's hosted commerce runtime.
The existing [language](../Language.md), [host-object](../HostObjects.md),
[error](../Errors.md) and [limits and concurrency](../Metrics.md) contracts
remain authoritative for current behavior. Known gaps and the evidence limits
in [SL21-01](SL21-01.md) remain open.

## Profile

- Keep the single `Liquid` library, `liquid` executable and empty root package
  dependency graph. Engines, inputs and templates have checked `Sendable`
  conformance; mutable rendering, quotas and diagnostics belong to an invocation.
- Target the documented standard tags, filters, parsing and recovery modes of
  open-source Liquid as described in the language contract, with pinned Ruby
  Liquid used to examine edge behavior. `warn` parser mode is not supported by
  the current adapter; a documented target is not evidence that every behavior
  is already implemented.
- Host values are typed strings, native-width integers, finite binary doubles,
  booleans, null, arrays and ordered string-keyed objects, subject to the JSON,
  numeric, Unicode, and finite-value rules in the existing contracts. Ruby
  symbols, arbitrary precision integers, binary strings, Ruby Date instances,
  cycles and arbitrary Ruby objects do not acquire faithful equivalents merely
  by stringification or flattening.
- Hosts explicitly supply partials, typed custom filters and the documented
  host-object capabilities. Properties and dynamic families are registered;
  the optional indexer receives keys under the host's own access policy. The
  finite sequences, boxed values and bounded nodes have the specific documented
  operation and scope boundaries, not a general Drop or recursive-object bridge.
  Callbacks are trusted host code; they must enforce their own authority and
  cooperate with cancellation.
- Logical resource limits and cooperative cancellation are part of the Swift
  contract. Ruby resource scores are not interchangeable with Swift quotas,
  and neither quotas nor cancellation guarantee wall-clock time or process memory.
- Ruby class identity, reflection, arbitrary object interoperability, Shopify
  storefront objects, hosted commerce behavior and custom tags are outside
  this proposed core profile. Jekyll compatibility would require a separately
  selected dialect and preferably a separate Swift-Liquid-Jekyll companion;
  this proposal implements neither.

Portable Drop-like semantics may be useful, but a new runtime capability or
widened host abstraction requires a specific proposal and Control Tower
authorization. A fixture-specific transport is eligible only after its exact
object operations, mode, error policy, all other requirements and reference
behavior have been checked. A primitive yielding the same output in one fixture
is not sufficient to establish object equivalence. Conflicts and exclusions are
never passes. The proposal does not assert complete conformance or release readiness.
