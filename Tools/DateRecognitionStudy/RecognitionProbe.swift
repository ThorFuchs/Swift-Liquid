// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import Liquid

private struct Input: Decodable, Sendable {
    let name: String, source: String, lowered: String
    let date: DateCostDate?
    let fields: DateCostFields?
    let format: DateCostFormat?
}
private struct Configuration: Decodable, Sendable {
    let referenceTime: Double
    let pattern: String
    let inputs: [Input]
}
private struct Failure: Error { let message: String }
private struct Audit {
    var hash: UInt64 = 14_695_981_039_346_656_037
    var bytes = 0
    mutating func byte(_ b: UInt8) { hash = (hash ^ UInt64(b)) &* 1_099_511_628_211; bytes += 1 }
    mutating func integer(_ n: Int) {
        let word = UInt64(bitPattern: Int64(n))
        for shift in stride(from: 0, to: 64, by: 8) { byte(UInt8(truncatingIfNeeded: word >> shift)) }
    }
    mutating func integer(_ n: Int?) {
        if let n { byte(1); integer(n) } else { byte(0) }
    }
    mutating func string(_ s: String) { for b in s.utf8 { byte(b) } }
    mutating func optionalString(_ s: String?) {
        if let s { byte(1); integer(s.utf8.count); string(s) } else { byte(0) }
    }
    mutating func date(_ d: DateCostDate?) {
        if let d { byte(1); integer(d.seconds); integer(d.offset); integer(d.fraction.utf8.count); string(d.fraction) }
        else { byte(0) }
    }
    mutating func fields(_ f: DateCostFields) {
        integer(f.year); integer(f.month); integer(f.day); integer(f.ordinal)
        integer(f.hour); integer(f.minute); integer(f.second)
        optionalString(f.fraction); optionalString(f.zone)
        byte(f.completeYear ? 1 : 0); byte(f.beforeCommonEra ? 1 : 0)
    }
    mutating func format(_ f: DateCostFormat) { string(f.output); integer(f.steps) }
}
@main struct RecognitionProbe {
    nonisolated private static func cpu() throws -> Double {
        var u = rusage()
        guard getrusage(RUSAGE_SELF, &u) == 0 else { throw Failure(message: "getrusage") }
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) * 1e9
            + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) * 1000
    }
    private static func measure<T: Equatable>(_ name: String, stage: String, expected: T,
        validateOnly: Bool, body: () throws -> T, audit: (inout Audit, T) -> Void) throws -> [String: Any] {
        var checksum = Audit(), one = Audit()
        audit(&one, expected)
        if validateOnly {
            let value = try body()
            guard value == expected else { throw Failure(message: "Validation mismatch: \(name)/\(stage)") }
            audit(&checksum, value)
            return ["name": name, "stage": stage, "outputBytes": one.bytes,
                "fnv1aChecksum": String(checksum.hash, radix: 16), "validated": true]
        }
        var wall: [Double] = [], utilization: [Double] = []
        let clock = ContinuousClock(), repetitions = 500
        for sample in -10..<25 {
            try Task.checkCancellation()
            let beforeCPU = try cpu(), before = clock.now
            for _ in 0..<repetitions {
                let value = try body()
                guard value == expected else { throw Failure(message: "Measured mismatch: \(name)/\(stage)") }
                audit(&checksum, value)
            }
            let duration = before.duration(to: clock.now).components
            let deltaCPU = try cpu() - beforeCPU
            if sample >= 0 {
                wall.append((Double(duration.seconds) * 1e9 + Double(duration.attoseconds) / 1e9) / Double(repetitions))
                utilization.append(deltaCPU / Double(repetitions))
            }
        }
        guard checksum.bytes == one.bytes * 35 * repetitions else { throw Failure(message: "Audit byte count") }
        let w = wall.sorted(), c = utilization.sorted()
        guard w.count == 25, c.count == 25, w[0] > 0, c[0] >= 0, c[12] > 0 else { throw Failure(message: "Sample count or resolution") }
        return ["name": name, "stage": stage, "samples": 25, "warmupSamples": 10,
            "repetitionsPerSample": repetitions, "wallSampleNanoseconds": wall,
            "cpuSampleNanoseconds": utilization, "cpuZeroSamples": utilization.filter { $0 == 0 }.count, "wallMedianNanoseconds": w[12],
            "wallP95Nanoseconds": w[23], "cpuMedianNanoseconds": c[12], "cpuP95Nanoseconds": c[23],
            "outputBytes": one.bytes, "fnv1aChecksum": String(checksum.hash, radix: 16)]
    }
    private static func run(_ config: Configuration, caller: String, validateOnly: Bool, order: String) throws -> Data {
        try Task.checkCancellation()
        let reference = Date(timeIntervalSince1970: config.referenceTime)
        var plans: [() throws -> [String: Any]] = []
        func add<T: Equatable>(_ name: String, stage: String, expected: T,
            validateOnly: Bool, body: @escaping () throws -> T,
            audit: @escaping (inout Audit, T) -> Void) {
            plans.append { try measure(name, stage: stage, expected: expected,
                validateOnly: validateOnly, body: body, audit: audit) }
        }
        for input in config.inputs {
            add(input.name, stage: "lowercase", expected: input.lowered, validateOnly: validateOnly,
                body: { LiquidDateCostProbe.lowercase(input.source) }, audit: { $0.string($1) })
            add(input.name, stage: "recognition", expected: input.date, validateOnly: validateOnly,
                body: { try LiquidDateCostProbe.recognize(input.lowered, referenceTime: reference) }, audit: { $0.date($1) })
            add(input.name, stage: "recognition-audit", expected: input.date, validateOnly: validateOnly,
                body: { LiquidDateCostProbe.dateControl(input.date) }, audit: { $0.date($1) })
            if let fields = input.fields {
                add(input.name, stage: "grammar", expected: fields, validateOnly: validateOnly,
                    body: { try LiquidDateCostProbe.fields(input.lowered) }, audit: { $0.fields($1) })
                add(input.name, stage: "grammar-audit", expected: fields, validateOnly: validateOnly,
                    body: { LiquidDateCostProbe.fieldControl(fields) }, audit: { $0.fields($1) })
            }
            if let date = input.date, let formatted = input.format {
                add(input.name, stage: "format", expected: formatted, validateOnly: validateOnly,
                    body: { try LiquidDateCostProbe.format(date, pattern: config.pattern) }, audit: { $0.format($1) })
                add(input.name, stage: "format-audit", expected: formatted, validateOnly: validateOnly,
                    body: { LiquidDateCostProbe.formatControl(formatted) }, audit: { $0.format($1) })
            }
        }
        if order == "reverse" { plans.reverse() }
        let records = try plans.map { try $0() }
        guard records.count == 29 else { throw Failure(message: "Record shape") }
        try Task.checkCancellation()
        return try JSONSerialization.data(withJSONObject: ["configuration": "release", "caller": caller,
            "recordOrder": order, "kind": validateOnly ? "validation" : "measurement", "records": records], options: [.prettyPrinted, .sortedKeys])
    }
    @MainActor private static func actor(_ c: Configuration, validateOnly: Bool, order: String) async throws -> Data {
        try run(c, caller: "actor", validateOnly: validateOnly, order: order)
    }
    @concurrent private static func concurrent(_ c: Configuration, validateOnly: Bool, order: String) async throws -> Data {
        try run(c, caller: "concurrent", validateOnly: validateOnly, order: order)
    }
    static func main() async throws {
        #if DEBUG
        throw Failure(message: "Release build required")
        #else
        guard [5, 6].contains(CommandLine.arguments.count) else { throw Failure(message: "OUTPUT CALLER INPUTS ORDER [--validate-only]") }
        let caller = CommandLine.arguments[2], order = CommandLine.arguments[4], only = CommandLine.arguments.count == 6
        guard ["actor", "concurrent"].contains(caller), ["forward", "reverse"].contains(order), !only || CommandLine.arguments[5] == "--validate-only" else { throw Failure(message: "Arguments") }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
        let data = try await caller == "actor" ? actor(config, validateOnly: only, order: order) : concurrent(config, validateOnly: only, order: order)
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
        print(String(decoding: data, as: UTF8.self))
        #endif
    }
}
