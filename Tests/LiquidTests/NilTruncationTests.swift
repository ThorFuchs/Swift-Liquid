// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Nil truncation input")
struct NilTruncationTests {
    @Test func nonIntegerLengthsMatchRubyInsidePartials() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for name in ["truncate", "truncatewords"] {
                for argument in ["1.5", "1.0", "'2.0'", "'abc'", "true", "nil"] {
                    let source = "before{{ 'input' | \(name): \(argument) }}after"
                    let result = try await engine.renderWithDiagnostics(template: "{% render 'p' %}", templates: ["p": source], syntaxMode: mode)
                    #expect(result.output.contains("invalid integer"), "\(name) \(argument)")
                    #expect(result.diagnostics.map(\.message) == ["invalid integer"])
                    #expect(result.output.hasPrefix("before") && result.output.hasSuffix("after"))
                }
                #expect(try await engine.render(template: "{{ nil | \(name): 1.5 | default: 'fallback' }}", syntaxMode: mode) == "fallback")
            }
        }
    }
    @Test func nilInputSkipsArgumentCoercion() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for name in ["truncate", "truncatewords"] {
                let source = "{{ nil | \(name): nil }}"
                #expect(try await engine.render(template: source, syntaxMode: mode) == "")
                let recovered = try await engine.renderWithDiagnostics(template: source, syntaxMode: mode)
                #expect(recovered.output == "" && recovered.diagnostics.isEmpty)
                #expect(try await engine.render(template: "{{ nil | \(name): nil | default: 'fallback' }}", syntaxMode: mode) == "fallback")
                await #expect(throws: LiquidError.self) { try await engine.render(template: "{{ 'x' | \(name): nil }}", syntaxMode: mode) }
            }
        }
    }
}
