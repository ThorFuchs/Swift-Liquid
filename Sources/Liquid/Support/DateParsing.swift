// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Integral epoch seconds and decimal subseconds are kept separately. Foundation
/// Date's binary floating-point storage cannot retain a parsed nanosecond spelling.
internal struct LiquidDate {
    let seconds: Int
    let fraction: String
    let offset: Int
    var zoneName: String { offset == 0 ? "UTC" : "" }

    init(seconds: Int, fraction: String = "", offset: Int = 0) throws {
        // Validate before adding the offset or passing values to calendar code.
        guard (-62_135_683_199...253_402_387_198).contains(seconds), (-86_399...86_399).contains(offset) else {
            throw LiquidError.invalidValue("Date year must be in 1...9999")
        }
        let local = seconds + offset
        guard (-62_135_596_800...253_402_300_799).contains(local) else {
            throw LiquidError.invalidValue("Date year must be in 1...9999")
        }
        self.seconds = seconds; self.fraction = fraction; self.offset = offset
    }

    static func now() throws -> Self {
        let epoch = Date().timeIntervalSince1970
        let seconds = try checkedInteger(epoch.rounded(.down))
        let nanos = Int((epoch - Double(seconds)) * 1_000_000_000)
        let digits = String(nanos)
        return try Self(seconds: seconds, fraction: String(repeating: "0", count: 9 - digits.count) + digits)
    }
}

/// The proleptic Gregorian calendar used by Ruby Time, including before 1582.
internal struct LiquidDateParts {
    let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
    let ordinal: Int, weekday: Int, isoYear: Int, isoWeek: Int

    static func isLeap(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }
    static func daysBeforeYear(_ year: Int) -> Int {
        let previous = year - 1
        return 365 * previous + previous / 4 - previous / 100 + previous / 400
    }
    static func daysBeforeMonth(_ month: Int, year: Int) -> Int {
        let common = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        return common[month - 1] + (month > 2 && isLeap(year) ? 1 : 0)
    }
    static func epochDay(year: Int, month: Int, day: Int) -> Int {
        daysBeforeYear(year) + daysBeforeMonth(month, year: year) + day - 1 - 719_162
    }
    private static func sundayWeekday(_ day: Int) -> Int { ((day + 4) % 7 + 7) % 7 }
    private static func firstISOWeek(_ year: Int) -> Int {
        let january4 = epochDay(year: year, month: 1, day: 4)
        return january4 - (sundayWeekday(january4) + 6) % 7
    }

    init(_ date: LiquidDate) {
        let local = date.seconds + date.offset
        // Swift integer division truncates; calendar days require floor division.
        let epochDay = local / 86_400 - (local % 86_400 < 0 ? 1 : 0)
        let secondsOfDay = local - epochDay * 86_400
        let absoluteDay = epochDay + 719_162
        var lower = 1, upper = 10_000
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if Self.daysBeforeYear(middle) <= absoluteDay { lower = middle } else { upper = middle }
        }
        year = lower
        ordinal = absoluteDay - Self.daysBeforeYear(year) + 1
        var selectedMonth = 1
        while selectedMonth < 12 && Self.daysBeforeMonth(selectedMonth + 1, year: year) < ordinal { selectedMonth += 1 }
        month = selectedMonth
        day = ordinal - Self.daysBeforeMonth(month, year: year)
        hour = secondsOfDay / 3600; minute = secondsOfDay % 3600 / 60; second = secondsOfDay % 60
        weekday = Self.sundayWeekday(epochDay)
        var weekYear = year
        if epochDay < Self.firstISOWeek(year) { weekYear -= 1 }
        else if epochDay >= Self.firstISOWeek(year + 1) { weekYear += 1 }
        isoYear = weekYear
        isoWeek = (epochDay - Self.firstISOWeek(weekYear)) / 7 + 1
    }
}

internal let liquidMonthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
internal let liquidWeekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

/// Recognizes complete calendar/ordinal dates and English RFC/asctime forms.
/// It deliberately does not guess missing date components from the system clock.
internal func parseLiquidDate(_ source: String) throws -> LiquidDate? {
    try Task.checkCancellation()
    var text = source.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    func match(_ pattern: String, _ input: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: input).map { String(input[$0]) } ?? ""
        }
    }
    func completeYear(_ spelling: String) -> Int? {
        guard let value = Int(spelling) else { return nil }
        return spelling.count <= 2 ? value + (value >= 69 ? 1900 : 2000) : value
    }
    // Expand the basic timestamp spelling before the common parser below.
    if let basic = match(#"^(\d{4})(\d{2})(\d{2})t(\d{2})(\d{2})(\d{2})(\.\d+)?(.*)$"#, text) {
        text = "\(basic[1])-\(basic[2])-\(basic[3])t\(basic[4]):\(basic[5]):\(basic[6])\(basic[7])\(basic[8])"
    }
    if let weekday = match(#"^(?:sun(?:day)?|mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?)\s*,?\s*"#, text) {
        text.removeFirst(weekday[0].count)
    }
    var hour = 0, minute = 0, second = 0, offset = 0, fraction = ""
    if let time = match(#"(?:[t\s])?(\d{1,2}):(\d{2})(?::(\d{2})(?:[.,](\d+))?)?"#, text),
       let range = text.range(of: time[0]) {
        hour = Int(time[1]) ?? 0; minute = Int(time[2]) ?? 0; second = Int(time[3]) ?? 0; fraction = time[4]
        var tail = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let meridian = match(#"^(am|pm)\b\s*"#, tail) {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridian[1] == "pm" ? 12 : 0)
            tail.removeFirst(meridian[0].count)
        }
        if let zone = match(#"^([+-]\d{2}(?::?\d{2})?(?::?\d{2})?|[a-z]+)\s*$"#, tail) {
            let spelling = zone[1]
            if spelling.first == "+" || spelling.first == "-" {
                let digits = spelling.dropFirst().replacingOccurrences(of: ":", with: "")
                guard [2, 4, 6].contains(digits.count), let hours = Int(digits.prefix(2)) else { return nil }
                let minutes = digits.count >= 4 ? Int(digits.dropFirst(2).prefix(2)) ?? 0 : 0
                let seconds = digits.count == 6 ? Int(digits.suffix(2)) ?? 0 : 0
                guard hours < 24, minutes < 60, seconds < 60 else { return nil }
                offset = (hours * 3600 + minutes * 60 + seconds) * (spelling.first == "-" ? -1 : 1)
            } else {
                // RFC 822 abbreviations; unrecognized zones are ignored in UTC,
                // as Time.parse does when they do not name the reference's zone.
                let hours = ["ut": 0, "utc": 0, "gmt": 0, "z": 0, "est": -5, "edt": -4, "cst": -6, "cdt": -5, "mst": -7, "mdt": -6, "pst": -8, "pdt": -7]
                if let known = hours[spelling] { offset = known * 3600 }
                else if spelling.utf8.count == 1, let code = spelling.utf8.first {
                    if (97...105).contains(code) { offset = Int(code - 96) * 3600 }
                    else if (107...109).contains(code) { offset = Int(code - 97) * 3600 }
                    else if (110...121).contains(code) { offset = -Int(code - 109) * 3600 }
                }
            }
            tail = ""
        }
        text = String(text[..<range.lowerBound]) + " " + tail
    }
    guard hour <= 24, minute < 60, second <= 60,
          hour != 24 || (minute == 0 && second == 0 && !fraction.contains(where: { $0 != "0" })) else { return nil }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var year: Int?, month: Int?, day: Int?, ordinal: Int?
    if let numeric = match(#"^(\d{1,4})([-/.])(\d{1,2})\2(\d{1,4})$"#, text) {
        if numeric[1].count >= 3 || (numeric[2] == "-" && numeric[4].count <= 2) {
            year = completeYear(numeric[1]); month = Int(numeric[3]); day = Int(numeric[4])
        } else {
            day = Int(numeric[1]); month = Int(numeric[3]); year = completeYear(numeric[4])
        }
    } else if let date = match(#"^(\d{4})-(\d{3})$"#, text) {
        year = Int(date[1]); ordinal = Int(date[2])
    } else {
        let words = text.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "-", with: " ").split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count == 3, let position = words.firstIndex(where: { word in
            liquidMonthNames.contains { name in name.lowercased() == word || name.lowercased().prefix(3) == word }
        }) {
            month = liquidMonthNames.firstIndex { $0.lowercased() == words[position] || $0.lowercased().prefix(3) == words[position] }.map { $0 + 1 }
            if position == 0 { day = Int(words[1]); year = completeYear(words[2]) }
            else if position == 1 {
                if words[0].count >= 3 { year = completeYear(words[0]); day = Int(words[2]) }
                else { day = Int(words[0]); year = completeYear(words[2]) }
            }
        }
    }
    guard let year else { return nil }
    guard (1...9999).contains(year) else { throw LiquidError.invalidValue("Date year must be in 1...9999") }
    let epochDay: Int
    if let ordinal {
        guard (1...(LiquidDateParts.isLeap(year) ? 366 : 365)).contains(ordinal) else { return nil }
        epochDay = LiquidDateParts.epochDay(year: year, month: 1, day: 1) + ordinal - 1
    } else {
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return nil }
        // Ruby Time normalizes days 29...31 that overflow a shorter month.
        epochDay = LiquidDateParts.epochDay(year: year, month: month, day: day)
    }
    try Task.checkCancellation()
    return try LiquidDate(seconds: epochDay * 86_400 + hour * 3600 + minute * 60 + second - offset, fraction: fraction, offset: offset)
}
