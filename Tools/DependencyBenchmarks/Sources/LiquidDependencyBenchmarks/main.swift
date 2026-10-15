// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid

private struct BenchmarkFailure: Error { let message: String }

@main struct DependencyBenchmarks {
    static func main() throws {
        #if DEBUG
        throw BenchmarkFailure(message: "Release build required")
        #else
        guard CommandLine.arguments.count == 2 else { throw BenchmarkFailure(message: "Expected output path") }
        let engine = LiquidEngine()
        let clock = ContinuousClock()
        let samples = 25, repetitions = 20
        var diamond: [String: String] = ["shared": "{{ user.name | escape }}"]
        for i in 0..<64 { diamond["leaf\(i)"] = "{% include 'shared' %}{% include 'shared' %}" }
        let diamondRoot = (0..<64).map { "{% include 'leaf\($0)' %}" }.joined()
        var cycle: [String: String] = [:]
        for i in 0..<128 { cycle["p\(i)"] = "{% include 'p\((i + 1) % 128)' %}" }
        var records: [[String: Any]] = []
        for (name, root, sources, nodeCount, edgeCount, cycleSize) in [
            ("shared-diamond", diamondRoot, diamond, 66, 128, 0),
            ("cycle", "{% include 'p0' %}", cycle, 129, 129, 128)
        ] {
            let parsed = try LiquidTemplate(root)
            let partials = try sources.mapValues { try LiquidTemplate($0) }
            let expected = try engine.inspectDependencies(parsed, templates: partials)
            guard expected.nodes.count == nodeCount, expected.edges.count == edgeCount,
                  expected.cycles.count == (cycleSize == 0 ? 0 : 1),
                  expected.cycles.first?.count ?? 0 == cycleSize,
                  expected.missingReferences.isEmpty, expected.dynamicReferences.isEmpty else {
                throw BenchmarkFailure(message: "Unexpected graph shape")
            }
            for reuse in [false, true] {
                var timings: [Double] = []
                var checksum: UInt64 = 14_695_981_039_346_656_037
                for sample in -10..<samples {
                    let start = clock.now
                    for _ in 0..<repetitions {
                        let result = try reuse ? engine.inspectDependencies(parsed, templates: partials)
                            : engine.inspectDependencies(template: root, templates: sources)
                        guard result == expected else { throw BenchmarkFailure(message: "Graph changed") }
                        // Exact result equality above audits every field. Fold stable names into the receipt checksum.
                        for edge in result.edges {
                            for byte in edge.requestedName.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                        }
                    }
                    let duration = start.duration(to: clock.now).components
                    if sample >= 0 { timings.append((Double(duration.seconds) * 1e9 + Double(duration.attoseconds) / 1e9) / Double(repetitions)) }
                }
                let sorted = timings.sorted()
                records.append(["workload": name, "mode": reuse ? "parsed" : "source", "nodes": nodeCount,
                    "edges": edgeCount, "cycleMembers": cycleSize, "warmupSamples": 10, "samples": samples,
                    "repetitions": repetitions, "nanosecondsPerOperation": timings, "medianNanoseconds": sorted[samples / 2],
                    "p95Nanoseconds": sorted[Int(ceil(Double(samples) * 0.95)) - 1], "checksumFNV1a64": String(checksum, radix: 16)])
            }
        }
        let object: [String: Any] = ["schemaVersion": 1, "operation": "dependency-inspection", "records": records,
            "scope": "Graph construction plus result equality and checksum audit; no rendering or release speedup claim."]
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
        print("Dependency benchmarks: four source/parsed diamond/cycle records passed.")
        #endif
    }
}
