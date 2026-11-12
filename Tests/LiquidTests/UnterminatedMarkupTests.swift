// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Unterminated outer markup")
struct UnterminatedMarkupTests {
    @Test func originalDelimiterOwnsTheLocation() async throws {
        let cases = [("first\nsecond\n{% if true\n", "Tag '{%' was not properly terminated", 3),
                     ("😀\n{{ x\n", "Variable '{{' was not properly terminated", 2),
                     ("😀\n{{ 'oops\n", "Variable '{{' was not properly terminated", 2),
                     ("😀\n{% assign x = 'oops\n", "Tag '{%' was not properly terminated", 2)]
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, reason, expectedLine) in cases {
                for entry in 0..<3 {
                    do {
                        switch entry {
                        case 0: _ = try LiquidTemplate(source, syntaxMode: mode)
                        case 1: _ = try await engine.render(template: source, syntaxMode: mode)
                        default: _ = try engine.inspect(template: source, syntaxMode: mode)
                        }
                        Issue.record("Expected malformed outer delimiter")
                    } catch LiquidError.syntax(let message, let line, let column) {
                        #expect(message.contains(reason), "\(source)")
                        #expect(line == expectedLine && column == 1, "\(source)")
                    }
                }
            }
        }
        #expect(try await engine.render(template: "{{ '}}' }}", syntaxMode: .strict2) == "}}")
    }

    @Test func sourceBudgetAndCancellationStayTerminal() async throws {
        let source = "{% if true" + String(repeating: " ", count: 2048)
        #expect(throws: LiquidError.self) { try LiquidTemplate(source, limits: .init(sourceBytes: 10)) }
        let task = Task { () throws -> LiquidTemplate in
            withUnsafeCurrentTask { $0?.cancel() }
            return try LiquidTemplate(source)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
