// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Map over string values")
struct MapStringCompatibilityTests {
    @Test func stringPropertiesUseSubstringLookupNotReflection() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for key in ["inspect", "__id__", "size"] {
                #expect(try await engine.render(template: "{{ 'foo' | map: '\(key)' }}", syntaxMode: mode) == "")
            }
            #expect(try await engine.render(template: "{{ 'foo' | map: 'o' }}", syntaxMode: mode) == "o")
            #expect(try await engine.render(template: "{{ xs | map: 'o' | join: ',' }}", context: ["xs": ["foo", "bar"]], syntaxMode: mode) == "o,")
        }
    }
}
