// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify standard filter coercion")
struct StandardFilterCoercionTests {
    @Test func defaultAndSquishHandleCompositeInputs() async throws {
        let engine = LiquidEngine()
        let input: LiquidObject = ["emptyArray": [], "emptyObject": [:], "falseValue": false,
                                   "items": ["foo", "bar"], "obj": ["foo": "bar"]]
        let cases = [
            ("{{ emptyArray | default: 'fallback', allow_false: true }}", "fallback"),
            ("{{ emptyObject | default: 'fallback', allow_false: true }}", "fallback"),
            ("{{ falseValue | default: 'fallback', allow_false: true }}", "false"),
            ("{{ items | squish }}", "[\"foo\", \"bar\"]"),
            ("{{ obj | squish }}", "{\"foo\"=>\"bar\"}")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: input) == expected)
                let result = try await engine.renderWithDiagnostics(parsed, context: input)
                #expect(result.output == expected && result.diagnostics.isEmpty)
            }
        }
    }

    @Test func scalarSumKeepsIntegerAndFloatIdentity() async throws {
        let engine = LiquidEngine()
        let cases: [(LiquidValue, String)] = [("foo", "0"), ([:], "0"), (nil, "0"), (false, "0"),
                                               ("42", "42"), ("2.5", "2.5"), (0.0, "0.0")]
        for (value, expected) in cases {
            #expect(try await engine.render(template: "{{ x | sum }}", context: ["x": value], syntaxMode: .strict2) == expected)
        }
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 1)).render(template: "{{ x | squish }}", context: ["x": ["a", "b"]]) }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: "{{ x | sum }}", context: ["x": [1, 2]])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
