// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 identifier before number diagnostics")
struct IdentifierNumberDiagnosticTests {
    @Test func pinnedRejectionsHaveTypedReason() async throws {
        // Exact inputs selected from the pinned parser_errors corpus.
        let sources = ["{% assign x = x | x : x.123 %}",
            "{% case x %}{% when x.123 %}{% endcase %}", "{% decrement 42 %}",
            "{% echo x.123 %}", "{% if x == x.123 %}{% endif %}",
            "{% include x for x.123 %}",
            "{% tablerow 42 %}{% endtablerow %}", "{{ x | x : x.123 }}"]
        let engine = LiquidEngine()
        for source in sources {
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
                    #expect(message == "Expected id but found number", "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func otherModesAndValidNumericAccessArePreserved() async throws {
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ x.123 }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: number(123.0)") }
        }
        let engine = LiquidEngine()
        #expect(try await engine.render(template: "{{ x[0] }}", context: ["x": ["ok"]], syntaxMode: .strict2) == "ok")
        do { _ = try LiquidTemplate("{{ x. }}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, _, _) { #expect(message == "Expected id but found end_of_string") }
    }
}
