// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Capture scope compatibility")
struct CaptureScopeCompatibilityTests {
    @Test func captureWritesRootButRenderRemainsIsolated() async throws {
        let engine = LiquidEngine()
        let source = "{% assign first = '' %}{% for n in (1..3) %}{% capture first %}{{ n }}{% endcapture %}{% endfor %}{{ first }}"
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await engine.render(template: source, syntaxMode: mode) == "3")
            let root = try LiquidTemplate("{% assign x = 'outer' %}{% render 'p' %}{{ x }}", syntaxMode: mode)
            let partial = try LiquidTemplate("{% for n in (1..2) %}{% capture x %}{{ n }}{% endcapture %}{% endfor %}{{ x }}|", syntaxMode: mode)
            #expect(try await engine.render(root, templates: ["p": partial]) == "2|outer")
        }
        for mode in [LiquidSyntaxMode.lax, .strict] {
            #expect(try await engine.render(template: "{% capture 'var' %}test{% endcapture %}{{ var }}", syntaxMode: mode) == "test")
        }
        #expect(throws: LiquidError.self) { try LiquidTemplate("{% capture 'var' %}test{% endcapture %}", syntaxMode: .strict2) }
    }
}
