// SPDX-License-Identifier: Apache-2.0 AND BSD-2-Clause
// Time.parse defaults adapted from Ruby Time 0.4.2; terms in Licenses/RubyDate.
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

    static func from(_ date: Date) throws -> Self {
        let epoch = date.timeIntervalSince1970
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

/// Apply Time.make_time's defaults after Date._parse's heuristic recognition.
/// The reference's timezone is UTC; unrecognized abbreviations use that zone.
internal func parseLiquidDate(_ source: String, referenceTime: Date) throws -> LiquidDate? {
    try Task.checkCancellation()
    // Date._parse's default length limit is bytes, after Liquid lowercases input.
    guard source.utf8.count <= 128 else { return nil }
    var parser = try RubyDateParser(source)
    let fields = try parser.parse()
    guard fields.year != nil || fields.month != nil || fields.day != nil || fields.ordinal != nil || fields.hour != nil || fields.minute != nil || fields.second != nil || fields.fraction != nil else { return nil }
    let offset = timeZoneOffset(fields.zone ?? "")
    guard (-86_399...86_399).contains(offset) else { return nil }
    let clock = try LiquidDate.from(referenceTime)
    let now = LiquidDateParts(try LiquidDate(seconds: clock.seconds, fraction: clock.fraction, offset: offset))
    var year = fields.year, month = fields.month, day = fields.day
    var hour = fields.hour, minute = fields.minute, second = fields.second
    var fraction = fields.fraction
    // Fill missing upper fields from the base clock until the first supplied
    // field. Unspecified lower fields then take their minimum values.
    if year == nil {
        year = now.year
        if month == nil && fields.ordinal == nil {
            month = now.month
            if day == nil {
                day = now.day
                if hour == nil {
                    hour = now.hour
                    if minute == nil {
                        minute = now.minute
                        if second == nil {
                            second = now.second
                            if fraction == nil { fraction = clock.fraction }
                        }
                    }
                }
            }
        }
    }
    let y = year ?? 1970, mon = month ?? 1, d = day ?? 1
    let h = hour ?? 0, m = minute ?? 0, s = second ?? 0
    guard (1...12).contains(mon), (1...31).contains(d), (0...24).contains(h), (0...59).contains(m), (0...60).contains(s),
          h != 24 || (m == 0 && s == 0) else { return nil }
    guard (1...9999).contains(y) else { throw LiquidError.invalidValue("Date year must be in 1...9999") }
    let epochDay: Int
    if let ordinal = fields.ordinal {
        guard (1...(LiquidDateParts.isLeap(y) ? 366 : 365)).contains(ordinal) else { return nil }
        epochDay = LiquidDateParts.epochDay(year: y, month: 1, day: 1) + ordinal - 1
    } else {
        epochDay = LiquidDateParts.epochDay(year: y, month: mon, day: d)
    }
    try Task.checkCancellation()
    return try LiquidDate(seconds: epochDay * 86_400 + h * 3600 + m * 60 + s - offset, fraction: fraction ?? "", offset: offset)
}

private func timeZoneOffset(_ original: String) -> Int {
    let zone = original.lowercased()
    let named = ["ut": 0, "utc": 0, "gmt": 0, "z": 0, "est": -5, "edt": -4, "cst": -6, "cdt": -5, "mst": -7, "mdt": -6, "pst": -8, "pdt": -7]
    if let hours = named[zone] { return hours * 3600 }
    if zone.utf8.count == 1, let code = zone.utf8.first {
        if (97...105).contains(code) { return Int(code - 96) * 3600 }
        if (107...109).contains(code) { return Int(code - 97) * 3600 }
        if (110...121).contains(code) { return -Int(code - 109) * 3600 }
    }
    guard zone.first == "+" || zone.first == "-" else { return 0 }
    let sign = zone.first == "-" ? -1 : 1
    let digits = zone.dropFirst()
    let pieces: [String]
    if digits.contains(":") {
        pieces = digits.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard [2, 3].contains(pieces.count), pieces.allSatisfy({ $0.utf8.count == 2 }) else { return 0 }
    } else {
        let bytes = Array(digits.utf8)
        guard [2, 4, 6].contains(bytes.count) else { return 0 }
        pieces = stride(from: 0, to: bytes.count, by: 2).map { String(decoding: bytes[$0..<($0 + 2)], as: UTF8.self) }
    }
    guard pieces.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return 0 }
    return sign * ((Int(pieces[0]) ?? 0) * 3600 + (pieces.count > 1 ? (Int(pieces[1]) ?? 0) * 60 : 0) + (pieces.count > 2 ? Int(pieces[2]) ?? 0 : 0))
}
