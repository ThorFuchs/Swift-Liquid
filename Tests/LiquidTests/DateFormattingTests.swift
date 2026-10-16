// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import Liquid

private struct ScalarFormatCase: Sendable {
    let format: String
    let output: String
    let steps: Int
}

@Suite("Date directive compatibility", .timeLimit(.minutes(1)))
struct DateFormattingTests {
    @Test(arguments: [
        ScalarFormatCase(format: "%F %T", output: "1970-01-01 00:00:00", steps: 3),
        ScalarFormatCase(format: "e\u{301}|%Y", output: "e\u{301}|1970", steps: 4),
        ScalarFormatCase(format: "👩‍💻%F", output: "👩‍💻1970-01-01", steps: 4),
        ScalarFormatCase(format: "%\u{301}A", output: "%\u{301}A", steps: 2),
        ScalarFormatCase(format: "%É%K%😀", output: "%É%K%😀", steps: 3),
        ScalarFormatCase(format: "%^B|%#b|%Ob", output: "JANUARY|JAN|%Ob", steps: 5),
        ScalarFormatCase(format: "%_5d|%-5d|%05d", output: "    1|1|00001", steps: 5),
        ScalarFormatCase(format: "%:z|%::z|%:::z", output: "+00:00|+00:00:00|+00", steps: 5),
        ScalarFormatCase(format: "%3N|%12N|%L", output: "123|123456789000|123", steps: 5),
        ScalarFormatCase(format: "%E", output: "%E", steps: 1),
        ScalarFormatCase(format: "%%|%q|%:::Q", output: "%|%q|%:::Q", steps: 5),
        ScalarFormatCase(format: "\0|%Y\r\n", output: "\0|1970\r\n", steps: 5),
    ])
    private func scalarDirectivesRetainBytesBudgetsAndCancellation(_ fixture: ScalarFormatCase) async throws {
        let date = try LiquidDate(seconds: 0, fraction: "123456789")
        let capacity = fixture.output.utf8.count
        let limits = LiquidLimits(outputBytes: capacity, renderSteps: fixture.steps)
        let budget = RuntimeBudget(limits)
        let output = try renderStrftime(fixture.format, date: date, budget: budget)
        #expect(Array(output.utf8) == Array(fixture.output.utf8))
        #expect(budget.remainingSteps == 0 && budget.activeDepth == 0)
        #expect(budget.remainingValues == limits.contextValues && budget.remainingIterations == limits.loopIterations)
        #expect(throws: LiquidError.limitExceeded("outputBytes")) {
            try renderStrftime(fixture.format, date: date,
                budget: RuntimeBudget(.init(outputBytes: capacity - 1)))
        }
        let worker = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let cancelled = RuntimeBudget(.init(outputBytes: 1))
            defer { #expect(cancelled.remainingSteps == cancelled.limits.renderSteps) }
            return try renderStrftime(fixture.format, date: date, budget: cancelled)
        }
        defer { worker.cancel() }
        await #expect(throws: CancellationError.self) { try await worker.value }

        let engine = LiquidEngine()
        let context: LiquidObject = ["stamp": "1970-01-01T00:00:00.123456789Z", "format": .string(fixture.format)]
        let parsed = try LiquidTemplate("{{ stamp | date: format }}")
        let direct = try await engine.render(parsed, context: context)
        let measured = try await engine.renderWithDiagnosticsAndMetrics(parsed, context: context)
        #expect(Array(direct.utf8) == Array(fixture.output.utf8))
        #expect(Array(measured.output.utf8) == Array(fixture.output.utf8) && measured.diagnostics.isEmpty)
        #expect(measured.metrics.outputBytes == capacity)
    }

    @Test func concurrentDateFormatsKeepInvocationStateIsolated() async throws {
        let source = "{{ stamp | date: format }}"
        let parsed = try LiquidTemplate(source)
        let engine = LiquidEngine()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<64 {
                group.addTask {
                    let context: LiquidObject = ["stamp": "1970-01-01T00:00:00.123456789Z",
                        "format": .string("\(index):%F %T %N")]
                    let expected = Array("\(index):1970-01-01 00:00:00 123456789".utf8)
                    let ordinary = try await engine.render(parsed, context: context)
                    let diagnostic = try await engine.renderWithDiagnostics(template: source, context: context)
                    let measured = try await engine.renderWithMetrics(parsed, context: context)
                    let combined = try await engine.renderWithDiagnosticsAndMetrics(template: source, context: context)
                    #expect(Array(ordinary.utf8) == expected)
                    #expect(Array(diagnostic.output.utf8) == expected && diagnostic.diagnostics.isEmpty)
                    for result in [measured, combined] {
                        #expect(Array(result.output.utf8) == expected && result.diagnostics.isEmpty)
                        #expect(result.metrics.outputBytes == expected.count)
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}
