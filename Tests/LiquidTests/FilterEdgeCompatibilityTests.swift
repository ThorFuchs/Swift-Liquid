// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Standard filter edge compatibility")
struct FilterEdgeCompatibilityTests {
    @Test func numericIdentityAndSorting() async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["zero": 0.0, "flag": true, "tiny": 1e-27,
                                     "rows": [["a": 10], ["a": 2]]]
        let cases = [("{{ zero | abs }}", "0.0"), ("{{ flag | round }}", "0"),
                     ("{{ tiny }}", "1.0e-27"),
                     ("{{ rows | sort: 'a' }}", "{\"a\"=>2}{\"a\"=>10}")]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: context) == expected, "\(source)")
                let recovered = try await engine.renderWithDiagnostics(parsed, context: context)
                #expect(recovered.output == expected && recovered.diagnostics.isEmpty)
            }
        }
    }

    @Test func truncateWordsUsesRubyAsciiSeparators() async throws {
        let engine = LiquidEngine()
        let source = "{{ text | truncatewords: 3 }}"
        let input: LiquidValue = .string("There is non\u{202F}breaking space here")
        let result = "There is non\u{202F}breaking..."
        #expect(try await engine.render(template: source, context: ["text": input]) == result)
        #expect(try await engine.render(template: source, context: ["text": "one\r\ntwo\tthree four"]) == "one two three...")
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 2)).render(template: source, context: ["text": input]) }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: source, context: ["text": input])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
