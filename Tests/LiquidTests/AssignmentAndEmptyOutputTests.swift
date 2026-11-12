// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Assignment diagnostics and blank output")
struct AssignmentAndEmptyOutputTests {
    @Test func emptyOutputKeepsWhitespaceControls() async throws {
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await LiquidEngine().render(template: "A{{}}B", syntaxMode: mode) == "AB")
            #expect(try await LiquidEngine().render(template: "foo {{-}} bar", syntaxMode: mode) == "foobar")
            #expect(try await LiquidEngine().render(template: "A{{  }}B", syntaxMode: mode) == "AB")
        }
    }

    @Test func assignmentPrecheckPresentsOriginalToken() throws {
        let examples = [(" ] ", "Expected id but found close_square"),
                        (" [ ", "Expected id but found open_square"),
                        (" - ", "Expected id but found dash"),
                        (" . ", "Expected id but found dot"),
                        (" == ", "Unexpected character =")]
        for (mark, expected) in examples {
            do { _ = try LiquidTemplate("{% assign x" + mark + "= x %}", syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, let line, _) { #expect(message == expected); #expect(line == 1) }
        }
        do { _ = try LiquidTemplate("{% assign x = = %}", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, let line, _) { #expect(message == "Unexpected character ="); #expect(line == 1) }
    }
}
