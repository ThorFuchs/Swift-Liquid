// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Lax output identifiers and filter tails")
struct LaxIdentifierFilterTests {
    @Test func numericWordsAndFilterTailFollowRuby() async throws {
        let engine = LiquidEngine()
        let source = "{% assign 123foo = 'bar' %}{{ 123foo }}"
        #expect(try await engine.render(template: source, syntaxMode: .lax) == "bar")
        #expect(try await engine.render(template: "{{ 123foo.bar }}", context: ["123foo": ["bar": "yes"]], syntaxMode: .lax) == "yes")
        #expect(try await engine.render(template: "{{ 123 }}", syntaxMode: .lax) == "123")
        #expect(try await engine.render(template: "{{ 'X' | downcase) }}", syntaxMode: .lax) == "x")
        for mode in [LiquidSyntaxMode.strict, .strict2] {
            #expect(throws: LiquidError.self) { try LiquidTemplate("{{ 123foo }}", syntaxMode: mode) }
            #expect(throws: LiquidError.self) { try LiquidTemplate("{{ 'X' | downcase) }}", syntaxMode: mode) }
        }
    }
}
