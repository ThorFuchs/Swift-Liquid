# SL21-02A — reference byte-vector RED gate

This test-first checkpoint records authored quoted-string inputs as explicit
UTF-8 byte arrays. `Scripts/generate_quoted_string_reference.py` generated 96
mode-expanded results from the clean pinned Shopify Liquid 5.14.0 checkout;
it does not evaluate fixture-supplied Ruby. The generated
`Tests/LiquidTests/Fixtures/QuotedStringReferenceCases.json` preserves exact
source and output bytes, parse/render phase and reference error locations.
The Swift public consumer test runs the same records independently in lax,
strict and strict2 and reports Swift parse locations and output bytes.

The checkpoint intentionally precedes the production repair. RED results and
commands are retained outside Git; a passing result is not asserted here.
The original SL21-02 audit and its manifest remain unchanged. The fixture
expectations are reference observations, not rewritten upstream fixtures.
