// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid

private struct Workload {
    let name: String
    let source: String
    let context: LiquidObject
    let partials: [String: String]
    let expected: String
}

@main
struct Benchmarks {
    static func main() async throws {
        let workloads = [
            Workload(name: "interpolation", source: "Hello, {{ name }}!", context: ["name": "Swift"], partials: [:], expected: "Hello, Swift!"),
            Workload(name: "filter-chain", source: "{{ title | strip | upcase | escape }}", context: ["title": " <Swift> "], partials: [:], expected: "&lt;SWIFT&gt;"),
            Workload(name: "loop", source: "{% for item in items %}{{ forloop.index }}:{{ item.title }};{% endfor %}", context: ["items": [["title": "A"], ["title": "B"], ["title": "C"]]], partials: [:], expected: "1:A;2:B;3:C;"),
            Workload(name: "partial", source: "{% render 'card', title: title %}", context: ["title": "Swift"], partials: ["card": "<h2>{{ title | escape }}</h2>"], expected: "<h2>Swift</h2>")
        ]
        let engine = LiquidEngine()
        let clock = ContinuousClock()
        let samples = 25
        let repetitions = 100
        var records: [[String: Any]] = []
        for workload in workloads {
            let parsed = try LiquidTemplate(workload.source)
            let partials = try workload.partials.mapValues { try LiquidTemplate($0) }
            for reuse in [false, true] {
                var timings: [Double] = []
                var checksum: UInt64 = 14_695_981_039_346_656_037
                for sample in -10..<samples {
                    let start = clock.now
                    for _ in 0..<repetitions {
                        let output: String
                        if reuse { output = try await engine.render(parsed, context: workload.context, templates: partials) }
                        else { output = try await engine.render(template: workload.source, context: workload.context, templates: workload.partials) }
                        guard output == workload.expected else { throw BenchmarkFailure("Output mismatch for \(workload.name)") }
                        for byte in output.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                    }
                    let duration = start.duration(to: clock.now).components
                    if sample >= 0 { timings.append((Double(duration.seconds) * 1_000_000_000 + Double(duration.attoseconds) / 1_000_000_000) / Double(repetitions)) }
                }
                timings.sort()
                records.append(["name": workload.name, "mode": reuse ? "reused-template" : "parse-and-render",
                                "samples": samples, "warmupSamples": 10, "repetitionsPerSample": repetitions,
                                "medianNanoseconds": timings[samples / 2], "p95Nanoseconds": timings[Int(ceil(Double(samples) * 0.95)) - 1],
                                "minimumNanoseconds": timings[0], "maximumNanoseconds": timings[samples - 1],
                                "outputBytes": workload.expected.utf8.count, "fnv1aChecksum": String(checksum, radix: 16)])
            }
        }
        let result: [String: Any] = ["schemaVersion": 1, "platform": ProcessInfo.processInfo.operatingSystemVersionString,
                                     "configuration": "release", "workloads": records]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        if CommandLine.arguments.count > 1 { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic) }
        print(String(decoding: data, as: UTF8.self))
    }
}

private struct BenchmarkFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
