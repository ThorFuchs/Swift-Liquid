// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Lax filter scanning")
struct LaxFilterScanningTests {
    @Test func ignoredJunkAndTrailingQuoteMatchRuby() async throws {
        let examples = [("{{ 'hi there' | split$$$: ' ' | first }}", "hi"),
                        ("{{ 'hi there' | split:'t'\" | reverse | first }}", "here"),
                        ("{{ 'hi there' | split:'t'\" | remove:'i' | first }}", "["),
                        ("{{ 'abc' | append: 'x'\" }}", "abcx")]
        for (source, expected) in examples {
            let actual = try await LiquidEngine().render(template: source, syntaxMode: .lax)
            #expect(actual == expected, "\(source): \(actual)")
            for mode in [LiquidSyntaxMode.strict, .strict2] {
                #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
            }
        }
        #expect(try await LiquidEngine().render(template: "{{ 'hi there' | split:\"t\"\" | reverse | first }}", syntaxMode: .lax) == "here")
        #expect(throws: LiquidError.self) { try LiquidTemplate("{{ 'x' | append: 'unterminated }}", syntaxMode: .lax) }
    }
}
