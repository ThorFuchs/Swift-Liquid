// SPDX-License-Identifier: Apache-2.0
import Foundation

// Render directives separately so literal text never becomes an ICU date pattern.
internal func renderStrftime(_ format: String, date: Date, offset: Int = 0, zoneName: String = "UTC") throws -> String {
    var calendar = Calendar(identifier: .gregorian)
    guard let timeZone = TimeZone(secondsFromGMT: offset) else { throw LiquidError.invalidValue("Invalid date offset") }
    calendar.timeZone = timeZone
    var iso = Calendar(identifier: .iso8601)
    iso.timeZone = calendar.timeZone
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
    guard let year = components.year, (1...9999).contains(year) else { throw LiquidError.invalidValue("Date year must be in 1...9999") }
    let month = components.month ?? 1, day = components.day ?? 1
    let hour = components.hour ?? 0, minute = components.minute ?? 0, second = components.second ?? 0
    let weekday = (components.weekday ?? 1) - 1
    let ordinal = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    func pad(_ value: Int, _ width: Int = 2, with character: Character = "0") -> String {
        let text = String(value)
        return String(repeating: String(character), count: max(0, width - text.count)) + text
    }
    let datePart = "\(pad(year, 4))-\(pad(month))-\(pad(day))"
    let timePart = "\(pad(hour)):\(pad(minute)):\(pad(second))"
    let hour12 = hour % 12 == 0 ? 12 : hour % 12
    var result = ""
    var index = format.startIndex
    while index < format.endIndex {
        try Task.checkCancellation()
        guard format[index] == "%" else {
            result.append(format[index]); index = format.index(after: index); continue
        }
        let start = index
        index = format.index(after: index)
        guard index < format.endIndex else { result.append("%"); break }
        var uppercase = false
        var unpadded = false
        var spacePadded = false
        var width: Int?
        while index < format.endIndex {
            let char = format[index]
            if char == "^" { uppercase = true }
            else if char == "-" { unpadded = true }
            else if char == "_" { spacePadded = true }
            else if char == "0" && width == nil { }
            else if let digit = char.wholeNumberValue {
                let next = (width ?? 0) * 10 + digit
                guard next <= 1024 else { throw LiquidError.limitExceeded("date padding") }
                width = next
            } else { break }
            index = format.index(after: index)
        }
        guard index < format.endIndex else { result += format[start...]; break }
        let directive = format[index]
        index = format.index(after: index)
        var value: String
        switch directive {
        case "Y": value = pad(year, 4)
        case "y": value = pad(year % 100)
        case "C": value = pad(year / 100)
        case "m": value = pad(month)
        case "d": value = pad(day)
        case "e": value = pad(day, with: " ")
        case "H": value = pad(hour)
        case "k": value = pad(hour, with: " ")
        case "I": value = pad(hour12)
        case "l": value = pad(hour12, with: " ")
        case "M": value = pad(minute)
        case "S": value = pad(second)
        case "p": value = hour < 12 ? "AM" : "PM"
        case "P": value = hour < 12 ? "am" : "pm"
        case "B": value = monthNames[month - 1]
        case "b", "h": value = String(monthNames[month - 1].prefix(3))
        case "A": value = weekdayNames[weekday]
        case "a": value = String(weekdayNames[weekday].prefix(3))
        case "j": value = pad(ordinal, 3)
        case "w": value = String(weekday)
        case "u": value = String(weekday == 0 ? 7 : weekday)
        case "V": value = pad(iso.component(.weekOfYear, from: date))
        case "G": value = pad(iso.component(.yearForWeekOfYear, from: date), 4)
        case "g": value = pad(iso.component(.yearForWeekOfYear, from: date) % 100)
        case "U": value = pad((ordinal - 1 + 7 - weekday) / 7)
        case "W": value = pad((ordinal - 1 + 7 - (weekday + 6) % 7) / 7)
        case "z": value = "\(offset < 0 ? "-" : "+")\(pad(abs(offset) / 3600))\(pad(abs(offset) % 3600 / 60))"
        case "Z": value = zoneName
        case "s": value = String(try checkedInteger(date.timeIntervalSince1970))
        case "F": value = datePart
        case "T", "X": value = timePart
        case "R": value = "\(pad(hour)):\(pad(minute))"
        case "D", "x": value = "\(pad(month))/\(pad(day))/\(pad(year % 100))"
        case "r": value = "\(pad(hour12)):\(pad(minute)):\(pad(second)) \(hour < 12 ? "AM" : "PM")"
        case "c": value = "\(weekdayNames[weekday].prefix(3)) \(monthNames[month - 1].prefix(3)) \(pad(day, with: " ")) \(timePart) \(year)"
        case "v": value = "\(pad(day, with: " "))-\(monthNames[month - 1].prefix(3))-\(pad(year, 4))"
        case "n": value = "\n"
        case "t": value = "\t"
        case "%": value = "%"
        default: value = String(format[start..<index])
        }
        if unpadded { value = String(value.drop(while: { $0 == "0" || $0 == " " })); if value.isEmpty { value = "0" } }
        if uppercase { value = value.uppercased() }
        if spacePadded { value = value.replacingOccurrences(of: "^0+", with: String(repeating: " ", count: value.prefix(while: { $0 == "0" }).count), options: .regularExpression) }
        if let width { value = String(repeating: spacePadded ? " " : "0", count: max(0, width - value.count)) + value }
        result += value
    }
    return result
}
