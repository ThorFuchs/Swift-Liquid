// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 inline hash tokenization")
struct InlineHashDiagnosticTests {
    @Test func strict2MarkupRejectsOriginalHash() async throws {
        // Original selected liquid-spec mutations from the pinned corpus.
        let sources = ["{% assign x = x | x : x , , # %}", "{% assign x = # %}",
            "{% case # %}{% endcase %}", "{% echo # %}",
            "{% for x in # %}{% endfor %}", "{% if # %}{% endif %}",
            "{% include # %}", "{% render 'snippet' for # %}", "{% unless # %}{% endunless %}"]
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
                    Issue.record("Expected lexical rejection: \(source)")
                } catch LiquidError.syntax(let message, let line, let column) {
                    #expect(message.contains("Unexpected character #"), "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func commentTagsQuotedHashesAndLegacyModesRemainValid() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await engine.render(template: "{% # a comment %}{{ '#' }}", syntaxMode: mode) == "#")
            #expect(try await engine.render(template: "{% liquid\nassign x = 1\n# comment\necho x\n%}", syntaxMode: mode) == "1")
        }
        #expect(try await engine.render(template: "{% assign x = 1 # comment %}{{ x }}", syntaxMode: .lax) == "1")
    }
}
