// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 punctuation and rejection order")
struct Strict2PunctuationTests {
    @Test func originalEarlierCommaRejectionsRetainPriority() async throws {
        // Original pinned liquid-spec parser_errors sources.
        let sources = ["{% assign x = x | x : x , , - %}",
            "{% assign x = x | x : x , , x : ? %}",
            "{% case x %}{% when x , , - %}{% endcase %}",
            "{% cycle x : x , , ? %}", "{% echo x | x : x , , ? %}",
            "{{ x | x : x , , - }}", "{{ x | x : x , , x : ? }}"]
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
                    #expect(message == "[:comma, \",\"] is not a valid expression", "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func directAndTrailingPunctuationUseTypedReason() throws {
        let cases: [(String, String)] = [
            ("{{ ? }}", "[:question, \"?\"] is not a valid expression"),
            ("{{ - }}", "[:dash, \"-\"] is not a valid expression"),
            ("{{ x ? }}", "Expected end_of_string but found question"),
            ("{% assign x = x - %}", "Expected end_of_string but found dash")
        ]
        for (source, expected) in cases {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == expected, "\(source)") }
        }
    }

    @Test func lexicalErrorsAndOtherModesRetainBoundaries() async throws {
        do { _ = try LiquidTemplate("{{ x | x: x,, ? $ }}", syntaxMode: .strict2); Issue.record("Expected lexical rejection") }
        catch LiquidError.syntax(let message, _, _) { #expect(message.contains("Unexpected character $")) }
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ ? }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message.contains("Unexpected character")) }
        }
        #expect(try await LiquidEngine().render(template: "{{ 'a?' }}|{{ -5 }}", syntaxMode: .strict2) == "a?|-5")
        #expect(try await LiquidEngine().render(template: "{{- 'a' -}}", syntaxMode: .strict2) == "a")
    }
}
