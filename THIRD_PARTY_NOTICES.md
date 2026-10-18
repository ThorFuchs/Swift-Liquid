# Third-party provenance

The root Apache-2.0 license covers original Swift-Liquid contributions and does
not replace applicable licenses on qualification inputs.

| Material | Pin and terms |
| --- | --- |
| RhoePlatform/RhoeLiquid | Source extraction from `9e52492671bc31741932811fe689a86fed76be69`; Apache-2.0. Original LICENSE and NOTICE retained in Licenses/RhoeLiquid. Changed source carries modification notices. |
| jg-rp/golden-liquid | All 1,098 fixture cases from `65c2f76ea64ef20647c295b000df5fcd9fc471cd`; MIT. Original license and README accompany the corpus. |
| Shopify/liquid | Reference implementation only, `4e39ae4cc3da73921923c0669e0fc84a66b2f696`, version 5.14.0. No Ruby implementation is included in the distributed runtime. |

The root package has no third-party dependencies. Reference clones and build
outputs are not distributed. File-level source adaptations and hashes are
recorded in Documentation/Architecture/ExtractionManifest.json.

Documentation qualification and landing-page tooling adapt Apache-2.0 code from
[ThorFuchs/Swift-JSON](https://github.com/ThorFuchs/Swift-JSON), copyright 2026 Thor
Fuchs. File headers retain that attribution and identify Liquid-specific changes;
the extraction manifest records the adapted source files and their hashes.

The date grammar and missing-component defaults include Swift adaptations of
Ruby Date 3.5.1 (`2b5442d85a97859a680eb4be20c6e1a28f3af282`,
`ext/date/date_parse.c`, coded by Tadayoshi Funaba) and Ruby Time 0.4.2
(`387292f5d2639e7100c2118254047514068da6e4`, `lib/time.rb`). Applicable source
files carry `Apache-2.0 AND BSD-2-Clause` identifiers. The original BSD copyright,
conditions and disclaimer, plus alternative Ruby terms, are retained in
[Licenses/RubyDate](Licenses/RubyDate). No Ruby interpreter is linked or invoked
by the distributed library or CLI.

The complete upstream date test source is preserved as inert fixture text, with
its SHA-256 in the conformance pins. The 337 source-table inputs retain their
line, original expectation, and year-completion metadata. The grammar tests
check the fields consumed by Time.parse; the public date-filter corpus checks
rendering and supported-year failures separately. These inputs carry the
upstream BSD-2-Clause terms. They are never evaluated as Ruby test code.

## Independent liquid-spec development tooling

The optional `Tools/LiquidSpecAdapter` driver uses externally checked out
[Shopify/liquid-spec](https://github.com/Shopify/liquid-spec/tree/84bf25e0edbca5f7e530574788b0f875ab331f50)
and [Shopify/liquid](https://github.com/Shopify/liquid/tree/4e39ae4cc3da73921923c0669e0fc84a66b2f696),
both under MIT. The full reference implementations and complete liquid-spec corpus
remain external. The derived nineteen-case fixture
`Tests/LiquidTests/Fixtures/R6ExpectedTokenCases.json` includes selected original
liquid-spec inputs, provenance and the full upstream MIT notice; it is test data,
not a Ruby runtime dependency.
The local adapter and driver are original Apache-2.0 tooling; their bridge
adaptations and limits are recorded in Documentation/LQ1. Development Ruby gems
are isolated and locked separately. They add no Liquid runtime dependency.
