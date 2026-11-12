// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Partial interrupt boundaries")
struct PartialInterruptCompatibilityTests {
    @Test func renderContainsSignalsAndIncludePropagatesThem() async throws {
        let engine = LiquidEngine()
        let sources = [
            ("{% for i in (1..3) %}{{ i }}{% render 'p' %}{{ i }}{% endfor %}", "{% break %}", "112233"),
            ("{% for i in (1..3) %}{{ i }}{% render 'p' %}{{ i }}{% endfor %}", "{% continue %}", "112233"),
            ("{% for i in (1..3) %}{{ i }}{% include 'p' %}{{ i }}{% endfor %}", "{% break %}", "1"),
            ("{% for i in (1..3) %}{{ i }}{% include 'p' %}{{ i }}{% endfor %}", "{% continue %}", "123"),
            ("{% for i in (1..2) %}{{ i }}{% render 'p' %}{{ i }}{% endfor %}", "before{% break %}after", "1before12before2"),
            ("{% if true %}start{% break %}end{% endif %}after", "", "start")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, partial, expected) in sources {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                let templates = ["p": try LiquidTemplate(partial, syntaxMode: mode)]
                #expect(try await engine.render(parsed, templates: templates) == expected, "\(source)")
                let result = try await engine.renderWithDiagnostics(parsed, templates: templates)
                #expect(result.output == expected && result.diagnostics.isEmpty, "\(source)")
                #expect(try await engine.renderWithMetrics(parsed, templates: templates).output == expected)
            }
        }
    }

    @Test func renderForAndExactRegistryStayIsolated() async throws {
        let registry = try LiquidTemplateRegistry([.init("p", .raw("{{ p }}{% break %}ignored"))])
        let engine = LiquidEngine()
        let source = "{% render 'p' for values %}done"
        #expect(try await engine.render(template: source, context: ["values": [1, 2]], registry: registry) == "12done")
        #expect(try await engine.renderWithDiagnostics(template: source, context: ["values": [1, 2]], registry: registry).output == "12done")
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 2)).render(template: source, context: ["values": [1, 2]], registry: registry)
        }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: source, context: ["values": [1, 2]], registry: registry)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
