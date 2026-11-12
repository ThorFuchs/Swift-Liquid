# Closed system environment

The optional `closedSystemV1` extension adds five explicit properties to a parsed
Liquid template: `.$value`, `.$descriptor`, `.$plain`, `.$htmlText` and `.$html`.
Choose it separately from the Shopify syntax mode. Standard templates keep their
existing grammar and behavior. Bracketed names such as `["$descriptor"]` remain
ordinary object keys.

Construct a `LiquidSystemEnvironment` from resident `LiquidSystemValue` trees,
parse the root with the extension profile, and render it with an exact
`LiquidTemplateRegistry`. Raw registry entries use the root's syntax and
extension profiles; parsed entries must already match both profiles. Admission
checks the complete registry before evaluation. Dependency inspection has a
matching profile-aware overload.

Ordinary selection retains a selected child's own decoration. `.$value`
recursively projects the ordinary value and strips all decorations. Custom
filters receive ordinary inputs and arguments, and their results have no
inherited decoration. Operations that construct a new container do not attach
the original container's descriptor; retained children keep their own. An
unadmitted descriptor is distinct from an admitted empty descriptor. Access to
an unavailable product throws a typed `LiquidSystemError`.

The host supplies resident plain and HTML representations and policy identities.
A context-specific identity is an opaque bounded assertion; Liquid does not
validate Content provenance or certify that output is placed in a safe host
context. The host must determine both. Explicit Liquid escaping still applies
when requested in a template. Caller-supplied unavailability reasons are exposed
in errors and should not contain secrets.

Construction limits count repeated occurrences, and each render owns its own
execution and context budgets. These are logical capacities, not an RSS limit or
a shared Content accounting ledger. Extraction through `.$value` uses the
existing bounded value bridge, including its output-byte limit. Cancellation is
checked at admitted work boundaries. No complete conformance or performance
claim follows from using this extension.
