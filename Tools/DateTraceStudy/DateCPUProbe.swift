// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import Liquid
private struct ProbeFailure: Error {}
@main struct DateCPUProbe {
    static func main() async throws {
        #if DEBUG
        throw ProbeFailure()
        #else
        guard CommandLine.arguments.count == 3 else { throw ProbeFailure() }
        let caller = CommandLine.arguments[1]
        guard caller == "actor" || caller == "concurrent" else { throw ProbeFailure() }
        let records = try await caller == "actor" ? onActor() : onConcurrent()
        let result: [String: Any] = ["configuration": "release", "caller": caller,
            "cpuClock": "getrusage(RUSAGE_SELF) user+system; brackets wall sample; process-wide",
            "records": try JSONSerialization.jsonObject(with: records)]
        try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        #endif
    }
    nonisolated private static func processCPU() throws -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw ProbeFailure() }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1e9
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) * 1000
    }
    @MainActor private static func onActor() async throws -> Data {

        let engine = LiquidEngine()
        let workloads: [(String, String, LiquidObject, String)] = [
            ("iso", "{{ stamp | date: '%F %T %:z %N' }}", ["stamp": "2024-02-03T04:05:06.123456789+05:30"], "2024-02-03 04:05:06 +05:30 123456789"),
            ("epoch", "{{ stamp | date: '%F %T %:z %N' }}", ["stamp": 0], "1970-01-01 00:00:00 +00:00 000000000"),
            ("filter", "{{ title | strip | upcase | escape }}", ["title": " <Swift> "], "&lt;SWIFT&gt;")
        ]
        let clock = ContinuousClock()
        var records: [[String: Any]] = []
        for (name, source, context, expected) in workloads {
            let parsed = try LiquidTemplate(source)
            for mode in ["parse", "source", "reused", "source-metrics", "reused-metrics"] {
                let payload = mode == "parse" ? source : expected
                var wall: [Double] = [], cpu: [Double] = []
                var checksum: UInt64 = 14_695_981_039_346_656_037
                for sample in -10..<25 {
                    let cpuStart = try processCPU()
                    let start = clock.now
                    for _ in 0..<100 {
                        let output: String
                        switch mode {
                        case "parse": output = try LiquidTemplate(source).source
                        case "source": output = try await engine.render(template: source, context: context)
                        case "reused": output = try await engine.render(parsed, context: context)
                        case "source-metrics": output = try await engine.renderWithMetrics(template: source, context: context).output
                        default: output = try await engine.renderWithMetrics(parsed, context: context).output
                        }
                        guard output.utf8.elementsEqual(payload.utf8) else { throw ProbeFailure() }
                        for byte in output.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                    }
                    let elapsed = start.duration(to: clock.now).components
                    let cpuElapsed = try processCPU() - cpuStart
                    if sample >= 0 {
                        wall.append((Double(elapsed.seconds) * 1e9 + Double(elapsed.attoseconds) / 1e9) / 100)
                        cpu.append(cpuElapsed / 100)
                    }
                }
                let w = wall.sorted(), c = cpu.sorted()
                records.append(["name": name, "mode": mode, "samples": 25, "warmupSamples": 10, "repetitionsPerSample": 100,
                    "wallSampleNanoseconds": wall, "cpuSampleNanoseconds": cpu,
                    "wallMedianNanoseconds": w[12], "cpuMedianNanoseconds": c[12],
                    "wallP95Nanoseconds": w[23], "cpuP95Nanoseconds": c[23],
                    "outputBytes": payload.utf8.count, "fnv1aChecksum": String(checksum, radix: 16)])
            }
        }
        return try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
    }
    @concurrent private static func onConcurrent() async throws -> Data {

        let engine = LiquidEngine()
        let workloads: [(String, String, LiquidObject, String)] = [
            ("iso", "{{ stamp | date: '%F %T %:z %N' }}", ["stamp": "2024-02-03T04:05:06.123456789+05:30"], "2024-02-03 04:05:06 +05:30 123456789"),
            ("epoch", "{{ stamp | date: '%F %T %:z %N' }}", ["stamp": 0], "1970-01-01 00:00:00 +00:00 000000000"),
            ("filter", "{{ title | strip | upcase | escape }}", ["title": " <Swift> "], "&lt;SWIFT&gt;")
        ]
        let clock = ContinuousClock()
        var records: [[String: Any]] = []
        for (name, source, context, expected) in workloads {
            let parsed = try LiquidTemplate(source)
            for mode in ["parse", "source", "reused", "source-metrics", "reused-metrics"] {
                let payload = mode == "parse" ? source : expected
                var wall: [Double] = [], cpu: [Double] = []
                var checksum: UInt64 = 14_695_981_039_346_656_037
                for sample in -10..<25 {
                    let cpuStart = try processCPU()
                    let start = clock.now
                    for _ in 0..<100 {
                        let output: String
                        switch mode {
                        case "parse": output = try LiquidTemplate(source).source
                        case "source": output = try await engine.render(template: source, context: context)
                        case "reused": output = try await engine.render(parsed, context: context)
                        case "source-metrics": output = try await engine.renderWithMetrics(template: source, context: context).output
                        default: output = try await engine.renderWithMetrics(parsed, context: context).output
                        }
                        guard output.utf8.elementsEqual(payload.utf8) else { throw ProbeFailure() }
                        for byte in output.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                    }
                    let elapsed = start.duration(to: clock.now).components
                    let cpuElapsed = try processCPU() - cpuStart
                    if sample >= 0 {
                        wall.append((Double(elapsed.seconds) * 1e9 + Double(elapsed.attoseconds) / 1e9) / 100)
                        cpu.append(cpuElapsed / 100)
                    }
                }
                let w = wall.sorted(), c = cpu.sorted()
                records.append(["name": name, "mode": mode, "samples": 25, "warmupSamples": 10, "repetitionsPerSample": 100,
                    "wallSampleNanoseconds": wall, "cpuSampleNanoseconds": cpu,
                    "wallMedianNanoseconds": w[12], "cpuMedianNanoseconds": c[12],
                    "wallP95Nanoseconds": w[23], "cpuP95Nanoseconds": c[23],
                    "outputBytes": payload.utf8.count, "fnv1aChecksum": String(checksum, radix: 16)])
            }
        }
        return try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
    }
}
