// SPDX-License-Identifier: Apache-2.0
// Diagnostic-only bridge. Never add this file to the production library.
import Foundation

public struct DateCostDate: Sendable, Equatable, Codable {
    public let seconds: Int
    public let fraction: String
    public let offset: Int
    public init(seconds: Int, fraction: String, offset: Int) {
        self.seconds = seconds; self.fraction = fraction; self.offset = offset
    }
}
public struct DateCostFields: Sendable, Equatable, Codable {
    public let year: Int?, month: Int?, day: Int?, ordinal: Int?
    public let hour: Int?, minute: Int?, second: Int?
    public let fraction: String?, zone: String?
    public let completeYear: Bool, beforeCommonEra: Bool
}
public struct DateCostFormat: Sendable, Equatable, Codable {
    public let output: String
    public let steps: Int
}
public enum LiquidDateCostProbe {
    @inline(never) public static func recognize(_ lowered: String, referenceTime: Date) throws -> DateCostDate? {
        guard let d = try parseLiquidDate(lowered, referenceTime: referenceTime) else { return nil }
        return DateCostDate(seconds: d.seconds, fraction: d.fraction, offset: d.offset)
    }
    @inline(never) public static func fields(_ lowered: String) throws -> DateCostFields {
        var parser = try RubyDateParser(lowered)
        let f = try parser.parse()
        return DateCostFields(year: f.year, month: f.month, day: f.day, ordinal: f.ordinal,
            hour: f.hour, minute: f.minute, second: f.second, fraction: f.fraction,
            zone: f.zone, completeYear: f.completeYear, beforeCommonEra: f.beforeCommonEra)
    }
    @inline(never) public static func format(_ d: DateCostDate, pattern: String) throws -> DateCostFormat {
        let budget = RuntimeBudget(.default)
        let output = try renderStrftime(pattern,
            date: LiquidDate(seconds: d.seconds, fraction: d.fraction, offset: d.offset), budget: budget)
        return DateCostFormat(output: output, steps: budget.limits.renderSteps - budget.remainingSteps)
    }
    @inline(never) public static func lowercase(_ text: String) -> String { text.lowercased() }
    @inline(never) public static func dateControl(_ value: DateCostDate?) -> DateCostDate? { value }
    @inline(never) public static func fieldControl(_ value: DateCostFields) -> DateCostFields { value }
    @inline(never) public static func formatControl(_ value: DateCostFormat) -> DateCostFormat { value }
}
