// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

private struct CaseEvaluationControl: Sendable {
    let name: String
    let source: String
    let context: LiquidObject
    let partials: [String: String]
    let expected: String
}

// Supplementary public controls; pinned Liquid 4e39ae4 tags/case.rb and
// condition.rb evaluate the left and right expressions for every when.
private let caseEvaluationControls: [CaseEvaluationControl] = [
    .init(name: "original-deferred", source: "{% case x %}{% when null %}A{% assign x = 1 %}{% when null %}B{% when 1 %}C{% endcase %}", context: LiquidObject([.init("x", .null)]), partials: [:], expected: "AC"),
    .init(name: "successive-mutating-whens", source: "{% case x %}{% when 0 %}A{% assign x = 1 %}{% when 1 %}B{% assign x = 2 %}{% when 2 %}C{% else %}E{% endcase %}", context: LiquidObject([.init("x", .integer(0))]), partials: [:], expected: "ABC"),
    .init(name: "comma-body-changes-next-comparison", source: "{% case x %}{% when 0, 1 %}A{% assign x = 1 %}{% else %}E{% endcase %}", context: LiquidObject([.init("x", .integer(0))]), partials: [:], expected: "AA"),
    .init(name: "or-body-changes-next-comparison", source: "{% case x %}{% when 0 or 1 %}A{% assign x = 1 %}{% else %}E{% endcase %}", context: LiquidObject([.init("x", .integer(0))]), partials: [:], expected: "AA"),
    .init(name: "duplicate-null-stops-after-mutation", source: "{% case x %}{% when null, null %}A{% assign x = 1 %}{% else %}E{% endcase %}", context: LiquidObject([.init("x", .null)]), partials: [:], expected: "A"),
    .init(name: "else-before-when-mutates-operand", source: "{% case x %}{% else %}E{% assign x = 1 %}{% when 1 %}B{% else %}Z{% endcase %}", context: LiquidObject([.init("x", .integer(0))]), partials: [:], expected: "EB"),
    .init(name: "preceding-match-suppresses-else", source: "{% case x %}{% when 0 %}A{% assign x = 1 %}{% else %}E{% when 1 %}B{% endcase %}", context: LiquidObject([.init("x", .integer(0))]), partials: [:], expected: "AB"),
    .init(name: "no-when-else", source: "{% case (1..3) %}{% else %}E{% endcase %}", context: LiquidObject([]), partials: [:], expected: "E"),
    .init(name: "no-when-no-body", source: "{% case (1..3) %}{% endcase %}", context: LiquidObject([]), partials: [:], expected: ""),
    .init(name: "dynamic-index-reevaluated", source: "{% case values[index] %}{% when 0 %}A{% assign index = 1 %}{% when 1 %}B{% endcase %}", context: LiquidObject([.init("values", .array([.integer(0), .integer(1)])), .init("index", .integer(0))]), partials: [:], expected: "AB"),
    .init(name: "property-root-reassigned", source: "{% case item.flag %}{% when 0 %}A{% assign item = other %}{% when 1 %}B{% endcase %}", context: LiquidObject([.init("item", .object(LiquidObject([.init("flag", .integer(0))]))), .init("other", .object(LiquidObject([.init("flag", .integer(1))])))]), partials: [:], expected: "AB"),
    .init(name: "include-mutation-visible", source: "{% case x %}{% when 0 %}A{% include \"p\" %}{% when 1 %}B{% endcase %}", context: LiquidObject([.init("x", .integer(0))]), partials: ["p": "{% assign x = 1 %}"], expected: "AB"),
    .init(name: "render-mutation-isolated", source: "{% case x %}{% when 0 %}A{% render \"p\" %}{% when 0 %}B{% endcase %}", context: LiquidObject([.init("x", .integer(0))]), partials: ["p": "P{% assign x = 1 %}"], expected: "APB"),
    .init(name: "capture-mutation-visible", source: "{% case x %}{% when 0 %}A{% capture x %}one{% endcapture %}{% when \"one\" %}B{% endcase %}", context: LiquidObject([.init("x", .integer(0))]), partials: [:], expected: "AB"),
    .init(name: "nested-case-mutation-visible", source: "{% case x %}{% when 0 %}A{% case y %}{% when 1 %}{% assign x = 2 %}{% endcase %}{% when 2 %}B{% endcase %}", context: LiquidObject([.init("x", .integer(0)), .init("y", .integer(1))]), partials: [:], expected: "AB"),
    .init(name: "loop-repeats-local-case", source: "{% for i in (1..2) %}{% assign choice = 0 %}{% case choice %}{% when 0 %}A{% assign choice = 1 %}{% when 1 %}B{% endcase %}{% endfor %}", context: LiquidObject([]), partials: [:], expected: "ABAB"),
    .init(name: "literal-operand-stable", source: "{% case 0 %}{% when 0 %}A{% assign x = 1 %}{% when 0 %}B{% else %}E{% endcase %}", context: LiquidObject([.init("x", .integer(0))]), partials: [:], expected: "AB"),
    .init(name: "unmatched-operand-stays-unmatched", source: "{% case x %}{% when 0 %}A{% assign x = 1 %}{% when 1 %}B{% else %}E{% endcase %}", context: LiquidObject([.init("x", .string("other"))]), partials: [:], expected: "E")
]

private let reevaluatedCaseSource = "{% case x %}{% when null %}A{% assign x = 1 %}{% when null %}B{% when 1 %}C{% else %}E{% endcase %}"

@Suite("Case operand reevaluation", .timeLimit(.minutes(1)))
struct CaseReevaluationTests {
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func caseOperandsReevaluateBeforeEveryComparison(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        for control in caseEvaluationControls {
            let parsed = try LiquidTemplate(control.source, syntaxMode: mode)
            let partials = try control.partials.mapValues { try LiquidTemplate($0, syntaxMode: mode) }
            let outputs = [
                try await engine.render(template: control.source, context: control.context, templates: control.partials, syntaxMode: mode),
                try await engine.render(parsed, context: control.context, templates: partials),
                try await engine.renderWithMetrics(template: control.source, context: control.context, templates: control.partials, syntaxMode: mode).output,
                try await engine.renderWithMetrics(parsed, context: control.context, templates: partials).output
            ]
            for output in outputs { #expect(output.utf8.elementsEqual(control.expected.utf8), "\(control.name)") }
            let recovered = [
                try await engine.renderWithDiagnostics(template: control.source, context: control.context, templates: control.partials, syntaxMode: mode),
                try await engine.renderWithDiagnostics(parsed, context: control.context, templates: partials)
            ]
            for result in recovered {
                #expect(result.output.utf8.elementsEqual(control.expected.utf8), "\(control.name)")
                #expect(result.diagnostics.isEmpty, "\(control.name)")
            }
            let measured = [
                try await engine.renderWithDiagnosticsAndMetrics(template: control.source, context: control.context, templates: control.partials, syntaxMode: mode),
                try await engine.renderWithDiagnosticsAndMetrics(parsed, context: control.context, templates: partials)
            ]
            for result in measured {
                #expect(result.output.utf8.elementsEqual(control.expected.utf8), "\(control.name)")
                #expect(result.diagnostics.isEmpty, "\(control.name)")
            }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func caseMutationPreservesErrorsAndRecovery(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let controls = [
            ("{% case x %}{% when 0 %}A{% assign x = 1 %}{% when 1 %}{{ 1 | divided_by: 0 }}{% endcase %}", ""),
            ("{% case x %}{% when 0 %}A{% assign x = 1 %}{{ 1 | divided_by: 0 }}{% when 1 %}B{% endcase %}", "B")
        ]
        for (source, suffix) in controls {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            await #expect(throws: LiquidError.self) { try await engine.render(template: source, context: ["x": 0], syntaxMode: mode) }
            await #expect(throws: LiquidError.self) { try await engine.render(parsed, context: ["x": 0]) }
            await #expect(throws: LiquidError.self) { try await engine.renderWithMetrics(parsed, context: ["x": 0]) }
            let recovered = try await engine.renderWithDiagnostics(parsed, context: ["x": 0])
            #expect(recovered.output.hasPrefix("A") && recovered.output.hasSuffix(suffix))
            #expect(recovered.diagnostics.count == 1 && recovered.diagnostics[0].line == 1)
            let measured = try await engine.renderWithDiagnosticsAndMetrics(template: source, context: ["x": 0], syntaxMode: mode)
            #expect(measured.output == recovered.output && measured.diagnostics == recovered.diagnostics)
            let root = try LiquidTemplate("{% render 'p' %}Z", syntaxMode: mode)
            await #expect(throws: LiquidError.self) { try await engine.render(root, context: ["x": 0], templates: ["p": parsed]) }
            let partial = try await engine.renderWithDiagnostics(root, context: ["x": 0], templates: ["p": parsed])
            #expect(partial.output.hasPrefix("A") && partial.output.hasSuffix(suffix + "Z"))
            #expect(partial.diagnostics.count == 1 && partial.diagnostics[0].line == 1)
            #expect(partial.diagnostics[0].templateName == "p")
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func reevaluationChargesWorkAndSkipsUnusedOperand(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let one = try LiquidTemplate("{% case x %}{% when 0 %}A{% endcase %}", syntaxMode: mode)
        let two = try LiquidTemplate("{% case x %}{% when 0 %}A{% when 1 %}B{% endcase %}", syntaxMode: mode)
        let first = try await engine.renderWithMetrics(one, context: ["x": 0])
        let second = try await engine.renderWithMetrics(two, context: ["x": 0])
        #expect(first.output == "A" && second.output == "A")
        // One extra comparison evaluates its current left and right operands.
        #expect(second.metrics.renderSteps == first.metrics.renderSteps + 2)
        let exact = LiquidEngine(limits: .init(renderSteps: second.metrics.renderSteps))
        #expect(try await exact.render(two, context: ["x": 0]) == "A")
        let short = LiquidEngine(limits: .init(renderSteps: second.metrics.renderSteps - 1))
        await #expect(throws: LiquidError.self) { try await short.render(two, context: ["x": 0]) }
        await #expect(throws: LiquidError.self) { try await short.renderWithDiagnosticsAndMetrics(two, context: ["x": 0]) }
        let parsed = try LiquidTemplate(reevaluatedCaseSource, syntaxMode: mode)
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 1)).renderWithDiagnostics(parsed, context: ["x": nil])
        }
        #expect(try await LiquidEngine(limits: .init(outputBytes: 2)).render(parsed, context: ["x": nil]) == "AC")
        let noWhen = try LiquidTemplate("{% case (1..3) %}{% else %}E{% endcase %}", syntaxMode: mode)
        let bounded = LiquidEngine(limits: .init(loopIterations: 1))
        #expect(try await bounded.render(noWhen) == "E")
        let used = try LiquidTemplate("{% case (1..3) %}{% when 1 %}A{% endcase %}", syntaxMode: mode)
        await #expect(throws: LiquidError.self) { try await bounded.render(used) }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func concurrentRendersKeepCaseReevaluationInvocationOwned(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let parsed = try LiquidTemplate(reevaluatedCaseSource, syntaxMode: mode)
        let inspection = try engine.inspect(parsed)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<24 {
                group.addTask { () async throws -> Void in
                    let value: LiquidValue = index % 3 == 0 ? .null : index % 3 == 1 ? "other" : 1
                    let expected = index % 3 == 0 ? "AC" : index % 3 == 1 ? "E" : "C"
                    let context: LiquidObject = ["x": value]
                    #expect(try await engine.render(parsed, context: context) == expected)
                    #expect(try await engine.renderWithDiagnostics(parsed, context: context).output == expected)
                    #expect(try await engine.renderWithMetrics(parsed, context: context).output == expected)
                    #expect(try await engine.renderWithDiagnosticsAndMetrics(parsed, context: context).output == expected)
                    #expect(try await engine.render(template: reevaluatedCaseSource, context: context, syntaxMode: mode) == expected)
                    #expect(try engine.inspect(parsed) == inspection)
                }
            }
            try await group.waitForAll()
        }
        #expect(try engine.inspect(parsed) == inspection)
    }

    @Test(arguments: [false, true])
    func cancellationBetweenCaseBranchesKeepsSiblingHealthy(recovering: Bool) async throws {
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for parsedInput in [false, true] {
                let gate = TestSuspensionGate()
                let engine = try LiquidEngine(filters: [LiquidFilter("case_pause") { value, _, _ in
                    await gate.enter()
                    return value
                }])
                let source = "{% case x %}{% when null %}{{ 'A' | case_pause }}{% assign x = 1 %}{% when 1 %}C{% endcase %}"
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                let worker = Task {
                    if parsedInput {
                        if recovering { return try await engine.renderWithDiagnostics(parsed, context: ["x": nil]).output }
                        return try await engine.render(parsed, context: ["x": nil])
                    }
                    if recovering { return try await engine.renderWithDiagnostics(template: source, context: ["x": nil], syntaxMode: mode).output }
                    return try await engine.render(template: source, context: ["x": nil], syntaxMode: mode)
                }
                defer { worker.cancel() }
                try await gate.waitForEntry()
                #expect(try await engine.render(template: reevaluatedCaseSource, context: ["x": nil], syntaxMode: mode) == "AC")
                worker.cancel()
                _ = try await gate.release()
                await #expect(throws: CancellationError.self) { try await worker.value }
                #expect(try await engine.render(parsed, context: ["x": nil]) == "AC")
            }
        }
    }
}
