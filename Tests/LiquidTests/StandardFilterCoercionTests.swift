// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify standard filter coercion")
struct StandardFilterCoercionTests {
    @Test func invalidSliceArgumentsReportRubyIntegerError() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for source in ["{{ 'hello' | slice: 'no' }}", "{{ 'hello' | slice: missing }}", "{{ 'hello' | slice: 1.5 }}", "{{ 'hello' | slice: 0, 'no' }}"] {
                do {
                    _ = try await engine.render(template: source, syntaxMode: mode)
                    Issue.record("Expected an invalid integer error")
                } catch LiquidError.rendering(let message) {
                    #expect(message == "invalid integer")
                }
                let result = try await engine.renderWithDiagnostics(template: source, syntaxMode: mode)
                #expect(result.diagnostics.map(\.message) == ["invalid integer"])
                #expect(result.output.contains("invalid integer"))
            }
            #expect(try await engine.render(template: "{{ 'hello' | slice: 1, missing }}", syntaxMode: mode) == "e")
        }
    }
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

    @Test func arraySumUsesDecimalInputsBeforeConvertingBackToFloat() async throws {
        let engine = LiquidEngine()
        let cases: [(LiquidValue, String)] = [
            ([0.1, 0.2, -0.3], "0.0"),
            ([0.1, 0.2], "0.3"),
            ([1, 2, 3], "6"),
            ([1, 0.5, "0.25"], "1.75"),
            ([[0.1], [0.2, -0.3]], "0.0")
        ]
        for (value, expected) in cases {
            #expect(try await engine.render(template: "{{ x | sum }}", context: ["x": value], syntaxMode: .strict2) == expected)
        }
        #expect(try await engine.render(template: "{{ x | sum: 'price' }}", context: ["x": [["price": 0.1], ["price": 0.2], ["price": -0.3]]]) == "0.0")
        let tiny = try await engine.render(template: "{{ x | sum }}", context: ["x": [1e-300]])
        #expect(Double(tiny) == 1e-300)
        await #expect(throws: LiquidError.self) {
            try await engine.render(template: "{{ x | sum }}", context: ["x": [.integer(Int.max), 1]])
        }
    }
}
