// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Partial argument syntax")
struct PartialArgumentCompatibilityTests {
    @Test func aliasesAndCommaSeparatedBindings() async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["items": ["a", "b"], "value": "v"]
        let templates = ["p": try LiquidTemplate("{{ prefix }}[{{ item }}]")]
        let registry = try LiquidTemplateRegistry([.init("p", .raw("{{ prefix }}[{{ item }}]"))])
        let cases = [
            ("{% render 'p' for items as item, prefix: '>' %}", ">[a]>[b]"),
            ("{% render 'p' with value as item, prefix: '>' %}", ">[v]"),
            ("{% include 'p' for items as item %}", "[a][b]"),
            ("{% include 'p' with value as item, prefix: '>' %}", ">[v]")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: context, templates: templates) == expected, "\(source)")
                let result = try await engine.renderWithDiagnostics(parsed, context: context, registry: registry)
                #expect(result.output == expected && result.diagnostics.isEmpty, "\(source)")
            }
        }
        let source = "{% render 'p' for items as item, prefix: '>' %}"
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 1)).render(template: source, context: context, registry: registry) }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: source, context: context, registry: registry)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
