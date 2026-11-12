// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify cycle fragment parsing")
struct CycleCompatibilityTests {
    @Test func laxAndStrictUseFirstExpressionPerFragment() async throws {
        let engine = LiquidEngine()
        let cases = [
            ("{% assign n = 'N' %}{% cycle n e: 'a', 'b', 'c' %}", "N"),
            ("{% assign n = 'N' %}{% cycle n e 'a', 'b', 'c' %}", "N"),
            ("{% cycle 'a' 'b', 'c' %}", "a"),
            ("{% cycle name: 'a' 'b', 'c' %}", "a"),
            ("{% cycle name: 'a', 'b' 'c' %}", "a"),
            ("{% cycle 'a', %}", "a")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict] {
            for (source, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed) == expected)
                let result = try await engine.renderWithDiagnostics(parsed)
                #expect(result.output == expected && result.diagnostics.isEmpty)
            }
        }
        for (source, _) in cases.dropLast() {
            #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: .strict2) }
        }
        #expect(try await engine.render(template: "{% cycle 'a', %}", syntaxMode: .strict2) == "a")
    }

    @Test func quotaAndCancellationRemainTerminal() async throws {
        let source = "{% cycle 'abc' extra, 'def' %}"
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 2)).render(template: source) }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiquidEngine().render(template: source)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
