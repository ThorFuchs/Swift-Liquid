// SPDX-License-Identifier: Apache-2.0
import Foundation

// Directives are rendered separately so literal text cannot become an ICU pattern.
internal func renderStrftime(_ format: String, date: LiquidDate, budget: RuntimeBudget) throws -> String {
    let parts = LiquidDateParts(date)
    let symbols = format.unicodeScalars
    enum Padding { case zero, space, none }
    func padded(_ value: String, width: Int, padding: Padding) -> String {
        guard padding != .none, value.count < width else { return value }
        let fill = String(repeating: padding == .space ? " " : "0", count: width - value.count)
        if padding == .zero && (value.first == "-" || value.first == "+") { return String(value.prefix(1)) + fill + value.dropFirst() }
        return fill + value
    }
    func number(_ value: Int, _ width: Int = 2, _ padding: Padding = .zero) -> String {
        padded(String(value), width: width, padding: padding)
    }
    let datePart = "\(number(parts.year, 4))-\(number(parts.month))-\(number(parts.day))"
    let timePart = "\(number(parts.hour)):\(number(parts.minute)):\(number(parts.second))"
    let hour12 = parts.hour % 12 == 0 ? 12 : parts.hour % 12
    var result = "", index = symbols.startIndex
    var remainingBytes = budget.limits.outputBytes
    func append(_ text: String) throws {
        guard text.utf8.count <= remainingBytes else { throw LiquidError.limitExceeded("outputBytes") }
        remainingBytes -= text.utf8.count
        result += text
    }
    while index < symbols.endIndex {
        try budget.step()
        guard symbols[index] == "%" else {
            try append(String(symbols[index])); index = symbols.index(after: index); continue
        }
        let start = index
        index = symbols.index(after: index)
        var uppercase = false, changeCase = false, noPadding = false
        var padding: Padding?, width: Int?, modifier: Character?, colons = 0
        while index < symbols.endIndex {
            let character = Character(String(symbols[index]))
            if character == "^" { uppercase = true }
            else if character == "#" { changeCase = true }
            else if character == "-" { noPadding = true }
            else if character == "_" { padding = .space }
            else if character == "0" { padding = .zero }
            else { break }
            index = symbols.index(after: index)
        }
        while index < symbols.endIndex, (48...57).contains(symbols[index].value) {
            let digit = symbols[index].value
            let next = (width ?? 0) * 10 + Int(digit - 48)
            guard next <= 1024 else { throw LiquidError.limitExceeded("date padding") }
            width = next; index = symbols.index(after: index)
        }
        if noPadding { padding = Padding.none }
        if index < symbols.endIndex, symbols[index] == "E" || symbols[index] == "O" {
            modifier = Character(String(symbols[index])); index = symbols.index(after: index)
        }
        while index < symbols.endIndex && symbols[index] == ":" {
            colons += 1; index = symbols.index(after: index)
        }
        guard index < symbols.endIndex else { try append(String(symbols[start...])); break }
        let directive = Character(String(symbols[index]))
        index = symbols.index(after: index)
        if (modifier == "E" && !"cCxXyY".contains(directive)) ||
            (modifier == "O" && !"deHImMSuUVwWy".contains(directive)) ||
            (colons > 0 && (directive != "z" || colons > 3)) {
            try append(String(symbols[start..<index])); continue
        }
        var value: String, defaultWidth = 0, defaultPadding = Padding.space
        var numeric: Int?
        switch directive {
        case "Y": numeric = parts.year; defaultWidth = 4
        case "y": numeric = parts.year % 100; defaultWidth = 2
        case "C": numeric = parts.year / 100; defaultWidth = 2
        case "m": numeric = parts.month; defaultWidth = 2
        case "d", "e": numeric = parts.day; defaultWidth = 2
        case "H", "k": numeric = parts.hour; defaultWidth = 2
        case "I", "l": numeric = hour12; defaultWidth = 2
        case "M": numeric = parts.minute; defaultWidth = 2
        case "S": numeric = parts.second; defaultWidth = 2
        case "j": numeric = parts.ordinal; defaultWidth = 3
        case "w": numeric = parts.weekday
        case "u": numeric = parts.weekday == 0 ? 7 : parts.weekday
        case "V": numeric = parts.isoWeek; defaultWidth = 2
        case "G": numeric = parts.isoYear; defaultWidth = 4
        case "g": numeric = parts.isoYear % 100; defaultWidth = 2
        case "U": numeric = (parts.ordinal - 1 + 7 - parts.weekday) / 7; defaultWidth = 2
        case "W": numeric = (parts.ordinal - 1 + 7 - (parts.weekday + 6) % 7) / 7; defaultWidth = 2
        case "s": numeric = date.seconds
        default: break
        }
        if let numeric {
            defaultPadding = "ekl".contains(directive) ? .space : .zero
            value = String(numeric)
        } else {
            switch directive {
            case "p": value = parts.hour < 12 ? "AM" : "PM"
            case "P": value = parts.hour < 12 ? "am" : "pm"
            case "B": value = liquidMonthNames[parts.month - 1]
            case "b", "h": value = String(liquidMonthNames[parts.month - 1].prefix(3))
            case "A": value = liquidWeekdayNames[parts.weekday]
            case "a": value = String(liquidWeekdayNames[parts.weekday].prefix(3))
            case "L", "N":
                let precision = width ?? (directive == "L" ? 3 : 9)
                value = String(date.fraction.prefix(precision))
                value += String(repeating: "0", count: precision - value.count)
                width = nil
            case "z":
                let magnitude = abs(date.offset), hours = magnitude / 3600
                let minutes = magnitude % 3600 / 60, seconds = magnitude % 60
                value = (date.offset < 0 ? "-" : "+") + String(hours)
                defaultPadding = .zero
                defaultWidth = colons == 0 ? 5 : colons == 1 ? 6 : colons == 2 ? 9 : seconds != 0 ? 9 : minutes != 0 ? 6 : 3
                if colons == 0 { value += number(minutes) }
                else if colons < 3 || minutes != 0 || seconds != 0 { value += ":" + number(minutes) }
                if colons == 2 || (colons == 3 && seconds != 0) { value += ":" + number(seconds) }
                if noPadding { padding = .zero; width = nil }
            case "Z": value = date.zoneName
            case "F": value = datePart
            case "T", "X": value = timePart
            case "R": value = "\(number(parts.hour)):\(number(parts.minute))"
            case "D", "x": value = "\(number(parts.month))/\(number(parts.day))/\(number(parts.year % 100))"
            case "r": value = "\(number(hour12)):\(number(parts.minute)):\(number(parts.second)) \(parts.hour < 12 ? "AM" : "PM")"
            case "c": value = "\(liquidWeekdayNames[parts.weekday].prefix(3)) \(liquidMonthNames[parts.month - 1].prefix(3)) \(number(parts.day, 2, .space)) \(timePart) \(number(parts.year, 4))"
            case "v": value = "\(number(parts.day, 2, .space))-\(liquidMonthNames[parts.month - 1].prefix(3).uppercased())-\(number(parts.year, 4))"
            case "n": value = "\n"
            case "t": value = "\t"
            case "%": value = "%"
            default: try append(String(symbols[start..<index])); continue
            }
        }
        if uppercase { value = value.uppercased() }
        if changeCase {
            if directive == "p" || directive == "Z" { value = value.lowercased() }
            else if "aAbBhBP".contains(directive) { value = value.uppercased() }
        }
        value = padded(value, width: width ?? defaultWidth, padding: padding ?? defaultPadding)
        try append(value)
    }
    return result
}
