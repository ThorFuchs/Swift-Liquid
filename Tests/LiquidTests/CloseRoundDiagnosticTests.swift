// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 closing parenthesis expression diagnostics")
struct CloseRoundDiagnosticTests {
    @Test func pinnedExpressionFailuresUseTypedReason() async throws {
        // Original pinned liquid-spec cases; the fixture files remain untouched.
        let sources = [
            "{% assign x = x | x : ) %}", "{% assign x = (1..) %}",
            "{% case ) %}{% endcase %}", "{% case x %}{% when ) %}{% endcase %}",
            "{% cycle x : ) %}", "{% echo x | x : ) %}",
            "{% for x in ) %}{% endfor %}", "{% if ) %}{% endif %}",
            "{% include ) %}", "{% render 'snippet' for ) %}",
            "{% tablerow x in ) %}{% endtablerow %}", "{% unless ) %}{% endunless %}",
            "{{ ) }}", "{{ x | x : (1..) }}"
        ]
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
                    #expect(message == "[:close_round, \")\"] is not a valid expression", "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func modesAndNeighboringSyntaxRetainBehavior() async throws {
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ ) }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: )") }
        }
        do { _ = try LiquidTemplate("{{ x ) }}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        // Pinned Shopify strict2 reports the closing parenthesis at the end check.
        catch LiquidError.syntax(let message, _, _) { #expect(message == "Expected end_of_string but found close_round") }
        #expect(try await LiquidEngine().render(template: "{% for x in (1..3) %}{{ x }}{% endfor %}", syntaxMode: .strict2) == "123")
    }
}
