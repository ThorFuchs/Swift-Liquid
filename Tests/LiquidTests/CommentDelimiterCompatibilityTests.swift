// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify comment closing tags")
struct CommentDelimiterCompatibilityTests {
    @Test func closingMarkupAndWhitespaceControl() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for suffix in [" extra ", "\nextra ", "\textra ", "\nextra endcomment "] {
                let source = "A{% comment %}hidden{% endcomment" + suffix + "%}Z"
                #expect(try await engine.render(template: source, syntaxMode: mode) == "AZ")
            }
            #expect(try await engine.render(template: "A{% comment %}x{% endcomment extra -%}  Z", syntaxMode: mode) == "AZ")
            #expect(throws: LiquidError.self) { try LiquidTemplate("{% comment %}x{% endcommentExtra %}", syntaxMode: mode) }
            #expect(throws: LiquidError.self) { try LiquidTemplate("{% comment %}x{% endcomment", syntaxMode: mode) }
        }
    }
}
