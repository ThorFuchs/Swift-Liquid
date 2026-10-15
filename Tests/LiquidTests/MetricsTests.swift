// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

@Suite("Opt-in render metrics")
struct MetricsTests {
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func sourceAndParsedRenderingPreserveBehavior(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine(referenceTime: Date(timeIntervalSince1970: 1_700_000_000))
        let context: LiquidObject = ["name": "é👩‍💻", "items": [1, 2, 3], "selected": "card"]
        let partials = ["card": "{{ name }}", "unused": "unused source"]
        let parsedPartials = try partials.mapValues { try LiquidTemplate($0, syntaxMode: mode) }
        for source in ["", "é👩‍💻", "{{ name | escape }}", "{% capture x %}abcdef{% endcapture %}Z",
                       "{% for i in items %}{% if i == 2 %}{% continue %}{% endif %}{{ i }}{% if i == 3 %}{% break %}{% endif %}{% endfor %}",
                       "{% include selected %}{% render 'card', name: name %}",
                       "{% liquid\nassign x = name\necho x\n%}{{ 'now' | date: '%F' }}"] {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            let expected = try await engine.render(parsed, context: context, templates: parsedPartials)
            let first = try await engine.renderWithMetrics(template: source, context: context, templates: partials, syntaxMode: mode)
            let second = try await engine.renderWithMetrics(parsed, context: context, templates: parsedPartials)
            let diagnostic = try await engine.renderWithDiagnosticsAndMetrics(parsed, context: context, templates: parsedPartials)
            let diagnosticSource = try await engine.renderWithDiagnosticsAndMetrics(template: source, context: context, templates: partials, syntaxMode: mode)
            #expect(first.output == expected && second.output == expected && diagnostic.output == expected)
            #expect(first.diagnostics.isEmpty && second.diagnostics.isEmpty && diagnostic.diagnostics.isEmpty)
            #expect(first.metrics.parseDuration != nil)
            #expect(first.metrics.parseDuration! >= .zero && first.metrics.totalDuration >= first.metrics.parseDuration!)
            #expect(second.metrics.parseDuration == nil && diagnostic.metrics.parseDuration == nil)
            #expect(second.metrics.totalDuration >= .zero)
            for metrics in [first.metrics, second.metrics, diagnostic.metrics] {
                #expect(metrics.sourceBytes == source.utf8.count + partials.values.reduce(0) { $0 + $1.utf8.count })
                #expect(metrics.outputBytes == expected.utf8.count)
                #expect(metrics.loopIterations == second.metrics.loopIterations)
                #expect(metrics.admittedValues == 6) // name, items with three elements, selected
            }
            #expect(first.metrics.renderSteps == second.metrics.renderSteps)
            #expect(diagnostic.metrics.renderSteps == diagnosticSource.metrics.renderSteps)
        }
    }

    @Test func logicalCountsMatchEnforcedCapacities() async throws {
        let simple = try await LiquidEngine().renderWithMetrics(template: "{{ x }}", context: ["x": 7])
        #expect(simple.metrics.renderSteps == 2)
        #expect(simple.metrics.admittedValues == 1 && simple.metrics.loopIterations == 0)
        let tight = LiquidEngine(limits: .init(renderSteps: 2, contextValues: 1))
        #expect(try await tight.renderWithMetrics(template: "{{ x }}", context: ["x": 7]).output == "7")
        for measured in [false, true] {
            await #expect(throws: LiquidError.self) {
                let engine = LiquidEngine(limits: .init(renderSteps: 1))
                if measured { _ = try await engine.renderWithMetrics(template: "{{ x }}", context: ["x": 7]) }
                else { _ = try await engine.render(template: "{{ x }}", context: ["x": 7]) }
            }
        }
        let engine = try LiquidEngine(filters: [LiquidFilter("host_echo") { value, _, _ in value }])
        let chained = try await engine.renderWithMetrics(template: "{{ x | host_echo | host_echo }}", context: ["x": 7])
        #expect(chained.metrics.admittedValues == 5 && chained.metrics.renderSteps == 12)
        let range = try await engine.renderWithMetrics(template: "{{ (1..3) | host_echo | size }}")
        #expect(range.output == "3" && range.metrics.admittedValues == 8)
        let arguments = try await engine.renderWithMetrics(template: "{{ x | host_echo: false, named: nil }}", context: ["x": [1, 2]])
        #expect(arguments.metrics.admittedValues == 11) // context 3, input 3, arguments 2, result 3
        let loop = try await engine.renderWithMetrics(template: "{% for i in (1..3) %}x{% endfor %}")
        #expect(loop.output == "xxx" && loop.metrics.loopIterations == 3 && loop.metrics.renderSteps == 8)
        let capture = try await engine.renderWithMetrics(template: "{% capture x %}abcdef{% endcapture %}Z")
        #expect(capture.metrics.outputBytes == 1 && capture.metrics.renderSteps == 3)
        let empty = try await engine.renderWithMetrics(template: "")
        #expect(empty.metrics.sourceBytes == 0 && empty.metrics.outputBytes == 0 && empty.metrics.renderSteps == 1)
    }

    @Test func partialsShareCountersAndValueAdmission() async throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("host_echo") { value, _, _ in value }])
        let source = "{{ x | host_echo }}{% render 'part', x: x %}{% include 'part' %}"
        let partials = ["part": "{% for i in (1..2) %}{{ x | host_echo }}{% endfor %}"]
        let result = try await engine.renderWithMetrics(template: source, context: ["x": 1], templates: partials)
        #expect(result.output == "11111")
        #expect(result.metrics.loopIterations == 4 && result.metrics.admittedValues == 11)
        let limited = try LiquidEngine(filters: [LiquidFilter("host_echo") { value, _, _ in value }], limits: .init(contextValues: 10))
        for measured in [false, true] {
            await #expect(throws: LiquidError.self) {
                if measured { _ = try await limited.renderWithMetrics(template: source, context: ["x": 1], templates: partials) }
                else { _ = try await limited.render(template: source, context: ["x": 1], templates: partials) }
            }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func recoveryRemainsExplicit(mode: LiquidSyntaxMode) async throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("fail") { _, _, _ in throw LiquidFilterFailure("bad input") }])
        let source = "A{% assign x = '' | fail %}{% render 'card' %}B"
        let partials = ["card": "{{ '' | fail }}"]
        let ordinary = try await engine.renderWithDiagnostics(template: source, templates: partials, syntaxMode: mode)
        let parsed = try LiquidTemplate(source, syntaxMode: mode)
        let parsedPartials = try partials.mapValues { try LiquidTemplate($0, syntaxMode: mode) }
        for result in [try await engine.renderWithDiagnosticsAndMetrics(template: source, templates: partials, syntaxMode: mode),
                       try await engine.renderWithDiagnosticsAndMetrics(parsed, templates: parsedPartials)] {
            #expect(result.output == ordinary.output && result.diagnostics == ordinary.diagnostics)
            #expect(result.diagnostics.count == 2 && result.diagnostics.last?.templateName == "card")
            #expect(result.metrics.outputBytes == ordinary.output.utf8.count)
        }
        await #expect(throws: LiquidError.self) { try await engine.renderWithMetrics(template: source, templates: partials, syntaxMode: mode) }
        await #expect(throws: LiquidError.self) { try await engine.renderWithMetrics(parsed, templates: parsedPartials) }
    }

    @Test func operationalErrorsReturnNoMeasuredResult() async throws {
        final class HostFailure: Error {}
        let failure = HostFailure()
        let engine = try LiquidEngine(filters: [LiquidFilter("fail") { _, _, _ in throw failure }])
        let parsed = try LiquidTemplate("{{ '' | fail }}")
        for recovering in [false, true] {
            do {
                if recovering { _ = try await engine.renderWithDiagnosticsAndMetrics(parsed) }
                else { _ = try await engine.renderWithMetrics(parsed) }
                Issue.record("Host failure became a measured success")
            } catch { #expect((error as? HostFailure) === failure) }
        }
        for recovering in [false, true] {
            for (limits, source, context) in [
                (LiquidLimits(sourceBytes: 1), "{{ x }}", LiquidObject()),
                (.init(outputBytes: 1), "abc", [:]),
                (.init(loopIterations: 1), "{% for i in items %}x{% endfor %}", ["items": [1, 2, 3]]),
                (.init(renderSteps: 1), "{{ x }}", [:]),
                (.init(contextValues: 1), "{{ x }}", ["x": [1, 2]]),
                (.init(nestingDepth: 1), "{{ x }}", [:]),
                (.init(renderSteps: 0), "", [:]),
                (.default, "{{ x }}", ["x": .number(.nan)]),
                (.default, "{% if %}", [:])
            ] {
                let engine = LiquidEngine(limits: limits)
                await #expect(throws: LiquidError.self) {
                    if recovering { _ = try await engine.renderWithDiagnosticsAndMetrics(template: source, context: context) }
                    else { _ = try await engine.renderWithMetrics(template: source, context: context) }
                }
                if source != "{% if %}" {
                    let parsed = try LiquidTemplate(source)
                    await #expect(throws: LiquidError.self) {
                        if recovering { _ = try await engine.renderWithDiagnosticsAndMetrics(parsed, context: context) }
                        else { _ = try await engine.renderWithMetrics(parsed, context: context) }
                    }
                }
            }
        }
    }

    @Test func suspensionIsInsideTotalDuration() async throws {
        let gate = MetricsGate()
        let engine = try LiquidEngine(filters: [LiquidFilter("wait") { _, _, _ in
            await gate.enter(); return "done"
        }])
        let task = Task { try await engine.renderWithMetrics(template: "{{ '' | wait }}") }
        await gate.waitForEntry()
        let interval = await gate.release()
        let result = try await task.value
        #expect(result.output == "done" && result.metrics.totalDuration >= interval)
    }

    @Test(arguments: [false, true])
    func cancellationSurvivesSuspendingHostCode(recovering: Bool) async throws {
        let gate = MetricsGate()
        let engine = try LiquidEngine(filters: [LiquidFilter("wait") { _, _, _ in
            await gate.enter(); throw LiquidFilterFailure("must not recover cancellation")
        }])
        let parsed = try LiquidTemplate("{{ '' | wait }}")
        let task = Task {
            if recovering { return try await engine.renderWithDiagnosticsAndMetrics(parsed) }
            return try await engine.renderWithMetrics(parsed)
        }
        await gate.waitForEntry()
        task.cancel()
        _ = await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.renderWithMetrics(template: "")
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    @Test func concurrentRendersKeepMetricsInvocationOwned() async throws {
        let root = try LiquidTemplate("{% increment n %}:{{ x | scoped }}{% render 'part', count: count %}")
        let partials = ["part": try LiquidTemplate("{% for i in (1..count) %}x{% endfor %}")]
        let first = try LiquidEngine(filters: [LiquidFilter("scoped") { value, _, _ in await Task.yield(); return value }], limits: .init(renderSteps: 200))
        let second = try LiquidEngine(filters: [LiquidFilter("scoped") { value, _, _ in await Task.yield(); return value }], limits: .init(renderSteps: 1000))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 1...48 {
                group.addTask {
                    let count = index % 3 + 1
                    let context: LiquidObject = ["x": .integer(index), "count": .integer(count)]
                    let a = try await first.renderWithMetrics(root, context: context, templates: partials)
                    let b = try await second.renderWithDiagnosticsAndMetrics(root, context: context, templates: partials)
                    let bNormal = try await second.renderWithMetrics(root, context: context, templates: partials)
                    #expect(a.output == "0:\(index)" + String(repeating: "x", count: count))
                    #expect(a.output == b.output && a.diagnostics.isEmpty && b.diagnostics.isEmpty)
                    #expect(a.metrics.loopIterations == count && b.metrics.loopIterations == count)
                    #expect(a.metrics.renderSteps == bNormal.metrics.renderSteps && a.metrics.admittedValues == 4)
                    #expect(b.metrics.admittedValues == 4 && b.metrics.renderSteps > 0)
                    #expect(try await first.render(root, context: context, templates: partials) == a.output)
                }
            }
            try await group.waitForAll()
        }
    }
}

private actor MetricsGate {
    private var start: ContinuousClock.Instant?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    func enter() async {
        start = ContinuousClock().now
        for waiter in waiters { waiter.resume() }
        waiters = []
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForEntry() async {
        if start == nil { await withCheckedContinuation { waiters.append($0) } }
    }
    func release() -> Duration {
        let interval = start!.duration(to: ContinuousClock().now)
        continuation?.resume(); continuation = nil
        return interval
    }
}
