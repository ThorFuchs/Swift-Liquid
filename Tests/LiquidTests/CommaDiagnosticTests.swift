// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Invalid comma expression diagnostics")
struct CommaDiagnosticTests {
    // Original examples from the pinned liquid-spec parser_errors files.
    private let originalSources = [
        "{% assign x = x | x : x , , [0] %}", "{% case , %}{% endcase %}",
        "{% cycle x : x , , [0] %}", "{% echo x | x : x , , [0] %}",
        "{% for x in , %}{% endfor %}", "{% if x == , %}{% endif %}",
        "{% include x for , %}", "{% render 'snippet' for , %}",
        "{% tablerow x in , %}{% endtablerow %}", "{% unless x == , %}{% endunless %}",
        "{{ x | x : x , , [0] }}"
    ]
    @Test func originalPrimaryExpressionFailuresRetainTypedReason() async throws {
        let engine = LiquidEngine()
        for source in originalSources {
            for entry in 0..<4 {
                do {
                    switch entry {
                    case 0: _ = try LiquidTemplate(source, syntaxMode: .strict2)
                    case 1: _ = try await engine.render(template: source, syntaxMode: .strict2)
                    case 2: _ = try await engine.renderWithDiagnostics(template: source, syntaxMode: .strict2)
                    default: _ = try engine.inspect(template: source, syntaxMode: .strict2)
                    }
                    Issue.record("Invalid expression accepted: \(source)")
                } catch LiquidError.syntax(let message, let line, let column) {
                    #expect(message == "[:comma, \",\"] is not a valid expression", "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }
    @Test func neighboringContextsKeepTheirExistingRejectionAndValidCommaSyntax() async throws {
        let engine = LiquidEngine()
        let valid = try LiquidTemplate("{{ 'a,b' | split: ',' | join: ':' }}", syntaxMode: .strict2)
        #expect(try await engine.render(valid) == "a:b")
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ , }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: ,") }
        }
        do { _ = try LiquidTemplate("{{ value, }}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        // Pinned Shopify strict2 rejects the same trailing comma at the end check.
        catch LiquidError.syntax(let message, _, _) { #expect(message == "Expected end_of_string but found comma") }
    }
}
