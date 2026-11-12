// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify nil ordering")
struct NilComparisonTests {
    @Test func specialComparisonLiteralsRemainPredicates() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for left in ["blank", "empty"] {
                for right in ["blank", "empty"] {
                    let source = "{% if \(left) == \(right) %}equal{% else %}different{% endif %}"
                    #expect(try await engine.render(template: source, syntaxMode: mode) == "different")
                    #expect(try await engine.renderWithDiagnostics(template: source, syntaxMode: mode).diagnostics.isEmpty)
                }
            }
            let controls = "{% if '' == empty %}E{% endif %}{% if false == blank %}B{% endif %}{% if empty != blank %}D{% endif %}"
            #expect(try await engine.render(template: controls, syntaxMode: mode) == "EBD")
        }
    }
    @Test func nilRelationalComparisonsAreFalseAcrossPolicies() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for op in ["<", "<=", ">", ">="] {
                for expression in ["null \(op) 10", "10 \(op) null", "nil \(op) nil", "nil \(op) false", "false \(op) nil"] {
                    let source = "{% if \(expression) %}true{% else %}false{% endif %}"
                    let parsed = try LiquidTemplate(source, syntaxMode: mode)
                    #expect(try await engine.render(template: source, syntaxMode: mode) == "false")
                    #expect(try await engine.render(parsed) == "false")
                    let recovered = try await engine.renderWithDiagnostics(parsed)
                    #expect(recovered.output == "false" && recovered.diagnostics.isEmpty)
                    #expect(try await engine.renderWithMetrics(parsed).output == "false")
                }
            }
            #expect(try await engine.render(template: "{% if nil == nil %}T{% endif %}{% if nil != 1 %}T{% endif %}", syntaxMode: mode) == "TT")
            #expect(try await engine.render(template: "{% if 1 < 2 %}T{% endif %}", syntaxMode: mode) == "T")
        }
    }

    @Test func nilOrderingRetainsQuotaAndCancellation() async throws {
        let source = "{% if nil < 1 %}a{% else %}false{% endif %}"
        let tight = LiquidEngine(limits: .init(outputBytes: 4))
        await #expect(throws: LiquidError.self) { try await tight.render(template: source) }
        let worker = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiquidEngine().render(template: source)
        }
        await #expect(throws: CancellationError.self) { try await worker.value }
    }
}
