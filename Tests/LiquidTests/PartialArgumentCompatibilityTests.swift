// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Partial argument syntax")
struct PartialArgumentCompatibilityTests {
    @Test func includeForRendersScalarOnceAndScopesArguments() async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["product": ["title": "Widget"], "entry": "outer", "prefix": "host"]
        let source = "{% include 'p' for product as entry, prefix: '>' %}|{{ entry }}|{{ prefix }}"
        let partial = "{{ prefix }}[{{ entry.title }}]"
        let registry = try LiquidTemplateRegistry([.init("p", .raw(partial))])
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await engine.render(template: source, context: context, registry: registry, syntaxMode: mode) == ">[Widget]|outer|host")
            #expect(try await engine.render(template: source, context: context, templates: ["p": partial], syntaxMode: mode) == ">[Widget]|outer|host")
            let dynamic = "{% assign page = 'product' %}{% include page for product %}"
            #expect(try await engine.render(template: dynamic, context: context, templates: ["product": "{{ product.title }}"], syntaxMode: mode) == "Widget")
            #expect(try await engine.render(template: "{% include 'p' for missing as entry %}", registry: registry, syntaxMode: mode) == "[]")
            let arrayContext: LiquidObject = ["items": [["title": "A"], ["title": "B"]]]
            #expect(try await engine.render(template: "{% include 'p' for items as entry, prefix: '>' %}", context: arrayContext, registry: registry, syntaxMode: mode) == ">[A]>[B]")
        }
    }
    @Test func dynamicIncludeWithUsesResolvedNameAsDefaultAlias() async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["tpl": "product", "featured": "Widget"]
        let source = "{% include tpl with featured, tpl: 'named' %}"
        let partial = "{{ product }}|{{ tpl }}"
        let registry = try LiquidTemplateRegistry([.init("product", .raw(partial))])
        let literalFirst = try LiquidTemplateRegistry([.init("tpl", .raw("literal={{ tpl }}")), .init("product", .raw(partial))])
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await engine.render(template: source, context: context, registry: registry, syntaxMode: mode) == "Widget|named")
            #expect(try await engine.render(template: source, context: context, templates: ["product": partial], syntaxMode: mode) == "Widget|named")
            #expect(try await engine.render(template: source, context: context, registry: literalFirst, syntaxMode: mode) == "literal=Widget")
            let result = try await engine.renderWithDiagnostics(template: source, context: context, registry: registry, syntaxMode: mode)
            #expect(result.output == "Widget|named" && result.diagnostics.isEmpty)
        }
    }
    @Test func laxPartialAttributesIgnoreUnrecognizedPunctuation() async throws {
        let engine = LiquidEngine()
        let partial = "{{ a }}:{{ b }}"
        let registry = try LiquidTemplateRegistry([.init("p", .raw(partial))])
        for tag in ["include", "render"] {
            let source = "{% \(tag) 'p' !!! a: 'A' ~~~ b: 'B' %}"
            #expect(try await engine.render(template: source, registry: registry, syntaxMode: .lax) == "A:B")
            #expect(try await engine.render(template: "{% \(tag) 'p' a: '!' b: '~' %}", registry: registry, syntaxMode: .lax) == "!:~")
            for mode in [LiquidSyntaxMode.strict, .strict2] {
                #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
            }
            #expect(throws: LiquidError.self) { try LiquidTemplate("{% \(tag) !!! 'p' %}", syntaxMode: .lax) }
        }
    }
    @Test func renderForNonEnumerableValuesRendersOnce() async throws {
        let engine = LiquidEngine()
        let partial = "{{ item }}:{{ forloop.index }}"
        let registry = try LiquidTemplateRegistry([.init("p", .raw(partial))])
        let templates = ["p": try LiquidTemplate(partial)]
        let cases: [(String, LiquidObject, String)] = [
            ("{% render 'p' for 'abc' as item %}", [:], "abc:"),
            ("{% render 'p' for missing as item, item: value %}", ["value": "outer"], "outer:"),
            ("{% render 'p' for value as item %}", ["value": 12], "12:"),
            ("{% render 'p' for values as item %}", ["values": []], ""),
            ("{% render 'p' for (1..2) as item %}", [:], "1:12:2"),
            ("{% render 'p' for values as item %}", ["values": ["a", "b"]], "a:1b:2")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, context, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: context, templates: templates) == expected)
                let recovered = try await engine.renderWithDiagnostics(parsed, context: context, registry: registry)
                #expect(recovered.output == expected && recovered.diagnostics.isEmpty)
            }
        }
        let objectPartial = "{{ item[0] }}={{ item[1] }};"
        let objectRegistry = try LiquidTemplateRegistry([.init("p", .raw(objectPartial))])
        let object = LiquidObject([.init("a", 1), .init("b", 2)])
        #expect(try await engine.render(template: "{% render 'p' for values as item %}", context: ["values": .object(object)], registry: objectRegistry) == "a=1;b=2;")
        let scalarSource = "{% render 'p' for 'abc' as item %}"
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 1)).render(template: scalarSource, registry: registry)
        }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: scalarSource, registry: registry)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
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
