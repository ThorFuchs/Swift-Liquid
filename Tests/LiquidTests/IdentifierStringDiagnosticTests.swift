// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 identifier before string diagnostics")
struct IdentifierStringDiagnosticTests {
    @Test func pinnedStringAfterDotRejectionsUseTypedReason() async throws {
        // Original selected inputs from pinned liquid-spec parser_errors files.
        let sources = ["{% assign x = x | x : x.\"y\" %}",
            "{% case x %}{% when x.\"y\" %}{% endcase %}",
            "{% echo x | x : x.\"y\" %}", "{% if x == x.\"y\" %}{% endif %}",
            "{% include x.\"y\" %}", "{% unless x == x.\"y\" %}{% endunless %}",
            "{{ x.\"y\" }}"]
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
                    #expect(message == "Expected id but found string", "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func otherModesAndValidLookupsRemainUnchanged() async throws {
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ x.\"y\" }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: string(y)") }
        }
        let engine = LiquidEngine()
        #expect(try await engine.render(template: "{{ x['y'] }}|{{ x.y }}", context: ["x": ["y": "ok"]], syntaxMode: .strict2) == "ok|ok")
        do { _ = try LiquidTemplate("{{ x. }}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, _, _) { #expect(message == "Expected id but found end_of_string") }
    }
}
