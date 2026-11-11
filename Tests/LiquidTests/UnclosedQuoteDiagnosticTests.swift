// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 first-token unclosed quotes")
struct UnclosedQuoteDiagnosticTests {
    @Test func pinnedQuotesRetainSourceAndRejection() async throws {
        // Exact original templates and expectations from the pinned corpus.
        let cases: [(String, String, Int)] = [
            ("line 1\nline 2\n{{ 'oops }}\n", "Unexpected character", 3),
            ("{% capture \"hello %}{% endcapture %}", "Unexpected character \"", 1),
            ("{% capture 'hello %}{% endcapture %}", "Unexpected character '", 1),
            ("{% case \"hello %}{% endcase %}", "Unexpected character \"", 1),
            ("{% case 'hello %}{% endcase %}", "Unexpected character '", 1),
            ("{% case x %}{% when \"hello %}{% endcase %}", "Unexpected character \"", 1),
            ("{% case x %}{% when 'hello %}{% endcase %}", "Unexpected character '", 1),
            ("{% cycle \"hello %}", "Unexpected character \"", 1),
            ("{% cycle 'hello %}", "Unexpected character '", 1),
            ("{% decrement \"hello %}", "Unexpected character \"", 1),
            ("{% decrement 'hello %}", "Unexpected character '", 1),
            ("{% echo \"hello %}", "Unexpected character \"", 1),
            ("{% echo 'hello %}", "Unexpected character '", 1),
            ("{% for \"hello %}{% endfor %}", "Unexpected character \"", 1),
            ("{% for 'hello %}{% endfor %}", "Unexpected character '", 1),
            ("{% if \"hello %}{% endif %}", "Unexpected character \"", 1),
            ("{% if 'hello %}{% endif %}", "Unexpected character '", 1),
            ("{% include \"hello %}", "Unexpected character \"", 1),
            ("{% include 'hello %}", "Unexpected character '", 1),
            ("{% increment \"hello %}", "Unexpected character \"", 1),
            ("{% increment 'hello %}", "Unexpected character '", 1),
            ("{% tablerow \"hello %}{% endtablerow %}", "Unexpected character \"", 1),
            ("{% tablerow 'hello %}{% endtablerow %}", "Unexpected character '", 1),
            ("{% unless \"hello %}{% endunless %}", "Unexpected character \"", 1),
            ("{% unless 'hello %}{% endunless %}", "Unexpected character '", 1),
            ("{{ \"hello }}", "Unexpected character \"", 1),
            ("{{ 'hello }}", "Unexpected character '", 1),
        ]
        let engine = LiquidEngine()
        for (source, expected, expectedLine) in cases {
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
                    #expect(message.contains(expected), "\(source), entry \(entry): \(message)")
                    #expect(line == expectedLine && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func quoteBoundariesRetainModesAndOriginalSourceOwnership() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ 'unterminated }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, let line, let column) {
                #expect(message == "Unterminated string literal" && line == nil && column == nil)
            }
        }
        #expect(try await engine.render(template: "{{ '}}' }}", syntaxMode: .strict2) == "}}")
        do { _ = try LiquidTemplate("{{ 'unterminated", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, let line, let column) {
            #expect(message == "Unterminated string literal" && line == nil && column == nil)
        }
        do { _ = try LiquidTemplate("{% liquid\n echo 'unterminated\n%}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, let line, let column) {
            #expect(message == "Unterminated string literal" && line == nil && column == nil)
        }
        do { _ = try LiquidTemplate("é 🫧\n{{ 'unterminated }}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, let line, let column) {
            #expect(message.contains("Unexpected character '") && line == 2 && column == 1)
        }
    }
}
