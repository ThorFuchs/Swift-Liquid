// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 numeric tag diagnostics")
struct NumericTagDiagnosticTests {
    @Test func pinnedNumbersPreserveTheExpectedToken() async throws {
        let cases = [
            ("{% assign x 42 = x %}", "Expected id but found number"),
            ("{% include x as 42 %}", "Expected id but found number"),
            ("{% render 'snippet' as 42 %}", "Expected id but found number"),
            ("{% include x 42 %}", "Expected end_of_string but found number"),
            ("{% render 'snippet' 42 %}", "Expected end_of_string but found number")
        ]
        let engine = LiquidEngine()
        for (source, expected) in cases {
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
        let tails = [(")", "close_round"), ("]", "close_square"), (":", "colon"),
                     ("-", "dash"), ("(", "open_round"), ("?", "question"), ("'hi'", "string")]
        for (suffix, kind) in tails {
            for source in ["{% include x \(suffix) %}", "{% render 'snippet' \(suffix) %}"] {
                do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
                catch LiquidError.syntax(let message, let line, let column) {
                    #expect(message == "Expected end_of_string but found \(kind)", "\(source)")
                    #expect(line == 1 && column != nil)
                }
            }
        }
    }

    @Test func strictAliasWithoutBindingAndOtherModesStayBounded() throws {
        for source in ["{% include 'snippet' as alias %}", "{% render 'snippet' as alias %}"] {
            _ = try LiquidTemplate(source, syntaxMode: .strict2)
        }
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{% render 'snippet' 42 %}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: number(42.0)") }
        }
    }
}
