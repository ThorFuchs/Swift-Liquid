// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Documentation block closing tags")
struct DocDelimiterCompatibilityTests {
    @Test func closingMarkupIsIgnoredButNamesStayDistinct() async throws {
        let engine = LiquidEngine()
        let endings = ["{% enddoc xyz %}", "{% enddoc\nxyz %}", "{% enddoc\n xyz enddoc %}",
                       "{% enddoc\txyz %}", "{% enddoc {{ x }} %}"]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for end in endings {
                let source = "a{% doc %}123" + end + "b"
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed) == "ab", "\(source)")
                #expect(try await engine.renderWithDiagnostics(parsed).output == "ab")
            }
            #expect(throws: LiquidError.self) { try LiquidTemplate("{% doc %}123{% enddocExtra %}", syntaxMode: mode) }
            #expect(throws: LiquidError.self) { try LiquidTemplate("{% doc %}{% doc %}{% enddoc %}", syntaxMode: mode) }
        }
    }

    @Test func sourceLimitsAndCancellationRemainTerminal() async throws {
        let source = "{% doc %}text{% enddoc xyz %}"
        #expect(throws: LiquidError.self) { try LiquidTemplate(source, limits: .init(sourceBytes: 2)) }
        let task = Task { () throws -> LiquidTemplate in
            withUnsafeCurrentTask { $0?.cancel() }
            return try LiquidTemplate(source)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
