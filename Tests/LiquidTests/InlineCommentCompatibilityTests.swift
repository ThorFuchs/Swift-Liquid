// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify inline comment continuation")
struct InlineCommentCompatibilityTests {
    @Test func invalidContinuationsRetainMarkupLine() async throws {
        let reason = "Syntax error in tag '#' - Each line of comments must be prefixed by the '#' character"
        let cases = [
            ("{% # ok\nfoo %}", 1), ("{% # ok\n# ok\nfoo %}", 1),
            ("{% # ok\n\nfoo %}", 1), ("{% # ok\n \t foo %}", 1),
            ("{% #\nfoo\nbar %}", 2), ("\n{% #\nfoo\nbar %}", 3),
            ("{% # ok\n😀 %}", 1)
        ]
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, expectedLine) in cases {
                for entry in 0..<3 {
                    do {
                        switch entry {
                        case 0: _ = try LiquidTemplate(source, syntaxMode: mode)
                        case 1: _ = try await engine.render(template: source, syntaxMode: mode)
                        default: _ = try engine.inspect(template: source, syntaxMode: mode)
                        }
                        Issue.record("Expected invalid comment: \(source)")
                    } catch LiquidError.syntax(let message, let line, _) {
                        #expect(message == reason, "\(source)")
                        #expect(line == expectedLine, "\(source)")
                    }
                }
            }
        }
    }

    @Test func blankLinesAndFirstMarkupLineAreAccepted() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for source in ["{% # ok\n\n# yes %}X", "{% #\nfoo %}X", "{% #\n\n# yes %}X", "{% # é\n # 😀 %}X", "{%-\n # comment\n\n # continued\n -%}\n\nX"] {
                #expect(try await engine.render(template: source, syntaxMode: mode) == "X", "\(source)")
            }
            #expect(try await engine.render(template: "A{% # comment %}\n X", syntaxMode: mode) == "A\n X")
            #expect(try await engine.render(template: "A{% # comment -%}\n X", syntaxMode: mode) == "AX")
        }
        do { _ = try LiquidTemplate("{% # é\n # 😀 %}\n{{ x & }}", syntaxMode: .strict2); Issue.record("Expected invalid output") }
        catch LiquidError.syntax(_, let line, _) { #expect(line == 3) }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: "{% # ok %}")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
