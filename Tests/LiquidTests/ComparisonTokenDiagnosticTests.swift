// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 comparison-token diagnostics")
struct ComparisonTokenDiagnosticTests {
    @Test func pinnedComparisonRejectionsUseOriginalSpelling() async throws {
        // Exact inputs and reasons from the pinned parser_errors population.
        let cases: [(String, String)] = [
            ("{% assign x = x == %}", "Expected end_of_string but found comparison"),
            ("{% assign x = x | x : == %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% assign x = == %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% capture x == %}{% endcapture %}", "Expected end_of_string but found comparison"),
            ("{% case == %}{% endcase %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% case x == %}{% endcase %}", "Expected end_of_string but found comparison"),
            ("{% case x %}{% when x == %}{% endcase %}", "Expected end_of_string but found comparison"),
            ("{% case x %}{% when == %}{% endcase %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% cycle x == %}", "Expected end_of_string but found comparison"),
            ("{% cycle x : == %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% cycle == %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% decrement x == %}", "Expected end_of_string but found comparison"),
            ("{% echo x == %}", "Expected end_of_string but found comparison"),
            ("{% echo x | x : == %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% echo == %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% for x in == %}{% endfor %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% for x in x == %}{% endfor %}", "Expected end_of_string but found comparison"),
            ("{% if x == == %}{% endif %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% if == %}{% endif %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% include x for == %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% include x == %}", "Expected end_of_string but found comparison"),
            ("{% include == %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% increment x == %}", "Expected end_of_string but found comparison"),
            ("{% render 'snippet' for == %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% render 'snippet' == %}", "Expected end_of_string but found comparison"),
            ("{% tablerow x in == %}{% endtablerow %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% tablerow x in x == %}{% endtablerow %}", "Expected end_of_string but found comparison"),
            ("{% unless x == == %}{% endunless %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{% unless == %}{% endunless %}", "[:comparison, \"==\"] is not a valid expression"),
            ("{{ x == }}", "Expected end_of_string but found comparison"),
            ("{{ x | x : == }}", "[:comparison, \"==\"] is not a valid expression"),
            ("{{ == }}", "[:comparison, \"==\"] is not a valid expression"),
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

    @Test func comparisonsKeepModesAndByteOrigins() async throws {
        let engine = LiquidEngine()
        for source in ["{% unless x === y %}{% endunless %}", "{% if x === y %}{% endif %}"] {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, let line, let column) {
                #expect(message == "Unexpected character =")
                #expect(line == 1 && column != nil)
            }
        }
        #expect(try await engine.render(template: "{% if 2 == 2 %}yes{% endif %}", syntaxMode: .strict2) == "yes")
        #expect(try await engine.render(template: "{{ '==' }}", syntaxMode: .strict2) == "==")
        for source in ["{{ = }}", "{{ === }}"] {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: ==") }
        }
        // Header errors use their own block-specific reason.
        for (source, expected) in [("{% raw == %}{% endraw %}", "Syntax Error in 'raw'"),
                                   ("{% doc == %}{% enddoc %}", "Syntax Error in 'doc'")] {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message.contains(expected)) }
        }
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ == }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: ==") }
        }
        do { _ = try LiquidTemplate("é 🫧\n{{ == }}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, let line, _) {
            #expect(message == "[:comparison, \"==\"] is not a valid expression")
            #expect(line == 2)
        }
        // Rewritten liquid bodies do not have original-byte token provenance.
        do { _ = try LiquidTemplate("{% liquid\n echo ==\n%}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: ==") }
    }
}
