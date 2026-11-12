// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict Shopify loop and case headers")
struct LoopHeaderDiagnosticTests {
    @Test func missingInAndTrailingPipesUseReferenceDiagnostics() throws {
        let samples = [
            ("{% for x %}{% endfor %}", "For loops require an 'in' clause"),
            ("{% for x of %}{% endfor %}", "For loops require an 'in' clause"),
            ("{% tablerow x %}{% endtablerow %}", "For loops require an 'in' clause"),
            ("{% tablerow x of %}{% endtablerow %}", "For loops require an 'in' clause"),
            ("{% for x in xs | %}{% endfor %}", "Expected end_of_string but found pipe"),
            ("{% tablerow x in xs | %}{% endtablerow %}", "Expected end_of_string but found pipe"),
            ("{% case x | %}{% endcase %}", "Expected end_of_string but found pipe"),
            ("{% case x %}{% when x | %}{% endcase %}", "Expected end_of_string but found pipe")
        ]
        for (source, expected) in samples {
            do {
                _ = try LiquidTemplate(source, syntaxMode: .strict2)
                Issue.record("Expected rejection: \(source)")
            } catch LiquidError.syntax(let message, let line, _) {
                #expect(message == expected, "\(source): \(message)")
                #expect(line == 1)
            }
        }
    }
}
