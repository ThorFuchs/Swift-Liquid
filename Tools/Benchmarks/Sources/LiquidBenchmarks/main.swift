// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid

private struct Workload {
    let name: String
    let source: String
    let context: LiquidObject
    let partials: [String: String]
    let expected: String
    let filters: [LiquidFilter]
    init(name: String, source: String, context: LiquidObject, partials: [String: String], expected: String,
         filters: [LiquidFilter] = []) {
        self.name = name; self.source = source; self.context = context
        self.partials = partials; self.expected = expected; self.filters = filters
    }
}

@main
struct Benchmarks {
    static func main() async throws {
        #if DEBUG
        throw BenchmarkFailure("Benchmarks require a release build")
        #else
        let workloads = [
            Workload(name: "interpolation", source: "Hello, {{ name }}!", context: ["name": "Swift"], partials: [:], expected: "Hello, Swift!"),
            Workload(name: "filter-chain", source: "{{ title | strip | upcase | escape }}", context: ["title": " <Swift> "], partials: [:], expected: "&lt;SWIFT&gt;"),
            Workload(name: "loop", source: "{% for item in items %}{{ forloop.index }}:{{ item.title }};{% endfor %}", context: ["items": [["title": "A"], ["title": "B"], ["title": "C"]]], partials: [:], expected: "1:A;2:B;3:C;"),
            Workload(name: "partial", source: "{% render 'card', title: title %}", context: ["title": "Swift"], partials: ["card": "<h2>{{ title | escape }}</h2>"], expected: "<h2>Swift</h2>"),
            Workload(name: "date", source: "{{ stamp | date: '%F %T %:z %N' }}", context: ["stamp": "2024-02-03T04:05:06.123456789+05:30"], partials: [:], expected: "2024-02-03 04:05:06 +05:30 123456789"),
            Workload(name: "custom-filter", source: "{{ title | strip | host_label: '<', suffix: '>' | escape }}",
                context: ["title": " Swift "], partials: [:], expected: "&lt;Swift&gt;",
                filters: [LiquidFilter("host_label") { value, arguments, named in
                    guard case .string(let text) = value, case .string(let prefix) = arguments.first,
                          case .string(let suffix) = named["suffix"] else { throw BenchmarkFailure("Invalid custom-filter arguments") }
                    return .string(prefix + text + suffix)
                }])
        ]
        let engine = LiquidEngine()
        let clock = ContinuousClock()
        let samples = 25
        let repetitions = 100
        var records: [[String: Any]] = []
        for workload in workloads {
            let activeEngine: LiquidEngine
            if workload.filters.isEmpty { activeEngine = engine }
            else { activeEngine = try LiquidEngine(filters: workload.filters) }
            let parsed = try LiquidTemplate(workload.source)
            let partials = try workload.partials.mapValues { try LiquidTemplate($0) }
            for reuse in [false, true] {
                var timings: [Double] = []
                var checksum: UInt64 = 14_695_981_039_346_656_037
                for sample in -10..<samples {
                    let start = clock.now
                    for _ in 0..<repetitions {
                        let output: String
                        if reuse { output = try await activeEngine.render(parsed, context: workload.context, templates: partials) }
                        else { output = try await activeEngine.render(template: workload.source, context: workload.context, templates: workload.partials) }
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
        // Inspection is measured separately from rendering. Its stable payload includes
        // every summary field; no callbacks or partial sources are supplied.
        let inspectionSource = "{% for item in items limit: maximum %}{{ item[key] | host: prefix, suffix: ending | escape }}{% render 'card', title: item.title %}{% endfor %}{% include selected %}"
        let inspectionTemplate = try LiquidTemplate(inspectionSource)
        let expectedInspection = "ending,item,items,key,maximum,prefix,selected|escape,host|card|true"
        for reuse in [false, true] {
            var timings: [Double] = []
            var checksum: UInt64 = 14_695_981_039_346_656_037
            for sample in -10..<samples {
                let start = clock.now
                for _ in 0..<repetitions {
                    let summary = try reuse ? engine.inspect(inspectionTemplate) : engine.inspect(template: inspectionSource)
                    let payload = summary.variableRoots.joined(separator: ",") + "|"
                        + summary.filterNames.joined(separator: ",") + "|"
                        + summary.literalPartialNames.joined(separator: ",") + "|" + String(summary.hasDynamicPartials)
                    guard payload == expectedInspection else { throw BenchmarkFailure("Inspection summary mismatch") }
                    for byte in payload.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
                }
                let duration = start.duration(to: clock.now).components
                if sample >= 0 { timings.append((Double(duration.seconds) * 1_000_000_000 + Double(duration.attoseconds) / 1_000_000_000) / Double(repetitions)) }
            }
            timings.sort()
            records.append(["name": "inspection", "mode": reuse ? "inspect-reused-template" : "parse-and-inspect",
                "samples": samples, "warmupSamples": 10, "repetitionsPerSample": repetitions,
                "medianNanoseconds": timings[samples / 2], "p95Nanoseconds": timings[Int(ceil(Double(samples) * 0.95)) - 1],
                "minimumNanoseconds": timings[0], "maximumNanoseconds": timings[samples - 1],
                "outputBytes": expectedInspection.utf8.count, "fnv1aChecksum": String(checksum, radix: 16)])
        }
        let result: [String: Any] = ["schemaVersion": 1, "platform": ProcessInfo.processInfo.operatingSystemVersionString,
                                     "configuration": "release", "workloads": records]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        if CommandLine.arguments.count > 1 { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic) }
        print(String(decoding: data, as: UTF8.self))
        #endif
    }
}

private struct BenchmarkFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
