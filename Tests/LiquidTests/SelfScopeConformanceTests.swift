// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify self scope")
struct SelfScopeConformanceTests {
    @Test func liveSelfLookupAndShadowing() async throws {
        let engine = LiquidEngine()
        let cases: [(String, LiquidObject, String)] = [
            ("{{ self['product'] }}", ["product": "shoes"], "shoes"),
            ("{{ self[key] }}", ["key": "target", "target": "found it"], "found it"),
            ("{% assign product = 'local' %}{{ self['product'] }}", ["product": "global"], "local"),
            ("{% assign s = self %}{% assign x = 42 %}{{ s.x }}", [:], "42"),
            ("{% assign size = 17 %}{% assign first = 18 %}{% assign last = 19 %}{{ self.size }}|{{ self.first }}|{{ self.last }}", [:], "17|18|19"),
            ("{% assign self = 'hello' %}{{ self }}", [:], "hello"),
            ("{{ self['key'] }}|{{ self.key }}", ["self": ["key": "value"]], "value|value"),
            ("{% if self == self %}true{% else %}false{% endif %}", [:], "true"),
            ("{{ self }}", [:], "Liquid::SelfDrop"),
            ("{{ self.x }}", ["self": .null, "x": 42], "42"),
            ("{% assign self = nil %}{{ self.x }}", ["x": 42], ""),
            ("{{ self.context }}", [:], ""),
            ("{{ self['é'] }}", ["é": "value"], "value")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, input, expected) in cases {
                #expect(try await engine.render(template: source, context: input, syntaxMode: mode) == expected, "\(source)")
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: input) == expected, "\(source)")
            }
        }
    }

    @Test func capturedSelfKeepsOriginAcrossNestedRender() async throws {
        let engine = LiquidEngine()
        let source = "{% assign a = 1 %}{% assign s1 = self %}{% render 'one', outer: s1 %}"
        let partials = ["one": "{% assign a = 2 %}{% assign s2 = self %}{% render 'two', outer: outer, middle: s2 %}",
                        "two": "{% assign a = 3 %}{{ outer.a }}|{{ middle.a }}|{{ self.a }}"]
        #expect(try await engine.render(template: source, templates: partials, syntaxMode: .strict2) == "1|2|3")
        let shadow = "{% assign x = 1 %}{% render 'p', self: self %}"
        #expect(try await engine.render(template: shadow, templates: ["p": "{% assign x = 2 %}{{ self['x'] }}|{{ x }}"], syntaxMode: .strict2) == "1|2")
    }

    @Test func selfScopeIsInvocationOwnedDuringConcurrentRenders() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{% assign s = self %}{{ s.value }}", syntaxMode: .strict2)
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for value in 0..<30 {
                group.addTask { try await engine.render(template, context: ["value": .integer(value)]) == String(value) }
            }
            for try await matched in group { #expect(matched) }
        }
    }
}
