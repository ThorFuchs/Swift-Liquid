// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Interpolation compatibility", .timeLimit(.minutes(1)))
struct InterpolationTests {
    @Test(arguments: [false, true], 0..<4)
    func interpolationPreservesBytesTypesMetricsAndQuotas(parsedInput: Bool, policy: Int) async throws {
        let source = "{{ value }}"
        let parsed = try LiquidTemplate(source)
        let cases: [(value: LiquidValue, expected: String, admitted: Int)] = [
            (.string(""), "", 1),
            (.string("Swift"), "Swift", 1),
            (.string("é|e\u{301}|👩‍💻"), "é|e\u{301}|👩‍💻", 1),
            (.string("<&>\"'"), "<&>\"'", 1),
            (.string("A\0B\r\n"), "A\0B\r\n", 1),
            (.integer(9_007_199_254_740_993), "9007199254740993", 1),
            (.integer(Int.min), String(Int.min), 1),
            (.number(5.0), "5.0", 1),
            (.number(1.5), "1.5", 1),
            (.bool(true), "true", 1),
            (.bool(false), "false", 1),
            (.null, "", 1),
            (.array([.string("A"), .integer(2), .bool(false), .null, .string("é")]), "A2falseé", 6),
            (.array([.array([.string("A"), .string("B")])]), "AB", 4),
            (.object(["b": "B", "a": "A"]), "{\"b\"=>B, \"a\"=>A}", 3),
        ]
        for sample in cases {
            let context: LiquidObject = ["value": sample.value]
            func render(_ engine: LiquidEngine) async throws -> (String, LiquidRenderMetrics?) {
                switch policy {
                case 0:
                    let output = try await parsedInput ? engine.render(parsed, context: context) :
                        engine.render(template: source, context: context)
                    return (output, nil)
                case 1:
                    let result = try await parsedInput ? engine.renderWithDiagnostics(parsed, context: context) :
                        engine.renderWithDiagnostics(template: source, context: context)
                    #expect(result.diagnostics.isEmpty)
                    return (result.output, nil)
                case 2:
                    let result = try await parsedInput ? engine.renderWithMetrics(parsed, context: context) :
                        engine.renderWithMetrics(template: source, context: context)
                    #expect(result.diagnostics.isEmpty)
                    return (result.output, result.metrics)
                default:
                    let result = try await parsedInput ? engine.renderWithDiagnosticsAndMetrics(parsed, context: context) :
                        engine.renderWithDiagnosticsAndMetrics(template: source, context: context)
                    #expect(result.diagnostics.isEmpty)
                    return (result.output, result.metrics)
                }
            }
            let byteCount = sample.expected.utf8.count
            let engine = LiquidEngine(limits: .init(outputBytes: max(1, byteCount)))
            let (output, metrics) = try await render(engine)
            #expect(Array(output.utf8) == Array(sample.expected.utf8))
            if let metrics {
                #expect(metrics.outputBytes == byteCount && metrics.sourceBytes == source.utf8.count)
                #expect(metrics.renderSteps == 2 && metrics.admittedValues == sample.admitted)
                #expect(metrics.loopIterations == 0)
                #expect((metrics.parseDuration == nil) == parsedInput)
            }
            if byteCount > 1 {
                do {
                    _ = try await render(LiquidEngine(limits: .init(outputBytes: byteCount - 1)))
                    Issue.record("Interpolation exceeded its exact UTF-8 output capacity")
                } catch {
                    guard case LiquidError.limitExceeded(let name) = error else { throw error }
                    #expect(name == "outputBytes")
                }
            }
        }
    }

    @Test func concurrentRendersKeepImmediateTemplatesInvocationOwned() async throws {
        let source = "A{{ value }}B"
        let parsed = try LiquidTemplate(source)
        let engine = LiquidEngine(limits: .init(sourceBytes: source.utf8.count, outputBytes: 8,
            loopIterations: 1, nestingDepth: 8, renderSteps: 4, contextValues: 1))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<64 {
                group.addTask {
                    let value = "\(index):e\u{301}"
                    let context: LiquidObject = ["value": .string(value)]
                    let expected = Array(("A" + value + "B").utf8)
                    let ordinary = try await engine.render(parsed, context: context)
                    #expect(Array(ordinary.utf8) == expected)
                    let diagnostic = try await engine.renderWithDiagnostics(template: source, context: context)
                    #expect(Array(diagnostic.output.utf8) == expected && diagnostic.diagnostics.isEmpty)
                    let measured = try await engine.renderWithMetrics(parsed, context: context)
                    let combined = try await engine.renderWithDiagnosticsAndMetrics(template: source, context: context)
                    for result in [measured, combined] {
                        #expect(Array(result.output.utf8) == expected && result.diagnostics.isEmpty)
                        #expect(result.metrics.sourceBytes == source.utf8.count)
                        #expect(result.metrics.outputBytes == expected.count)
                        #expect(result.metrics.renderSteps == 4 && result.metrics.admittedValues == 1)
                        #expect(result.metrics.loopIterations == 0)
                    }
                    #expect(measured.metrics.parseDuration == nil && combined.metrics.parseDuration != nil)
                }
            }
            try await group.waitForAll()
        }
    }

}
