// SPDX-License-Identifier: Apache-2.0 AND BSD-2-Clause
// Adapted from Ruby Date 3.5.1 date_parse.c, coded by Tadayoshi Funaba (2011, 2012).
// Original Ruby copyright/terms are retained in Licenses/RubyDate.
// Swift adaptation: checked values, immutable regexes, invocation-owned fragments.
import Foundation

internal struct DateFragments {
    var year: Int?, month: Int?, day: Int?, ordinal: Int?
    var hour: Int?, minute: Int?, second: Int?
    var fraction: String?, zone: String?
    var completeYear = true
    var beforeCommonEra = false
}

private enum DatePatterns {
    static let compiled: Result<[String: NSRegularExpression], Error> = Result {
        let sources: [String: String] = [
            "day": #"\b(sun|mon|tue|wed|thu|fri|sat)[^-/0-9\s]*"#,
            "time": #"((?<![0-9])[0-9]+\s*(?:(?::\s*[0-9]+(?:\s*:\s*[0-9]+(?:[,.][0-9]*)?)?|h(?:\s*[0-9]+m?(?:\s*[0-9]+s?)?)?)(?:\s*[ap](?:m\b|\.m\.))?|[ap](?:m\b|\.m\.)))(?:\s*((?:gmt|utc?)?[-+][0-9]+(?:[,.:][0-9]+(?::[0-9]+)?)?|(?-i:[[:alpha:].\s]+)(?:standard|daylight)\stime\b|(?-i:[[:alpha:]]+)(?:\sdst)?\b))?"#,
            "eu": #"('?(?<![0-9])[0-9]+)[^-0-9\s]*\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^-0-9\s']*(?:\s*(?:\b(c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|a(?:d|\.d\.)|b(?:c|\.c\.))(?!(?<!\.)[a-z]))?\s*('?-?[0-9]+(?:(?:st|nd|rd|th)\b)?))?"#,
            "us": #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^-0-9\s']*\s*('?[0-9]+)[^-0-9\s']*(?:\s*+,?\s*+(c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|a(?:d|\.d\.)|b(?:c|\.c\.))?\s*('?-?[0-9]+))?"#,
            "iso": #"('?[-+]?(?<![0-9])[0-9]+)-([0-9]+)-('?-?[0-9]+)"#,
            "iso21": #"\b([0-9]{2}|[0-9]{4})?-?w([0-9]{2})(?:-?([0-9]))?\b"#,
            "iso22": #"-w-([0-9])\b"#,
            "iso23": #"--([0-9]{2})?-([0-9]{2})\b"#,
            "iso24": #"--([0-9]{2})([0-9]{2})?\b"#,
            "iso25Guard": #"[,.]([0-9]{2}|[0-9]{4})-[0-9]{3}\b"#,
            "iso25": #"\b([0-9]{2}|[0-9]{4})-([0-9]{3})\b"#,
            "iso26Guard": #"[0-9]-[0-9]{3}\b"#,
            "iso26": #"\b-([0-9]{3})\b"#,
            "jis": #"\b([mtshr])([0-9]+)\.([0-9]+)\.([0-9]+)"#,
            "vms11": #"('?-?(?<![0-9])[0-9]+)-(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^-/.]*-('?-?[0-9]+)"#,
            "vms12": #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^-/.]*-('?-?[0-9]+)(?:-('?-?[0-9]+))?"#,
            "sla": #"('?-?(?<![0-9])[0-9]+)/\s*('?[0-9]+)(?:[^0-9]\s*('?-?[0-9]+))?"#,
            "dot": #"('?-?(?<![0-9])[0-9]+)\.\s*('?[0-9]+)\.\s*('?-?[0-9]+)"#,
            "year": #"'([0-9]+)\b"#,
            "mon": #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\S*"#,
            "mday": #"((?<![0-9])[0-9]+)(st|nd|rd|th)\b"#,
            "ddd": #"([-+]?)((?<![0-9])[0-9]{2,14})(?:\s*t?\s*([0-9]{2,6})?(?:[,.]([0-9]*))?)?(?:\s*(z\b|[-+][0-9]{1,4}\b|\[[-+]?[0-9][^\]]*\]))?"#,
            "bc": #"\b(bc\b|bce\b|b\.c\.|b\.c\.e\.)"#,
            "frag": #"\A\s*([0-9]{1,2})\s*\z"#,
            "timeFields": #"\A([0-9]+)h?(?:\s*:?\s*([0-9]+)m?(?:\s*:?\s*([0-9]+)(?:[,.]([0-9]+))?s?)?)?(?:\s*([ap])(?:m\b|\.m\.))?"#,
            "normalize": #"[^-+',./:@[:alnum:]\[\]]+"#,
        ]
        return try sources.mapValues { try NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }
}

/// Ruby Date's loose-parser production order. Time.parse consumes only the
/// calendar/time/zone fields; weekday and ISO commercial-week fields do not
/// supply a calendar date to Time.make_time.
internal struct RubyDateParser {
    private var text: String
    private var value = DateFragments()
    private let patterns: [String: NSRegularExpression]

    init(_ source: String, completeYear: Bool = true) throws {
        value.completeYear = completeYear
        patterns = try DatePatterns.compiled.get()
        let regex = patterns["normalize"]!
        text = regex.stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: " ")
    }

    private func find(_ name: String, in input: String) -> (NSTextCheckingResult, [String?])? {
        guard let regex = patterns[name], let result = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { return nil }
        return (result, (0..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: input).map { String(input[$0]) }
        })
    }
    private mutating func take(_ name: String) -> [String?]? {
        guard let (result, groups) = find(name, in: text), let range = Range(result.range, in: text) else { return nil }
        text.replaceSubrange(range, with: " ")
        return groups
    }
    private func integer(_ spelling: String?) throws -> Int? {
        guard let spelling else { return nil }
        guard let result = Int(spelling) else { throw LiquidError.invalidValue("Date component is outside Int") }
        return result
    }
    private func month(_ spelling: String?) -> String? {
        guard let spelling, let index = liquidMonthNames.firstIndex(where: { $0.lowercased().prefix(3) == spelling.lowercased().prefix(3) }) else { return nil }
        return String(index + 1)
    }

    /// Preserve s3e's field rotations before interpreting numeric prefixes.
    private mutating func calendar(_ originalYear: String?, _ originalMonth: String?, _ originalDay: String?, bc: Bool = false) throws {
        var y = originalYear, m = originalMonth, d = originalDay
        if y != nil && m != nil && d == nil { (y, m, d) = (d, y, m) }
        if y == nil {
            if let day = d, day.utf8.count > 2 { y = d; d = nil }
            if d?.first == "'" { y = d; d = nil }
        }
        func numericPrefix(_ spelling: String, signed: Bool) -> String? {
            let bytes = Array(spelling.utf8)
            guard let start = bytes.firstIndex(where: { (48...57).contains($0) || (signed && ($0 == 43 || $0 == 45)) }) else { return nil }
            var end = start
            if signed && (bytes[end] == 43 || bytes[end] == 45) { end += 1 }
            while end < bytes.count && (48...57).contains(bytes[end]) { end += 1 }
            guard end > start else { return nil }
            return String(decoding: bytes[start..<end], as: UTF8.self)
        }
        if let year = y, let prefix = numericPrefix(year, signed: true), !year.hasSuffix(prefix) {
            y = d; d = prefix
        }
        if let mon = m, mon.first == "'" || mon.utf8.count > 2 { (y, m, d) = (m, d, y) }
        if let day = d, day.first == "'" || day.utf8.count > 2 { (y, d) = (d, y) }
        if let year = y, let prefix = numericPrefix(year, signed: true) {
            if prefix.first == "+" || prefix.first == "-" || prefix.utf8.count > 2 { value.completeYear = false }
            value.year = try integer(prefix)
        }
        if bc { value.beforeCommonEra = true }
        if let mon = m, let prefix = numericPrefix(mon, signed: false) { value.month = try integer(prefix) }
        if let day = d, let prefix = numericPrefix(day, signed: false) { value.day = try integer(prefix) }
    }

    mutating func parse() throws -> DateFragments {
        _ = take("day")
        if let time = take("time") {
            value.zone = time[2]
            if let input = time[1], let (_, fields) = find("timeFields", in: input) {
                value.hour = try integer(fields[1]); value.minute = try integer(fields[2]); value.second = try integer(fields[3]); value.fraction = fields[4]
                if let meridian = fields[5], let hour = value.hour { value.hour = hour % 12 + (meridian.lowercased() == "p" ? 12 : 0) }
            }
        }
        if let g = take("eu") { try calendar(g[4], month(g[2]), g[1], bc: g[3]?.lowercased().first == "b") }
        else if let g = take("us") { try calendar(g[4], month(g[1]), g[2], bc: g[3]?.lowercased().first == "b") }
        else if let g = take("iso") { try calendar(g[1], g[2], g[3]) }
        else if let g = take("jis") {
            let eras = ["m": 1867, "t": 1911, "s": 1925, "h": 1988, "r": 2018]
            if let year = try integer(g[2]) {
                let (result, overflow) = year.addingReportingOverflow(eras[g[1]!.lowercased()] ?? 0)
                guard !overflow else { throw LiquidError.invalidValue("Date year overflow") }
                value.year = result
            }
            value.month = try integer(g[3]); value.day = try integer(g[4])
        }
        else if let g = take("vms11") { try calendar(g[3], month(g[2]), g[1]) }
        else if let g = take("vms12") { try calendar(g[3], month(g[1]), g[2]) }
        else if let g = take("sla") { try calendar(g[1], g[2], g[3]) }
        else if let g = take("dot") { try calendar(g[1], g[2], g[3]) }
        else if take("iso21") != nil || take("iso22") != nil { /* Time.parse ignores commercial-week fields. */ }
        else if let g = take("iso23") { value.month = try integer(g[1]); value.day = try integer(g[2]) }
        else if let g = take("iso24") { value.month = try integer(g[1]); value.day = try integer(g[2]) }
        else if find("iso25Guard", in: text) == nil, let g = take("iso25") { value.year = try integer(g[1]); value.ordinal = try integer(g[2]) }
        else if find("iso26Guard", in: text) == nil, let g = take("iso26") { value.ordinal = try integer(g[1]) }
        else if let g = take("year") { value.year = try integer(g[1]) }
        else if let g = take("mon") { value.month = try integer(month(g[1])) }
        else if let g = take("mday") { value.day = try integer(g[1]) }
        else if let g = take("ddd") { try digits(g) }
        if take("bc") != nil { value.beforeCommonEra = true }
        if let g = take("frag"), let number = try integer(g[1]) {
            if value.hour != nil && value.day == nil && (1...31).contains(number) { value.day = number }
            if value.day != nil && value.hour == nil && (0...24).contains(number) { value.hour = number }
        }
        if value.beforeCommonEra, let year = value.year {
            let (result, overflow) = 1.subtractingReportingOverflow(year)
            guard !overflow else { throw LiquidError.invalidValue("Date year overflow") }
            value.year = result
        }
        if value.completeYear, let year = value.year, (0...99).contains(year) { value.year = year + (year >= 69 ? 1900 : 2000) }
        return value
    }

    private mutating func digits(_ groups: [String?]) throws {
        guard let digits = groups[2] else { return }
        let bytes = Array(digits.utf8), length = bytes.count
        func number(_ start: Int, _ width: Int) -> Int { bytes[start..<(start + width)].reduce(0) { $0 * 10 + Int($1 - 48) } }
        func year(_ start: Int, _ width: Int) -> Int { number(start, width) * (groups[1] == "-" ? -1 : 1) }
        let backwards = groups[3] == nil && groups[4] != nil
        if backwards && [2, 3, 4, 5, 6, 7, 8, 10, 12, 14].contains(length) {
            if length >= 2 { value.second = number(length - 2, 2) }
            if length >= 3 { value.minute = number(max(0, length - 4), min(2, length - 2)) }
            if length >= 5 { value.hour = number(max(0, length - 6), min(2, length - 4)) }
            if length >= 7 { value.day = number(max(0, length - 8), min(2, length - 6)) }
            if length >= 10 { value.month = number(length - 10, 2) }
            if length == 12 { value.year = year(0, 2) }
            if length == 14 { value.year = year(0, 4); value.completeYear = false }
        } else {
            switch length {
            case 2: value.day = number(0, 2)
            case 4: value.month = number(0, 2); value.day = number(2, 2)
            case 6: value.year = year(0, 2); value.month = number(2, 2); value.day = number(4, 2)
            case 8, 10, 12, 14:
                value.year = year(0, 4); value.month = number(4, 2); value.day = number(6, 2); value.completeYear = false
                if length >= 10 { value.hour = number(8, 2) }
                if length >= 12 { value.minute = number(10, 2) }
                if length >= 14 { value.second = number(12, 2) }
            case 3: value.ordinal = number(0, 3)
            case 5: value.year = year(0, 2); value.ordinal = number(2, 3)
            case 7: value.year = year(0, 4); value.ordinal = number(4, 3)
            default: break
            }
        }
        if let time = groups[3] {
            let clock = Array(time.utf8), count = clock.count
            func n(_ start: Int) -> Int { Int(clock[start] - 48) * 10 + Int(clock[start + 1] - 48) }
            if [2, 4, 6].contains(count) {
                if groups[4] != nil {
                    value.second = n(count - 2)
                    if count >= 4 { value.minute = n(count - 4) }
                    if count >= 6 { value.hour = n(count - 6) }
                } else {
                    value.hour = n(0)
                    if count >= 4 { value.minute = n(2) }
                    if count >= 6 { value.second = n(4) }
                }
            }
        }
        if let fraction = groups[4] { value.fraction = fraction }
        if var zone = groups[5] {
            if zone.first == "[" {
                zone.removeFirst(); zone.removeLast()
                if let colon = zone.firstIndex(of: ":") { zone = String(zone[zone.index(after: colon)...]) }
            }
            value.zone = zone
        }
    }
}
