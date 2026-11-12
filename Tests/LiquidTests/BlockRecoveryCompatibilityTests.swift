// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify control-flow error recovery")
struct BlockRecoveryCompatibilityTests {
    @Test func comparisonsPreserveReasonsAndBlankRecovery() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let source = "before\n{% if 5 > 'x' %}{% assign y = 1 %}{% endif %}after"
            let recovered = try await engine.renderWithDiagnostics(template: source, syntaxMode: mode)
            let reason = "comparison of Integer with String failed"
            #expect(recovered.diagnostics.count == 1)
            #expect(recovered.diagnostics.first?.message == reason)
            #expect(recovered.diagnostics.first?.line == 2)
            #expect(recovered.output == (mode == .strict2 ? "before\nLiquid error (line 2): \(reason)after" : "before\nafter"))
            do { _ = try await engine.render(template: source, syntaxMode: mode); Issue.record("Expected error") }
            catch LiquidError.rendering(let message) { #expect(message == reason) }
            let visible = "{% unless 5 > 'x' %}shown{% endunless %}"
            #expect(try await engine.renderWithDiagnostics(template: visible, syntaxMode: mode).output == "Liquid error (line 1): \(reason)")
            #expect(try await engine.render(template: "{% if 5 > false %}Y{% else %}N{% endif %}", syntaxMode: mode) == "N")
        }
    }

    @Test func loopErrorsRespectModeLocationsAndBudgets() async throws {
        let engine = LiquidEngine()
        let source = "{% for x in (1..3) offset: value %}{% endfor %}"
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let result = try await engine.renderWithDiagnostics(template: source, context: ["value": "bad"], syntaxMode: mode)
            #expect(result.diagnostics.first?.message == "invalid integer")
            #expect(result.diagnostics.first?.line == 1)
            #expect(result.output == (mode == .strict2 ? "Liquid error (line 1): invalid integer" : ""))
        }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: source, context: ["value": 0])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
