// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Lax case markup")
struct LaxCaseMarkupTests {
    @Test func retainedLookupAndTrailingTextMatchReference() async throws {
        let engine = LiquidEngine()
        let cases = [
            ("{% case 1 bar %}{% when 1 %}one{% else %}two{% endcase %}", "one"),
            ("{% case 1 %}{% when 1 bar %}one{% else %}two{% endcase %}", "one"),
            ("{% case foo=>bar %}{% when 'baz' %}one{% else %}two{% endcase %}", "one"),
            ("{% case 'baz' %}{% when foo=>bar %}one{% else %}two{% endcase %}", "one"),
            ("{% case foo=bar %}{% when 'baz' %}one{% else %}two{% endcase %}", "one"),
            ("{% case foo => bar %}{% when 'baz' %}one{% else %}two{% endcase %}", "two")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict] {
            for (source, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: ["foo": ["bar": "baz"]]) == expected, "\(source)")
                let result = try await engine.renderWithDiagnostics(parsed, context: ["foo": ["bar": "baz"]])
                #expect(result.output == expected && result.diagnostics.isEmpty)
            }
        }
        for (source, _) in cases {
            #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: .strict2) }
        }
        let inspection = try engine.inspect(template: "{% case foo=>bar %}{% when 'baz' %}yes{% endcase %}", syntaxMode: .lax)
        #expect(inspection.variableRoots.contains("foo"))
    }

    @Test func limitsAndCancellationStayTerminal() async throws {
        let source = "{% case 1 extra %}{% when 1 %}long{% endcase %}"
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 1)).render(template: source) }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiquidEngine().render(template: source)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
