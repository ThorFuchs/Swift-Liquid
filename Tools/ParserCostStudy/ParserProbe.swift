// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import Liquid
private struct DateInput: Decodable, Sendable {
    let name: String, source: String, normalized: String
    let fields: ParserCostFields?
}
private struct MatchInput: Decodable, Sendable {
    let name: String, pattern: String, input: String, remaining: String
    let span: [Int]?
    let groups: [String?]?
}
private struct Configuration: Decodable, Sendable {
    let dates: [DateInput]
    let matches: [MatchInput]
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
    mutating func fields(_ f: ParserCostFields) {
        integer(f.year); integer(f.month); integer(f.day); integer(f.ordinal)
        integer(f.hour); integer(f.minute); integer(f.second)
        optionalString(f.fraction); optionalString(f.zone)
        byte(f.completeYear ? 1 : 0); byte(f.beforeCommonEra ? 1 : 0)
    }
    mutating func value(_ v: ParserCostValue) {
        optionalString(v.text)
        if let span = v.span { byte(1); integer(span.count); for n in span { integer(n) } } else { byte(0) }
        if let groups = v.groups { byte(1); integer(groups.count); for g in groups { optionalString(g) } } else { byte(0) }
        if let f = v.fields { byte(1); fields(f) } else { byte(0) }
    }
}
@main struct ParserProbe {
    nonisolated private static func cpu() throws -> Double {
        var u = rusage()
        guard getrusage(RUSAGE_SELF, &u) == 0 else { throw Failure(message: "getrusage") }
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) * 1e9
            + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) * 1000
    }
    private static func measure(_ name: String, stage: String, expected: ParserCostValue,
        validateOnly: Bool, body: () throws -> ParserCostValue) throws -> [String: Any] {
        var checksum = Audit(), one = Audit()
        one.value(expected)
        if validateOnly {
            let value = try body()
            guard value == expected else { throw Failure(message: "Validation mismatch: \(name)/\(stage)") }
            checksum.value(value)
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
                checksum.value(value)
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
        var plans: [() throws -> [String: Any]] = []
        func add(_ name: String, stage: String, expected: ParserCostValue,
            body: @escaping () throws -> ParserCostValue) {
            plans.append { try measure(name, stage: stage, expected: expected,
                validateOnly: validateOnly, body: body) }
            plans.append { try measure(name, stage: stage + "-audit", expected: expected,
                validateOnly: validateOnly, body: { LiquidParserCostProbe.control(expected) }) }
        }
        for input in config.dates {
            let p = try LiquidParserCostProbe.prepare(input.source)
            let expected = ParserCostValue(text: input.normalized)
            add(input.name, stage: "normalize", expected: expected, body: { LiquidParserCostProbe.normalize(p) })
            add(input.name, stage: "construct", expected: expected, body: { try LiquidParserCostProbe.construct(p) })
            if let fields = input.fields {
                add(input.name, stage: "grammar", expected: .init(fields: fields), body: { try LiquidParserCostProbe.grammar(p) })
            }
        }
        for input in config.matches {
            let p = try LiquidParserCostProbe.prepare(input.input, pattern: input.pattern)
            add(input.name, stage: "match", expected: .init(span: input.span), body: { LiquidParserCostProbe.match(p) })
            add(input.name, stage: "captures", expected: .init(groups: input.groups), body: { LiquidParserCostProbe.captures(p) })
            add(input.name, stage: "find", expected: .init(groups: input.groups), body: { LiquidParserCostProbe.find(p) })
            add(input.name, stage: "take", expected: .init(text: input.remaining, groups: input.groups), body: { LiquidParserCostProbe.take(p) })
        }
        if order == "reverse" { plans.reverse() }
        let records = try plans.map { try $0() }
        guard records.count == 100 else { throw Failure(message: "Record shape") }
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
