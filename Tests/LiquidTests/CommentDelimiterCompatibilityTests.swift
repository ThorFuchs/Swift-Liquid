// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify comment closing tags")
struct CommentDelimiterCompatibilityTests {
    @Test func nestedCommentsInsideLiquidKeepTheOuterCommentOpen() async throws {
        let engine = LiquidEngine()
        let cases = [
            "{% liquid\necho 'A'\ncomment\ncomment\nnested\nendcomment\nstill hidden\nendcomment\necho 'B'\n%}",
            "{% liquid\necho 'A'\ncomment\ncomment extra\nhidden\nendcomment suffix\nstill hidden\nendcomment\necho 'B'\n%}",
            "{% liquid\necho 'A'\ncomment\ncommentary\nendcomment\necho 'B'\n%}"
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for source in cases {
                #expect(try await engine.render(template: source, syntaxMode: mode) == "AB")
            }
            #expect(throws: LiquidError.self) {
                try LiquidTemplate("{% liquid\ncomment\ncomment\nendcomment\n%}", syntaxMode: mode)
            }
        }
    }
    @Test func openingMarkupConsumesTheOuterDelimiterBeforeTheBody() async throws {
        let engine = LiquidEngine()
        let sources = [
            "A{%comment}{% assign a = 1 %}{%endcomment}{% endif %}Z",
            "A{%comment}garbage%}inner{% endcomment %}Z",
            "A{% comment}{%if true%}B{%endcomment%}Z"
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for source in sources {
                #expect(try await engine.render(template: source, syntaxMode: mode) == "AZ")
            }
            #expect(throws: LiquidError.self) { try LiquidTemplate("{% comment}missing close", syntaxMode: mode) }
        }
    }
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

    @Test func openingMarkupAndUnclosedBodyMatchRuby() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await engine.render(template: "a{% comment extra %}hidden{% endcomment %}b", syntaxMode: mode) == "ab")
            #expect(try await engine.render(template: "a{% # hidden %}b", syntaxMode: mode) == "ab")
        }
        for source in ["{% comment extra %}hello", "{% comment %}this is {{{ not }}} valid{{ liquid{% endcomment %}"] {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, let line, _) {
                #expect(message.contains("'comment' tag was never closed"), "\(source): \(message)")
                #expect(line == 1)
            }
        }
    }
}
