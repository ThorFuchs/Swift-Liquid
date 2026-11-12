// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Lax output trailing markup")
struct LaxOutputTailTests {
    @Test func completeLeadingExpressionSurvivesTerminalSuffix() async throws {
        let engine = LiquidEngine()
        for suffix in ["a", "1", "=", "!", "<", ">", "-"] {
            let source = "{{ value \(suffix) }}"
            let parsed = try LiquidTemplate(source, syntaxMode: .lax)
            #expect(try await engine.render(parsed, context: ["value": false]) == "false", "\(source)")
            #expect(try await engine.renderWithDiagnostics(parsed, context: ["value": "ok"]).output == "ok", "\(source)")
            for mode in [LiquidSyntaxMode.strict, .strict2] {
                #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
            }
        }
        #expect(try await engine.render(template: "{{ obj.name ! }}", context: ["obj": ["name": "ok"]]) == "ok")
        #expect(try await engine.render(template: "{{ value | upcase }}", context: ["value": "ok"]) == "OK")
        #expect(throws: LiquidError.self) { try LiquidTemplate("{{ ! }}", syntaxMode: .lax) }
        for suffix in ["a", "1", "=", "<", ">", "!", "-"] {
            for source in ["{% assign x = false \(suffix) %}{{ x }}", "{% liquid assign x = false \(suffix)\n%}{{ x }}"] {
                #expect(try await engine.render(template: source, syntaxMode: .lax) == "false", "\(source)")
                for mode in [LiquidSyntaxMode.strict, .strict2] {
                    #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
                }
            }
        }
        for source in ["{% assign x = ! %}", "{% assign x = false ! true %}", "{% if true ! %}x{% endif %}"] {
            #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: .lax) }
        }
    }

    @Test func boundsAndCancellationRemainTerminal() async throws {
        let source = "{{ value ! }}"
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 1)).render(template: source, context: ["value": "long"]) }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiquidEngine().render(template: source, context: ["value": "ok"])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
