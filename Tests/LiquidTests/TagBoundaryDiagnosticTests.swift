// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Tag boundary diagnostics")
struct TagBoundaryDiagnosticTests {
    @Test func strict2ReportsShopifyFirstRejection() throws {
        let examples = [
            ("{% capture 42 %}{% endcapture %}", "Expected id but found number"),
            ("{% case x %}{% elsif %}{% endcase %}", "Unknown tag 'elsif'"),
            ("{% for x in y %}{% elsif %}{% endfor %}", "Unknown tag 'elsif'"),
            ("{% endraw %}", "Unknown tag 'endraw'"),
            ("{% endcomment %}", "Unknown tag 'endcomment'"),
            ("{% cycle %}", "Syntax Error in 'cycle'"),
            ("{% include x extra %}", "Expected colon but found end_of_string"),
            ("{% render 'x' extra %}", "Expected colon but found end_of_string"),
            ("{% render %}", "Expected string but found end_of_string"),
            ("{{ x. }}", "Expected id but found end_of_string")
        ]
        for (source, expected) in examples {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection: \(source)") }
            catch LiquidError.syntax(let message, let line, _) {
                #expect(message.contains(expected), "\(source): \(message)")
                #expect(line == 1)
            }
        }
    }
}
