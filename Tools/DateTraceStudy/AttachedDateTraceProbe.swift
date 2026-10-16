// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import Liquid
import os
private struct TraceFailure: Error {}
@main struct DateTraceProbe {
    static func main() async throws {
        #if DEBUG
        throw TraceFailure()
        #else
        guard CommandLine.arguments.count == 5 else { throw TraceFailure() }
        let caller = CommandLine.arguments[1], capture = CommandLine.arguments[2]
        guard ["actor", "concurrent"].contains(caller), ["cpu", "executor"].contains(capture) else { throw TraceFailure() }
        let coordination = URL(fileURLWithPath: CommandLine.arguments[4])
        let files = FileManager.default
        try Data("ready".utf8).write(to: coordination.appendingPathComponent("ready"))
        while !files.fileExists(atPath: coordination.appendingPathComponent("start").path) { try await Task.sleep(for: .milliseconds(20)) }
        let records = try await caller == "actor" ? onActor(capture) : onConcurrent(capture)
        let result: [String: Any] = ["configuration": "release", "caller": caller, "capture": capture,
            "records": try JSONSerialization.jsonObject(with: records)]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
        print("Trace probe complete: \(caller) \(capture)")
        try Data("done".utf8).write(to: coordination.appendingPathComponent("done"))
        while !files.fileExists(atPath: coordination.appendingPathComponent("release").path) { try await Task.sleep(for: .milliseconds(20)) }
        #endif
    }
    nonisolated private static func processCPU() throws -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw TraceFailure() }
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1e9
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) * 1000
    }
    @MainActor private static func onActor(_ capture: String) async throws -> Data {

        try Task.checkCancellation()
        let engine = LiquidEngine()
        let poster = OSSignposter(subsystem: "org.swift-liquid.date-trace", category: .pointsOfInterest)
        let workloads: [(String, String, LiquidObject, String)] = [
            ("iso", "{{ stamp | date: '%F %T %:z %N' }}", ["stamp": "2024-02-03T04:05:06.123456789+05:30"], "2024-02-03 04:05:06 +05:30 123456789"),
            ("epoch", "{{ stamp | date: '%F %T %:z %N' }}", ["stamp": 0], "1970-01-01 00:00:00 +00:00 000000000"),
            ("filter", "{{ title | strip | upcase | escape }}", ["title": " <Swift> "], "&lt;SWIFT&gt;")
        ]
        let count = capture == "cpu" ? 20_000 : 100
        let warmups = capture == "cpu" ? 100 : 10
        let clock = ContinuousClock()
        var records: [[String: Any]] = []
        for (name, source, context, expected) in workloads {
            let template = try LiquidTemplate(source)
            for reused in [false, true] {
                let key = name + (reused ? "-reused" : "-source")
                var checksum: UInt64 = 14_695_981_039_346_656_037
                for _ in 0..<warmups {
                    let output = try await reused ? engine.render(template, context: context) : engine.render(template: source, context: context)
                    guard output.utf8.elementsEqual(expected.utf8) else { throw TraceFailure() }
                    for byte in output.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                }
                let interval = poster.beginInterval("RenderBatch", id: poster.makeSignpostID(), "case=\(key, privacy: .public)")
                let cpuStart = try processCPU(), start = clock.now
                for _ in 0..<count {
                    let output = try await reused ? engine.render(template, context: context) : engine.render(template: source, context: context)
                    guard output.utf8.elementsEqual(expected.utf8) else { throw TraceFailure() }
                    for byte in output.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                }
                let elapsed = start.duration(to: clock.now).components
                let cpu = try processCPU() - cpuStart
                poster.endInterval("RenderBatch", interval, "case=\(key, privacy: .public)")
                records.append(["name": key, "iterations": count, "warmupIterations": warmups,
                    "wallNanoseconds": Double(elapsed.seconds) * 1e9 + Double(elapsed.attoseconds) / 1e9,
                    "cpuNanoseconds": cpu, "outputBytes": expected.utf8.count, "fnv1aChecksum": String(checksum, radix: 16)])
            }
        }
        try Task.checkCancellation()
        return try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
    }
    @concurrent private static func onConcurrent(_ capture: String) async throws -> Data {

        try Task.checkCancellation()
        let engine = LiquidEngine()
        let poster = OSSignposter(subsystem: "org.swift-liquid.date-trace", category: .pointsOfInterest)
        let workloads: [(String, String, LiquidObject, String)] = [
            ("iso", "{{ stamp | date: '%F %T %:z %N' }}", ["stamp": "2024-02-03T04:05:06.123456789+05:30"], "2024-02-03 04:05:06 +05:30 123456789"),
            ("epoch", "{{ stamp | date: '%F %T %:z %N' }}", ["stamp": 0], "1970-01-01 00:00:00 +00:00 000000000"),
            ("filter", "{{ title | strip | upcase | escape }}", ["title": " <Swift> "], "&lt;SWIFT&gt;")
        ]
        let count = capture == "cpu" ? 20_000 : 100
        let warmups = capture == "cpu" ? 100 : 10
        let clock = ContinuousClock()
        var records: [[String: Any]] = []
        for (name, source, context, expected) in workloads {
            let template = try LiquidTemplate(source)
            for reused in [false, true] {
                let key = name + (reused ? "-reused" : "-source")
                var checksum: UInt64 = 14_695_981_039_346_656_037
                for _ in 0..<warmups {
                    let output = try await reused ? engine.render(template, context: context) : engine.render(template: source, context: context)
                    guard output.utf8.elementsEqual(expected.utf8) else { throw TraceFailure() }
                    for byte in output.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                }
                let interval = poster.beginInterval("RenderBatch", id: poster.makeSignpostID(), "case=\(key, privacy: .public)")
                let cpuStart = try processCPU(), start = clock.now
                for _ in 0..<count {
                    let output = try await reused ? engine.render(template, context: context) : engine.render(template: source, context: context)
                    guard output.utf8.elementsEqual(expected.utf8) else { throw TraceFailure() }
                    for byte in output.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                }
                let elapsed = start.duration(to: clock.now).components
                let cpu = try processCPU() - cpuStart
                poster.endInterval("RenderBatch", interval, "case=\(key, privacy: .public)")
                records.append(["name": key, "iterations": count, "warmupIterations": warmups,
                    "wallNanoseconds": Double(elapsed.seconds) * 1e9 + Double(elapsed.attoseconds) / 1e9,
                    "cpuNanoseconds": cpu, "outputBytes": expected.utf8.count, "fnv1aChecksum": String(checksum, radix: 16)])
            }
        }
        try Task.checkCancellation()
        return try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
    }
}
