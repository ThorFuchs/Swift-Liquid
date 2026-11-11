// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Recursive partial operational boundaries")
struct RecursionOperationalEvidenceTests {
    @Test func explicitlySmallCallerLimitRemainsOperationalForBothPolicies() async throws {
        let engine = LiquidEngine(limits: .init(nestingDepth: 8))
        for source in ["{% include 'p' %}", "{% render 'p' %}"] {
            for recover in [false, true] {
                do {
                    if recover { _ = try await engine.renderWithDiagnostics(template: source, templates: ["p": source], syntaxMode: .strict2) }
                    else { _ = try await engine.render(template: source, templates: ["p": source], syntaxMode: .strict2) }
                    Issue.record("Expected caller's nestingDepth limit")
                } catch LiquidError.limitExceeded(let limit) {
                    #expect(limit == "nestingDepth")
                }
            }
        }
    }

    @Test func finiteRecursiveIncludeAndCancellationRetainBehavior() async throws {
        let engine = LiquidEngine()
        let partial = "{% assign n = n | plus: 1 %}{{ n }}{% if n < 3 %}{% include 'p' %}{% endif %}"
        let source = "start{% include 'p' %}done"
        #expect(try await engine.render(template: source, context: ["n": 0], templates: ["p": partial], syntaxMode: .strict2) == "start123done")
        let worker = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: "{% include 'p' %}", templates: ["p": "{% include 'p' %}"], syntaxMode: .strict2)
        }
        await #expect(throws: CancellationError.self) { try await worker.value }
    }
    @Test func shopifyScopeBoundaryAndRecoveredOutput() async throws {
        let engine = LiquidEngine()
        for (tag, expectedLast) in [("include", 99), ("render", 100)] {
            let call = tag == "include" ? "{% include 'p' %}" : "{% render 'p' with n as n %}"
            let recursive = "{{ n }}|{% assign n = n | plus: 1 %}" + call
            let result = try await engine.renderWithDiagnostics(template: "start" + call + "done", context: ["n": 1], templates: ["p": recursive], syntaxMode: .strict2)
            let prefix = "start" + (1...expectedLast).map { "\($0)|" }.joined()
            #expect(result.output.hasPrefix(prefix))
            #expect(result.output.contains("Nesting too deep") && result.output.hasSuffix("done"))
            #expect(result.diagnostics.count == 1)
            do {
                _ = try await engine.render(template: call, context: ["n": 1], templates: ["p": recursive], syntaxMode: .strict2)
                Issue.record("Expected Shopify recursion error")
            } catch LiquidError.rendering(let message) {
                #expect(message.contains("Nesting too deep"))
            }
        }
    }

    @Test func separateRenderAndInputLimitsPreserveExplicitLimits() async throws {
        let standard = LiquidLimits()
        #expect(standard == .default)
        #expect(standard.nestingDepth == 64 && standard.renderingDepth == 384)
        #expect(LiquidLimits(sourceBytes: 262_144, outputBytes: 1_048_576).renderingDepth == 384)
        let explicit = LiquidLimits(nestingDepth: 64)
        #expect(explicit.nestingDepth == 64 && explicit.renderingDepth == 64)
        var modified = standard
        modified.nestingDepth = 8
        #expect(modified.renderingDepth == 8)
        var nested: LiquidValue = "leaf"
        for _ in 0..<200 { nested = .array([nested]) }
        do {
            _ = try await LiquidEngine().render(template: "ok", context: ["deep": nested])
            Issue.record("Expected input depth rejection")
        } catch LiquidError.limitExceeded(let name) { #expect(name == "nestingDepth") }
        var invalid = standard
        invalid.renderingDepth = 385
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: invalid).render(template: "ok") }
        let deep = String(repeating: "{% if true %}", count: 150) + "ok" + String(repeating: "{% endif %}", count: 150)
        do {
            _ = try LiquidTemplate(deep)
            Issue.record("Expected syntax depth rejection")
        } catch LiquidError.limitExceeded(let name) { #expect(name == "nestingDepth") }
        let nestedPartial = String(repeating: "{% if true %}", count: 40) + "{% render 'p' %}" + String(repeating: "{% endif %}", count: 40)
        do {
            _ = try await LiquidEngine().render(template: "{% render 'p' %}", templates: ["p": nestedPartial])
            Issue.record("Expected active rendering depth rejection")
        } catch LiquidError.limitExceeded(let name) { #expect(name == "nestingDepth") }
    }

}
