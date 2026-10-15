// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

private actor ExplicitReleaseGate {
    private let arrival = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var exited = false
    private(set) var laterCalls = 0

    func enter() async {
        await withCheckedContinuation { pending in
            continuation = pending
            arrival.continuation.yield(()); arrival.continuation.finish()
        }
        exited = true
    }
    func wait() async -> Bool {
        var iterator = arrival.stream.makeAsyncIterator()
        return await iterator.next() != nil
    }
    func finished() { arrival.continuation.finish() }
    func release() { continuation?.resume(); continuation = nil }
    func later() { laterCalls += 1 }
}

@Suite(.timeLimit(.minutes(1)))
struct CancellationMaintenanceTests {
    @Test(arguments: [false, true], 0..<8)
    func cancellationWaitsForUncooperativeHostAndPreservesReuse(parsedInput: Bool, scenario: Int) async throws {
        let policy = scenario % 4
        let throwsFailure = scenario >= 4
        let gate = ExplicitReleaseGate()
        let engine = try LiquidEngine(filters: [
            LiquidFilter("host_pause") { value, _, _ in
                await gate.enter()
                if throwsFailure { throw LiquidFilterFailure("Cancellation must take precedence") }
                return value
            },
            LiquidFilter("after_pause") { value, _, _ in await gate.later(); return value }
        ])
        let source = "{{ 'value' | host_pause | after_pause }}"
        let parsed = try LiquidTemplate(source)
        let worker = Task {
            do {
                let output: String
                switch policy {
                case 0: output = try await parsedInput ? engine.render(parsed) : engine.render(template: source)
                case 1: output = try await parsedInput ? engine.renderWithDiagnostics(parsed).output : engine.renderWithDiagnostics(template: source).output
                case 2: output = try await parsedInput ? engine.renderWithMetrics(parsed).output : engine.renderWithMetrics(template: source).output
                default: output = try await parsedInput ? engine.renderWithDiagnosticsAndMetrics(parsed).output : engine.renderWithDiagnosticsAndMetrics(template: source).output
                }
                await gate.finished(); return output
            } catch { await gate.finished(); throw error }
        }
        defer { worker.cancel() }
        guard await gate.wait() else {
            worker.cancel(); await gate.release(); _ = try? await worker.value
            Issue.record("Render finished before entering host callback"); return
        }
        let sibling = try await engine.render(template: "healthy")
        worker.cancel()
        let exitedBeforeRelease = await gate.exited
        await gate.release() // Always release before an assertion can end the test.
        await #expect(throws: CancellationError.self) { try await worker.value }
        #expect(!exitedBeforeRelease)
        #expect(await gate.laterCalls == 0)
        #expect(sibling == "healthy")
        #expect(try await engine.render(template: "reused") == "reused")
    }
}
