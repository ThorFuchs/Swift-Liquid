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
}
