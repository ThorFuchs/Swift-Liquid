// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 invalid expression token diagnostics")
struct ExpressionTokenDiagnosticTests {
    @Test func pinnedOperatorsUseShopifyReasons() async throws {
        // The assign templates are exact inputs from the pinned parser_errors corpus.
        let cases: [(String, String, String)] = [
            ("]", "close_square", "]"), (":", "colon", ":"),
            ("!=", "comparison", "!="), ("<", "comparison", "<"),
            (">", "comparison", ">"), ("<=", "comparison", "<="),
            (">=", "comparison", ">="), ("contains", "comparison", "contains"),
            (".", "dot", "."), ("..", "dotdot", ".."), ("|", "pipe", "|")
        ]
        let engine = LiquidEngine()
        for (token, kind, spelling) in cases {
            let source = "{% assign x = x | x : \(token) %}"
            // The current pinned case and Ruby reference parse a pipe as the
            // next filter boundary, then reject the missing filter name.
            let expected = token == "|" ? "Expected id but found end_of_string" : "[:\(kind), \"\(spelling)\"] is not a valid expression"
            for entry in 0..<4 {
                do {
                    switch entry {
                    case 0: _ = try LiquidTemplate(source, syntaxMode: .strict2)
                    case 1: _ = try await engine.render(template: source, syntaxMode: .strict2)
                    case 2: _ = try await engine.renderWithDiagnostics(template: source, syntaxMode: .strict2)
                    default: _ = try engine.inspect(template: source, syntaxMode: .strict2)
                    }
                    Issue.record("Expected rejection: \(source)")
                } catch LiquidError.syntax(let message, let line, let column) {
                    #expect(message == expected, "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func otherModesAndValidOperatorsRemainUnchanged() async throws {
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ : }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: :") }
        }
        #expect(try await LiquidEngine().render(template: "{% if 1 < 2 %}yes{% endif %}", syntaxMode: .strict2) == "yes")
        #expect(try await LiquidEngine().render(template: "{{ 'ab' | upcase }}", syntaxMode: .strict2) == "AB")
    }
}
