// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 trailing token diagnostics")
struct TrailingTokenDiagnosticTests {
    @Test func pinnedTrailingTokensRetainTypedReason() async throws {
        let cases: [(String, String)] = [
            ("{% assign x = x ( %}", "open_round"),
            ("{% capture x ( %}{% endcapture %}", "open_round"),
            ("{% case x %}{% when x ( %}{% endcase %}", "open_round"),
            ("{% if x and x (1, 5) %}{% endif %}", "open_round"),
            ("{% echo x 42 %}", "number"),
            ("{% increment x 'hi' %}", "string"),
            ("{% capture x , %}{% endcapture %}", "comma"),
            ("{% if x and x ] %}{% endif %}", "close_square"),
            ("{{ 'hi' | append, '!' }}", "comma"),
            ("{{ x ( }}", "open_round")
        ]
        let engine = LiquidEngine()
        for (source, token) in cases {
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
                    #expect(message == "Expected end_of_string but found \(token)", "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func validRangeAccessAndOtherModesKeepTheirBehavior() async throws {
        let engine = LiquidEngine()
        #expect(try await engine.render(template: "{% for i in (1..3) %}{{ i }}{% endfor %}", syntaxMode: .strict2) == "123")
        #expect(try await engine.render(template: "{{ x[0] }}", context: ["x": ["ok"]], syntaxMode: .strict2) == "ok")
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{% capture x , %}{% endcapture %}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: ,") }
        }
        do { _ = try LiquidTemplate("{{ x. }}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, _, _) { #expect(message == "Expected id but found end_of_string") }
    }
}
