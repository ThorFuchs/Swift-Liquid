// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Lax filter scanning")
struct LaxFilterScanningTests {
    @Test func emptyFilterSegmentsAreLaxOnly() async throws {
        let cases = [("{{ 'hello' || upcase }}", "HELLO"), ("{{ 'hello' | }}", "hello"),
                     ("{{ 'hello' | upcase || downcase }}", "hello"), ("{{ 'hello' || }}", "hello"),
                     ("{% assign x = 'hello' | %}{{ x }}", "hello")]
        let engine = LiquidEngine()
        for (source, expected) in cases {
            #expect(try await engine.render(template: source, syntaxMode: .lax) == expected)
            let recovered = try await engine.renderWithDiagnostics(template: source, syntaxMode: .lax)
            #expect(recovered.output == expected && recovered.diagnostics.isEmpty)
            for mode in [LiquidSyntaxMode.strict, .strict2] {
                #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
            }
        }
    }
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
        #expect(try await LiquidEngine().render(template: "{{ 'hi there' | split:\"t\"\" | remove:\"i\" | first }}", syntaxMode: .lax) == "hi ")
        #expect(try await LiquidEngine().render(template: "{{ 'abc' | append:\"x\"\" | append:\"q\" }}", syntaxMode: .lax) == "abcx")
        #expect(try await LiquidEngine().render(template: "{{ 'abc' | append:\"x\"\" | z\" | append: \"q\" }}", syntaxMode: .lax) == "abcxq")
        for mode in [LiquidSyntaxMode.strict, .strict2] {
            #expect(throws: LiquidError.self) { try LiquidTemplate("{{ 'hi there' | split:\"t\"\" | remove:\"i\" | first }}", syntaxMode: mode) }
        }
        #expect(throws: LiquidError.self) { try LiquidTemplate("{{ 'x' | append: 'unterminated }}", syntaxMode: .lax) }
    }
}
