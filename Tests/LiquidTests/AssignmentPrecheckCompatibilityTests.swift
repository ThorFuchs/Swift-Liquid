// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 assignment precheck")
struct AssignmentPrecheckCompatibilityTests {
    @Test func invalidOriginalPrecheckKeepsSourceLocation() async throws {
        let engine = LiquidEngine()
        let cases = ["{% assign x ) = x %}", "{% assign x : = x %}",
                     "{% assign x , = x %}", "{% assign x ( = x %}",
                     "{% assign x | = x %}", "{% assign x ? = x %}",
                     "{% assign x 'hi' = x %}", "{% assign = x %}",
                     "{% assign = = x %}", "{% assign ? = x %}"]
        for source in cases {
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
                    #expect(message.contains("Syntax Error in 'assign'"), "\(source)")
                    #expect(line == 1 && column != nil, "\(source)")
                }
            }
        }
        do { _ = try LiquidTemplate("{% assign 42 = x %}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, let line, _) {
            #expect(message == "Expected id but found number")
            #expect(line == 1)
        }
        #expect(try await engine.render(template: "{% assign @foo = 'ok' %}{{ foo }}", syntaxMode: .strict2) == "ok")
    }
}
