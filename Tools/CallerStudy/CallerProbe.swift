// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid

private struct ProbeFailure: Error {}
@main struct CallerProbe {
    static func main() async throws {
        #if DEBUG
        throw ProbeFailure()
        #else
        guard CommandLine.arguments.count == 3 else { throw ProbeFailure() }
        let mode = CommandLine.arguments[1]
        guard mode == "actor" || mode == "concurrent" else { throw ProbeFailure() }
        let records = try await mode == "actor" ? onActor() : onConcurrent()
        let result: [String: Any] = ["configuration": "release", "caller": mode, "records": try JSONSerialization.jsonObject(with: records)]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        #endif
    }
    @inline(never) nonisolated static func emptyAsync(_ text: String) async -> String { text }
    @inline(never) nonisolated static func checkedAsync(_ text: String) async throws -> String {
        try Task.checkCancellation()
        return text
    }
    @MainActor private static func onActor() async throws -> Data {

        let engine = LiquidEngine()
        let interpolation = try LiquidTemplate("Hello, {{ name }}!")
        let date = try LiquidTemplate("{{ stamp | date: '%F %T %:z %N' }}")
        let name: LiquidObject = ["name": "Swift"]
        let stamp: LiquidObject = ["stamp": "2024-02-03T04:05:06.123456789+05:30"]
        let clock = ContinuousClock()
        var records: [[String: Any]] = []
        for kind in ["empty-async", "checked-async", "interpolation", "interpolation-metrics", "date", "date-metrics"] {
            let expected = kind.hasPrefix("date") ? "2024-02-03 04:05:06 +05:30 123456789" : "Hello, Swift!"
            var times: [Double] = [], checksum: UInt64 = 14_695_981_039_346_656_037
            for sample in -10..<25 {
                let start = clock.now
                for _ in 0..<100 {
                    let output: String
                    switch kind {
                    case "empty-async": output = await emptyAsync(expected)
                    case "checked-async": output = try await checkedAsync(expected)
                    case "interpolation": output = try await engine.render(interpolation, context: name)
                    case "interpolation-metrics": output = try await engine.renderWithMetrics(interpolation, context: name).output
                    case "date": output = try await engine.render(date, context: stamp)
                    default: output = try await engine.renderWithMetrics(date, context: stamp).output
                    }
                    guard output == expected else { throw ProbeFailure() }
                    for byte in output.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                }
                let d = start.duration(to: clock.now).components
                if sample >= 0 { times.append((Double(d.seconds) * 1e9 + Double(d.attoseconds) / 1e9) / 100) }
            }
            let sorted = times.sorted()
            records.append(["name": kind, "samples": 25, "warmupSamples": 10, "repetitionsPerSample": 100,
                "sampleNanoseconds": times, "medianNanoseconds": sorted[12], "p95Nanoseconds": sorted[23],
                "minimumNanoseconds": sorted[0], "maximumNanoseconds": sorted[24],
                "outputBytes": expected.utf8.count, "fnv1aChecksum": String(checksum, radix: 16)])
        }
        return try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
    }
    @concurrent private static func onConcurrent() async throws -> Data {

        let engine = LiquidEngine()
        let interpolation = try LiquidTemplate("Hello, {{ name }}!")
        let date = try LiquidTemplate("{{ stamp | date: '%F %T %:z %N' }}")
        let name: LiquidObject = ["name": "Swift"]
        let stamp: LiquidObject = ["stamp": "2024-02-03T04:05:06.123456789+05:30"]
        let clock = ContinuousClock()
        var records: [[String: Any]] = []
        for kind in ["empty-async", "checked-async", "interpolation", "interpolation-metrics", "date", "date-metrics"] {
            let expected = kind.hasPrefix("date") ? "2024-02-03 04:05:06 +05:30 123456789" : "Hello, Swift!"
            var times: [Double] = [], checksum: UInt64 = 14_695_981_039_346_656_037
            for sample in -10..<25 {
                let start = clock.now
                for _ in 0..<100 {
                    let output: String
                    switch kind {
                    case "empty-async": output = await emptyAsync(expected)
                    case "checked-async": output = try await checkedAsync(expected)
                    case "interpolation": output = try await engine.render(interpolation, context: name)
                    case "interpolation-metrics": output = try await engine.renderWithMetrics(interpolation, context: name).output
                    case "date": output = try await engine.render(date, context: stamp)
                    default: output = try await engine.renderWithMetrics(date, context: stamp).output
                    }
                    guard output == expected else { throw ProbeFailure() }
                    for byte in output.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                }
                let d = start.duration(to: clock.now).components
                if sample >= 0 { times.append((Double(d.seconds) * 1e9 + Double(d.attoseconds) / 1e9) / 100) }
            }
            let sorted = times.sorted()
            records.append(["name": kind, "samples": 25, "warmupSamples": 10, "repetitionsPerSample": 100,
                "sampleNanoseconds": times, "medianNanoseconds": sorted[12], "p95Nanoseconds": sorted[23],
                "minimumNanoseconds": sorted[0], "maximumNanoseconds": sorted[24],
                "outputBytes": expected.utf8.count, "fnv1aChecksum": String(checksum, radix: 16)])
        }
        return try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
    }
}
