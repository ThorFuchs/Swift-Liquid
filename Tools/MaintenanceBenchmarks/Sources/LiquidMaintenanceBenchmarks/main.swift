// SPDX-License-Identifier: Apache-2.0
import Foundation
import Dispatch
import Liquid

private struct MaintenanceFailure: Error { let message: String }
private enum Policy: String, CaseIterable, Sendable {
    case ordinary, diagnostics, metrics, diagnosticsAndMetrics

    func render(_ engine: LiquidEngine, source: String, parsed: LiquidTemplate,
                reuse: Bool, context: LiquidObject = [:],
                partials: [String: String] = [:], parsedPartials: [String: LiquidTemplate] = [:]) async throws -> String {
        switch self {
        case .ordinary:
            return try await reuse ? engine.render(parsed, context: context, templates: parsedPartials)
                : engine.render(template: source, context: context, templates: partials)
        case .diagnostics:
            let result = try await reuse ? engine.renderWithDiagnostics(parsed, context: context, templates: parsedPartials)
                : engine.renderWithDiagnostics(template: source, context: context, templates: partials)
            guard result.diagnostics.isEmpty else { throw MaintenanceFailure(message: "Unexpected diagnostics") }
            return result.output
        case .metrics:
            return try await reuse ? engine.renderWithMetrics(parsed, context: context, templates: parsedPartials).output
                : engine.renderWithMetrics(template: source, context: context, templates: partials).output
        case .diagnosticsAndMetrics:
            let result = try await reuse ? engine.renderWithDiagnosticsAndMetrics(parsed, context: context, templates: parsedPartials)
                : engine.renderWithDiagnosticsAndMetrics(template: source, context: context, templates: partials)
            guard result.diagnostics.isEmpty else { throw MaintenanceFailure(message: "Unexpected diagnostics") }
            return result.output
        }
    }
}

private func nanoseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000_000_000 + Double(parts.attoseconds) / 1_000_000_000
}

private func checksum(_ text: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
    return String(hash, radix: 16)
}

private func summary(_ values: [Double]) throws -> [String: Any] {
    guard values.count == 25, values.allSatisfy({ $0 > 0 && $0.isFinite }) else {
        throw MaintenanceFailure(message: "Invalid observation set")
    }
    let sorted = values.sorted()
    return ["medianNanoseconds": sorted[12], "p95Nanoseconds": sorted[23],
            "minimumNanoseconds": sorted[0], "maximumNanoseconds": sorted[24]]
}

/// Both modes signal actual host entry. The explicit-release mode intentionally
/// ignores task cancellation until its controller releases the continuation.
private actor HostGate {
    private let arrival = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let resume = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var continuation: CheckedContinuation<Void, Never>?
    private var exited = false
    private var continued = false

    func enter(cooperative: Bool) async {
        if cooperative {
            arrival.continuation.yield(()); arrival.continuation.finish()
            var iterator = resume.stream.makeAsyncIterator()
            _ = await iterator.next()
        } else {
            await withCheckedContinuation { pending in
                continuation = pending
                arrival.continuation.yield(()); arrival.continuation.finish()
            }
        }
        exited = true
    }
    func waitForEntry() async -> Bool {
        var iterator = arrival.stream.makeAsyncIterator()
        return await iterator.next() != nil
    }
    func finished() { arrival.continuation.finish() }
    func release() {
        resume.continuation.finish()
        continuation?.resume(); continuation = nil
    }
    func markContinuation() { continued = true }
    func state() -> (exited: Bool, continued: Bool) { (exited, continued) }
}

private enum Outcome: Sendable { case cancelled, completed, failed(String) }
private struct Completion: Sendable {
    let outcome: Outcome
    let instant: ContinuousClock.Instant
}

@main
struct MaintenanceBenchmarks {
    static func main() async throws { try await measure() }

    // An async executable's entry point is MainActor-isolated. Keep the driver
    // and callback construction off that actor so runnable work cannot prevent
    // the controller from requesting cancellation on the same serial executor.
    @concurrent
    private static func measure() async throws {
        #if DEBUG
        throw MaintenanceFailure(message: "Measurements require a release build")
        #else
        guard CommandLine.arguments.count == 2 else { throw MaintenanceFailure(message: "Expected OUTPUT") }
        let clock = ContinuousClock()
        let engine = LiquidEngine()
        let text = String(repeating: "<Swift & Liquid>", count: 8_192)
        let escaped = String(repeating: "&lt;Swift &amp; Liquid&gt;", count: 8_192)
        let row = "Swift-🌊;"
        let workloads: [(String, String, LiquidObject, [String: String], String, Int)] = [
            ("large-loop", "{% for item in items %}{{ item }}{% endfor %}",
             ["items": .array(Array(repeating: .string(row), count: 1_024))], [:], String(repeating: row, count: 1_024), 1_024),
            ("large-escape", "{{ text | escape }}", ["text": .string(text)], [:], escaped, text.utf8.count),
            ("partial-fanout", "{% for item in (1..256) %}{% render 'row' %}{% endfor %}",
             [:], ["row": "<p>Swift &amp; Liquid</p>"], String(repeating: "<p>Swift &amp; Liquid</p>", count: 256), 256)
        ]
        var large: [[String: Any]] = []
        for (name, source, context, partials, expected, units) in workloads {
            let parsed = try LiquidTemplate(source)
            let parsedPartials = try partials.mapValues { try LiquidTemplate($0) }
            for reuse in [false, true] {
                var samples: [Double] = []
                for index in -5..<25 {
                    let start = clock.now
                    let output = try await Policy.ordinary.render(engine, source: source, parsed: parsed,
                        reuse: reuse, context: context, partials: partials, parsedPartials: parsedPartials)
                    let elapsed = nanoseconds(start.duration(to: clock.now))
                    // Output equality and hashing are outside the timed call.
                    guard output == expected else { throw MaintenanceFailure(message: "Large workload output differs") }
                    if index >= 0 { samples.append(elapsed) }
                }
                var record: [String: Any] = ["workload": name, "mode": reuse ? "parsed" : "source",
                    "samples": 25, "warmupSamples": 5, "repetitions": 1, "units": units,
                    "sourceBytes": source.utf8.count + partials.values.reduce(0) { $0 + $1.utf8.count },
                    "outputBytes": expected.utf8.count, "checksumFNV1a64": checksum(expected),
                    "nanosecondsPerOperation": samples]
                record.merge(try summary(samples)) { _, new in new }; large.append(record)
            }
        }
        var cancellation: [[String: Any]] = []
        let source = "{{ 'value' | host_pause | after_pause }}"
        let parsed = try LiquidTemplate(source)
        for policy in Policy.allCases {
            for reuse in [false, true] {
                for cooperative in [true, false] {
                    var samples: [Double] = [], releaseDelays: [Double] = [], responses: [Double] = []
                    for index in -5..<25 {
                        let gate = HostGate()
                        let active = try LiquidEngine(filters: [
                            LiquidFilter("host_pause") { value, _, _ in await gate.enter(cooperative: cooperative); return value },
                            LiquidFilter("after_pause") { value, _, _ in await gate.markContinuation(); return value }
                        ])
                        let worker = Task.detached {
                            let outcome: Outcome
                            do { _ = try await policy.render(active, source: source, parsed: parsed, reuse: reuse); outcome = .completed }
                            catch is CancellationError { outcome = .cancelled }
                            catch { outcome = .failed(String(describing: error)) }
                            await gate.finished()
                            return outcome
                        }
                        guard await gate.waitForEntry() else {
                            worker.cancel(); await gate.release(); _ = await worker.value
                            throw MaintenanceFailure(message: "Worker failed before host entry")
                        }
                        let start = clock.now
                        worker.cancel()
                        var released: ContinuousClock.Instant?
                        if !cooperative {
                            let state = await gate.state()
                            guard !state.exited else { throw MaintenanceFailure(message: "Host escaped explicit release") }
                            // This includes controller scheduling; no synthetic sleep sets a delay.
                            released = clock.now
                            await gate.release()
                        }
                        let outcome = await worker.value
                        let end = clock.now
                        await gate.release()
                        let state = await gate.state()
                        guard case .cancelled = outcome, !state.continued else {
                            throw MaintenanceFailure(message: "Cancellation lost its identity or continued evaluation")
                        }
                        guard try await active.render(template: "healthy") == "healthy" else {
                            throw MaintenanceFailure(message: "Cancelled invocation damaged engine reuse")
                        }
                        if index >= 0 {
                            samples.append(nanoseconds(start.duration(to: end)))
                            if let released {
                                releaseDelays.append(nanoseconds(start.duration(to: released)))
                                responses.append(nanoseconds(released.duration(to: end)))
                            }
                        }
                    }
                    var record: [String: Any] = ["policy": policy.rawValue, "mode": reuse ? "parsed" : "source",
                        "host": cooperative ? "cooperative" : "explicit-release", "samples": 25, "warmupSamples": 5,
                        "cancelledSamples": 25, "continuedSamples": 0, "healthyReuse": true,
                        "cancelToCompletionNanoseconds": samples, "cancelToReleaseNanoseconds": releaseDelays,
                        "releaseToCompletionNanoseconds": responses]
                    record.merge(try summary(samples)) { _, new in new }; cancellation.append(record)
                }
            }
        }
        // The callback signals entry and returns immediately. The controller may
        // race the remaining work; every completion is retained and classified.
        var runnable: [[String: Any]] = []
        let runnableSource = "{{ text | announce_work | escape }}"
        let runnableParsed = try LiquidTemplate(runnableSource)
        for policy in Policy.allCases {
            for reuse in [false, true] {
                var observations: [[String: Any]] = []
                var cancelled: [Double] = []
                for index in -5..<25 {
                    let entry = DispatchSemaphore(value: 0)
                    let start = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
                    let requests = AsyncStream<ContinuousClock.Instant>.makeStream(bufferingPolicy: .bufferingNewest(1))
                    let announcements = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
                    let active = try LiquidEngine(filters: [
                        LiquidFilter("announce_work") { value, _, _ in
                            announcements.continuation.yield(()); announcements.continuation.finish()
                            entry.signal(); return value
                        }
                    ])
                    let worker = Task.detached {
                        // Also unblock the controller if rendering fails before the marker.
                        defer { announcements.continuation.finish(); entry.signal() }
                        var iterator = start.stream.makeAsyncIterator()
                        guard await iterator.next() != nil else {
                            return Completion(outcome: .failed("Missing controller start"), instant: clock.now)
                        }
                        let completion: Completion
                        do {
                            let output = try await policy.render(active, source: runnableSource,
                                parsed: runnableParsed, reuse: reuse, context: ["text": .string(text)])
                            let end = clock.now
                            completion = Completion(outcome: output == escaped ? .completed : .failed("Output differs"), instant: end)
                        } catch is CancellationError { completion = Completion(outcome: .cancelled, instant: clock.now) }
                        catch { completion = Completion(outcome: .failed(String(describing: error)), instant: clock.now) }
                        return completion
                    }
                    // Only a Dispatch thread blocks. A Swift-task controller could be
                    // scheduled after all runnable work on a busy cooperative executor.
                    DispatchQueue.global(qos: .userInitiated).async {
                        start.continuation.yield(()); start.continuation.finish()
                        entry.wait()
                        let requested = clock.now
                        worker.cancel()
                        requests.continuation.yield(requested); requests.continuation.finish()
                    }
                    var iterator = requests.stream.makeAsyncIterator()
                    guard let requested = await iterator.next() else {
                        worker.cancel(); _ = await worker.value
                        throw MaintenanceFailure(message: "Missing runnable cancellation request")
                    }
                    let completion = await worker.value
                    var announcement = announcements.stream.makeAsyncIterator()
                    guard await announcement.next() != nil else {
                        throw MaintenanceFailure(message: "Runnable render did not enter its marker callback")
                    }
                    let interval = nanoseconds(requested.duration(to: completion.instant))
                    let outcome: String
                    switch completion.outcome {
                    case .cancelled:
                        guard interval >= 0 else { throw MaintenanceFailure(message: "Cancellation precedes its only request") }
                        outcome = "cancelled"
                    case .completed: outcome = interval < 0 ? "completed-before-request" : "completed-racing-request"
                    case .failed(let message): throw MaintenanceFailure(message: message)
                    }
                    guard try await active.render(template: "healthy") == "healthy" else {
                        throw MaintenanceFailure(message: "Runnable cancellation damaged reuse")
                    }
                    if index >= 0 {
                        observations.append(["outcome": outcome, "completionRelativeToRequestNanoseconds": interval])
                        if outcome == "cancelled" { cancelled.append(interval) }
                    }
                }
                let sorted = cancelled.sorted()
                let median: Any
                let p95: Any
                if sorted.isEmpty { median = NSNull(); p95 = NSNull() }
                else {
                    median = sorted.count % 2 == 1 ? sorted[sorted.count / 2]
                        : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                    p95 = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]
                }
                runnable.append(["workload": "runnable-escape", "policy": policy.rawValue,
                    "mode": reuse ? "parsed" : "source", "samples": 25, "warmupSamples": 5,
                    "inputBytes": text.utf8.count, "expectedOutputBytes": escaped.utf8.count,
                    "checksumFNV1a64": checksum(escaped), "observations": observations,
                    "cancelledSamples": cancelled.count, "completedSamples": 25 - cancelled.count,
                    "healthyReuse": true,
                    "cancelledMedianNanoseconds": median, "cancelledP95Nanoseconds": p95])
            }
        }
        let result: [String: Any] = ["schemaVersion": 1, "configuration": "release",
            "operation": "measured-maintenance",
            "schedulerConfiguration": "concurrent driver, detached workers, Dispatch cancellation controller", "largeWorkloads": large, "cancellation": cancellation, "runnableCancellation": runnable]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
        print(String(decoding: data, as: UTF8.self))
        #endif
    }
}
