// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Lax unknown condition operators")
struct LaxUnknownConditionTests {
    @Test func recoveryAndShortCircuitMatchRuby() async throws {
        let engine = LiquidEngine()
        let blank = try await engine.renderWithDiagnostics(template: "{% if true true %}{% endif %}", syntaxMode: .lax)
        #expect(blank.output == "")
        #expect(blank.diagnostics.map(\.message) == ["Unknown operator true"])
        let nonblank = try await engine.renderWithDiagnostics(template: "{% if true true %}{% else %}1{% endif %}", syntaxMode: .lax)
        #expect(nonblank.output.contains("Unknown operator true"))
        #expect(try await engine.render(template: "{% if true %}a{% elsif true true %}b{% endif %}", syntaxMode: .lax) == "a")
        let alternate = try await engine.renderWithDiagnostics(template: "{% if false %}a{% elsif true true %}b{% endif %}", syntaxMode: .lax)
        #expect(alternate.output.contains("Unknown operator true"))
        #expect(try await engine.render(template: "{% if dynamic and true true %}a{% else %}b{% endif %}", context: ["dynamic": false], syntaxMode: .lax) == "b")
        #expect(try await engine.render(template: "{% if true or 1 < 'x' %}yes{% endif %}", syntaxMode: .strict2) == "yes")
        #expect(try engine.inspect(template: "{% if customer unknown other %}x{% endif %}", syntaxMode: .lax).variableRoots == ["customer", "other"])
        let equals = try await engine.renderWithDiagnostics(template: "{% if 0 = 0 %}NOPE{% endif %}", syntaxMode: .lax)
        #expect(equals.output.contains("Unknown operator ="))
        for mode in [LiquidSyntaxMode.strict, .strict2] {
            #expect(throws: LiquidError.self) { try LiquidTemplate("{% if true true %}x{% endif %}", syntaxMode: mode) }
        }
    }
}
