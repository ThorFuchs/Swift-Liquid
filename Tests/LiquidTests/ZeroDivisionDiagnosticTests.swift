// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify zero-division diagnostics")
struct ZeroDivisionDiagnosticTests {
    @Test func divisionAndModuloRetainErrorAndRecoveryBoundaries() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for filter in ["divided_by", "modulo"] {
                let source = "before {{ 1 | \(filter): 0 }} after"
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                for parseFirst in [false, true] {
                    do {
                        if parseFirst { _ = try await engine.render(parsed) }
                        else { _ = try await engine.render(template: source, syntaxMode: mode) }
                        Issue.record("Expected zero division")
                    } catch LiquidError.rendering(let message) { #expect(message == "divided by 0") }
                    let result = try await parseFirst ? engine.renderWithDiagnostics(parsed) : engine.renderWithDiagnostics(template: source, syntaxMode: mode)
                    #expect(result.output == "before Liquid error (line 1): divided by 0 after")
                    #expect(result.diagnostics.count == 1 && result.diagnostics.first?.message == "divided by 0")
                }
            }
        }
        let partial = "first\n{{ 1 | divided_by: 0 }}"
        let result = try await engine.renderWithDiagnostics(template: "{% render 'p' %}", templates: ["p": partial])
        #expect(result.output.contains("Liquid error (p line 2): divided by 0"))
        #expect(result.diagnostics.count == 1 && result.diagnostics.first?.line == 2)
    }

    @Test func floatZeroStillFailsAndCancellationRemainsTerminal() async throws {
        let engine = LiquidEngine()
        do { _ = try await engine.render(template: "{{ 1.0 | divided_by: 0.0 }}"); Issue.record("Expected finite-domain rejection") }
        catch LiquidError.rendering(let message) { #expect(message == "divided by 0") }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: "{{ 1 | modulo: 0 }}")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
