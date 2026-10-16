
// SPDX-License-Identifier: Apache-2.0
// Diagnostic-only suffix, appended to an archived RubyDateParser.swift.
// Original parser bytes above this suffix are never edited.
extension DateFragments: Sendable {}
extension RubyDateParser: Sendable {}

public struct ParserCostFields: Sendable, Equatable, Codable {
    public let year: Int?, month: Int?, day: Int?, ordinal: Int?
    public let hour: Int?, minute: Int?, second: Int?
    public let fraction: String?, zone: String?
    public let completeYear: Bool, beforeCommonEra: Bool
}
public struct ParserCostValue: Sendable, Equatable, Codable {
    public let text: String?
    public let span: [Int]?
    public let groups: [String?]?
    public let fields: ParserCostFields?
    public init(text: String? = nil, span: [Int]? = nil, groups: [String?]? = nil, fields: ParserCostFields? = nil) {
        self.text = text; self.span = span; self.groups = groups; self.fields = fields
    }
}
public struct ParserCostPlan: Sendable {
    fileprivate let source: String
    fileprivate let name: String
    fileprivate let parser: RubyDateParser
    fileprivate let normalizer: NSRegularExpression
    fileprivate let ranges: [NSRange]?
}
extension RubyDateParser {
    fileprivate func costFind(_ name: String, input: String) -> [String?]? { find(name, in: input)?.1 }
    fileprivate mutating func costTake(_ name: String) -> ParserCostValue { let groups = take(name); return .init(text: text, groups: groups) }
    fileprivate var costText: String { text }
    fileprivate mutating func costSetText(_ input: String) { text = input }
    fileprivate func costMatch(_ name: String, input: String) -> NSTextCheckingResult? {
        guard let regex = patterns[name], let result = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { return nil }
        return result
    }
}
public enum LiquidParserCostProbe {
    public static func prepare(_ input: String, pattern: String = "day") throws -> ParserCostPlan {
        var parser = try RubyDateParser(input)
        // Explicit post-consumption state is prepared outside timing, including
        // a synthetic UTF-16 boundary input that normalization would remove.
        parser.costSetText(input)
        return ParserCostPlan(source: input, name: pattern, parser: parser,
            normalizer: try DatePatterns.compiled.get()["normalize"]!,
            ranges: parser.costMatch(pattern, input: input).map { result in
                (0..<result.numberOfRanges).map { result.range(at: $0) }
            })
    }
    @inline(never) public static func normalize(_ p: ParserCostPlan) -> ParserCostValue {
        .init(text: p.normalizer.stringByReplacingMatches(in: p.source,
            range: NSRange(p.source.startIndex..., in: p.source), withTemplate: " "))
    }
    @inline(never) public static func construct(_ p: ParserCostPlan) throws -> ParserCostValue {
        .init(text: try RubyDateParser(p.source).costText)
    }
    @inline(never) public static func grammar(_ p: ParserCostPlan) throws -> ParserCostValue {
        var parser = try RubyDateParser(p.source); let f = try parser.parse()
        return .init(fields: .init(year: f.year, month: f.month, day: f.day, ordinal: f.ordinal,
            hour: f.hour, minute: f.minute, second: f.second, fraction: f.fraction,
            zone: f.zone, completeYear: f.completeYear, beforeCommonEra: f.beforeCommonEra))
    }
    @inline(never) public static func match(_ p: ParserCostPlan) -> ParserCostValue {
        guard let r = p.parser.costMatch(p.name, input: p.source) else { return .init() }
        return .init(span: [r.range.location, r.range.length, r.numberOfRanges])
    }
    @inline(never) public static func captures(_ p: ParserCostPlan) -> ParserCostValue {
        guard let ranges = p.ranges else { return .init() }
        let input = p.source
        // Immutable range snapshots avoid sharing non-Sendable Foundation match
        // objects. Range validation and String materialization follow find.
        return .init(groups: ranges.map { range in
            Range(range, in: input).map { String(input[$0]) }
        })
    }
    @inline(never) public static func find(_ p: ParserCostPlan) -> ParserCostValue {
        .init(groups: p.parser.costFind(p.name, input: p.source))
    }
    @inline(never) public static func take(_ p: ParserCostPlan) -> ParserCostValue {
        var parser = p.parser; return parser.costTake(p.name)
    }
    @inline(never) public static func control(_ value: ParserCostValue) -> ParserCostValue { value }
}
