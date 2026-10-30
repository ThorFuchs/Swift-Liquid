// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 loop attribute diagnostics")
struct LoopAttributeDiagnosticTests {
    @Test func pinnedUnknownAttributesUseShopifyReasons() async throws {
        let cases: [(String, String)] = [
            ("{% for x in x step , %}{% endfor %}", "Invalid attribute in for loop. Valid attributes are limit and offset"),
            ("{% for x in x extra %}{% endfor %}", "Invalid attribute in for loop. Valid attributes are limit and offset"),
            ("{% tablerow x in x step , %}{% endtablerow %}", "Invalid attribute 'step' in tablerow loop. Valid attributes are cols, limit, offset, and range"),
            ("{% tablerow x in x extra %}{% endtablerow %}", "Invalid attribute 'extra' in tablerow loop. Valid attributes are cols, limit, offset, and range")
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
    }

    @Test func validParametersAndOtherModesKeepBehavior() async throws {
        let engine = LiquidEngine()
        #expect(try await engine.render(template: "{% for x in (1..3) limit: 2 %}{{ x }}{% endfor %}", syntaxMode: .strict2) == "12")
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{% for x in x extra %}{% endfor %}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: identifier(extra)") }
        }
    }
}
