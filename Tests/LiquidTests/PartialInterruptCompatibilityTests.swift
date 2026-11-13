// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Partial interrupt boundaries")
struct PartialInterruptCompatibilityTests {
    @Test func emptyCounterNamesFollowParserModeAndRenderIsolation() async throws {
        let engine = LiquidEngine()
        let cases = [("increment", "010"), ("decrement", "-1-2-1")]
        for mode in [LiquidSyntaxMode.lax, .strict] {
            for (tag, expected) in cases {
                let source = "{% \(tag) %}{% \(tag) %}{% render 'p' %}"
                let result = try await engine.renderWithDiagnostics(template: source, templates: ["p": "{% \(tag) %}"], syntaxMode: mode)
                #expect(result.output == expected && result.diagnostics.isEmpty)
                #expect(try await engine.render(template: source, templates: ["p": "{% \(tag) %}"], syntaxMode: mode) == expected)
            }
        }
        for tag in ["increment", "decrement"] {
            #expect(throws: LiquidError.self) { try LiquidTemplate("{% \(tag) %}", syntaxMode: .strict2) }
        }
    }
    @Test func renderDisallowsIncludeInItsIsolatedSubtree() async throws {
        let engine = LiquidEngine()
        let reason = "include usage is not allowed in this context"
        let source = "{% render 'p' %}|{% include 'ok' %}"
        let partial = "P\n{% include 'ok' %}\nQ"
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            let templates = ["p": try LiquidTemplate(partial, syntaxMode: mode), "ok": try LiquidTemplate("OK", syntaxMode: mode)]
            do { _ = try await engine.render(parsed, templates: templates); Issue.record("Expected forbidden include") }
            catch LiquidError.rendering(let message) { #expect(message == reason) }
            let recovered = try await engine.renderWithDiagnostics(parsed, templates: templates)
            #expect(recovered.output == "P\nLiquid error (p line 2): \(reason)\nQ|OK")
            #expect(recovered.diagnostics.count == 1)
            #expect(recovered.diagnostics.first?.message == reason)
            #expect(recovered.diagnostics.first?.line == 2 && recovered.diagnostics.first?.templateName == "p")
            let registry = try LiquidTemplateRegistry([.init("p", .raw(partial)), .init("ok", .raw("OK"))])
            #expect(try await engine.renderWithDiagnostics(template: source, registry: registry, syntaxMode: mode).output == recovered.output)
            let suffixed = ["p.liquid": partial, "ok.liquid": "OK"]
            let legacySuffix = try await engine.renderWithDiagnostics(template: source, templates: suffixed, syntaxMode: mode)
            #expect(legacySuffix.diagnostics.first?.templateName == "p")
            let suffixRegistry = try LiquidTemplateRegistry([.init("p.liquid", .raw(partial)), .init("ok.liquid", .raw("OK"))])
            let exactSuffix = try await engine.renderWithDiagnostics(template: source, registry: suffixRegistry, syntaxMode: mode)
            #expect(exactSuffix.diagnostics.first?.templateName == "p.liquid")
            let nested = ["p": "{% render 'inner' %}", "inner": "{% include 'ok' %}", "ok": "OK"]
            let nestedResult = try await engine.renderWithDiagnostics(template: "{% render 'p' %}", templates: nested, syntaxMode: mode)
            #expect(nestedResult.diagnostics.first?.templateName == "inner")
            #expect(nestedResult.diagnostics.first?.message == reason)
            let markerSource = "{% render 'p' %}"
            let markerTemplates = ["p": "{% include 'ok', __render_isolated__: true %}", "ok": "bad"]
            let markerResult = try await engine.renderWithDiagnostics(template: markerSource, templates: markerTemplates, syntaxMode: mode)
            #expect(markerResult.diagnostics.first?.message == reason)
            #expect(try await engine.render(template: "{% include 'ok', __render_isolated__: true %}", templates: ["ok": "{{ __render_isolated__ }}"], syntaxMode: mode) == "true")
        }
    }
    @Test func includeForCarriesPriorOutputAndRestoresBindings() async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["items": ["a", "b", "c"], "item": "outer"]
        let source = "{% for outer in (1..2) %}{% include 'p' for items as item %}Z{% endfor %}|{{ item }}"
        let cases = [("{% if item == 'b' %}{% break %}{% endif %}{{ item }}", "a|outer"),
                     ("{{ item }}{% if item == 'b' %}{% continue %}{% endif %}", "abab|outer")]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (partial, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                let templates = ["p": try LiquidTemplate(partial, syntaxMode: mode)]
                #expect(try await engine.render(parsed, context: context, templates: templates) == expected)
                let result = try await engine.renderWithDiagnostics(parsed, context: context, templates: templates)
                #expect(result.output == expected && result.diagnostics.isEmpty)
                let registry = try LiquidTemplateRegistry([.init("p", .parsed(try LiquidTemplate(partial, syntaxMode: mode)))])
                #expect(try await engine.render(parsed, context: context, registry: registry) == expected)
            }
        }
    }
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
