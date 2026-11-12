// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Computed include references")
struct DynamicIncludeAccessTests {
    @Test func accessNamesResolveAgainstBothTemplateLoaders() async throws {
        let engine = LiquidEngine()
        let source = "{% include item.template, title: item.title %}|{% include choices[1] %}"
        let context: LiquidObject = ["item": ["template": "card", "title": "Widget"], "choices": ["unused", "sidebar"]]
        let registry = try LiquidTemplateRegistry([.init("card", .raw("Card: {{ title }}")), .init("sidebar", .raw("Side"))])
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            let templates = ["card": try LiquidTemplate("Card: {{ title }}", syntaxMode: mode), "sidebar": try LiquidTemplate("Side", syntaxMode: mode)]
            #expect(try await engine.render(parsed, context: context, templates: templates) == "Card: Widget|Side")
            #expect(try await engine.render(parsed, context: context, registry: registry) == "Card: Widget|Side")
            let result = try await engine.renderWithDiagnostics(parsed, context: context, registry: registry)
            #expect(result.output == "Card: Widget|Side" && result.diagnostics.isEmpty)
            let inspection = try engine.inspect(parsed)
            #expect(inspection.hasDynamicPartials)
            #expect(inspection.variableRoots.contains("item") && inspection.variableRoots.contains("choices"))
        }
    }

    @Test func computedNamesKeepExactIdentityAndDoNotRetryVariables() async throws {
        let engine = LiquidEngine()
        let registry = try LiquidTemplateRegistry([.init("é", .raw("A")), .init("e\u{301}", .raw("B"))])
        let source = "{% include settings.name %}"
        #expect(try await engine.render(template: source, context: ["settings": ["name": "e\u{301}"]], registry: registry) == "B")
        let missing = try LiquidTemplateRegistry([.init("real", .raw("WRONG"))])
        await #expect(throws: LiquidError.self) {
            try await engine.render(template: source, context: ["settings": ["name": "alias"], "alias": "real"], registry: missing)
        }
        let literalFirst = try LiquidTemplateRegistry([.init("alias", .raw("LITERAL")), .init("real", .raw("VALUE"))])
        #expect(try await engine.render(template: "{% include alias %}", context: ["alias": "real"], registry: literalFirst) == "LITERAL")
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 0)).render(template: source, context: ["settings": ["name": "é"]], registry: registry)
        }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: source, context: ["settings": ["name": "é"]], registry: registry)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
