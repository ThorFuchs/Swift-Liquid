// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  Renderer+Utilities.swift
//  LiquidRenderer
//
//

import Foundation

extension Renderer {
    // MARK: - Utility Functions
    
    @inline(__always)
    internal func formatDouble(_ num: Double) -> String {
        if num == floor(num), !num.isInfinite, !num.isNaN {
            // Whole-number doubles: show as "5.0" not "5"
            return String(format: "%.1f", num)
        }
        // Use Swift's default which gives shortest round-trip representation
        let full = String(num)
        // Detect floating-point noise: patterns like "7.8999999999999995" or "3.0000000000000004"
        // These have 16 significant digits and end with runs of 9s or 0s followed by small digits
        if full.count >= 16, let dotIndex = full.firstIndex(of: ".") {
            let decimals = String(full[full.index(after: dotIndex)...])
            // Check for trailing noise: many 9s or 0s near the end
            if decimals.count >= 13 {
                let last5 = String(decimals.suffix(5))
                let nineCount = last5.filter { $0 == "9" }.count
                let zeroCount = last5.filter { $0 == "0" }.count
                if nineCount >= 4 || zeroCount >= 4 {
                    // Round to 10 significant digits to eliminate noise
                    let rounded = String(format: "%.10g", num)
                    return rounded
                }
            }
        }
        return full
    }

    internal func stringify(_ value: Any, escape: Bool? = nil) -> String {
        if let escape {
            let stringValue = stringifyUnescapedPreservingSafeHTML(value)
            return escape ? HTMLEscape.escape(stringValue) : stringValue
        }

        if autoEscapeEnabled {
            if let safeHTML = value as? SafeHTML {
                return safeHTML.value
            }
            return HTMLEscape.escape(stringifyUnescaped(value))
        }

        return stringifyUnescapedPreservingSafeHTML(value)
    }

    @inline(__always)
    internal func stringifyUnescapedPreservingSafeHTML(_ value: Any) -> String {
        if let safeHTML = value as? SafeHTML {
            return safeHTML.value
        }
        return stringifyUnescaped(value)
    }

    @inline(__always)
    internal func stringifyUnescaped(_ value: Any) -> String {
        switch value {
        case is LiquidSpecialValue: return ""
        case let range as RuntimeRange: return range.description
        case let str as String:
            return str
        case let inline as InlineString:
            return inline.string
        case let num as Double:
            return formatDouble(num)
        case let num as Int:
            return String(num)
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.doubleValue == floor(number.doubleValue)
                ? String(number.intValue)
                : String(number.doubleValue)
        case is NSNull:
            return ""
        case let array as [Any]:
            return joinedStringifiedValues(array, separator: "", escapeElements: false)
        case let dict as [String: Any]:
            // Shopify Liquid outputs dictionaries as {"key"=>"value"} format
            if dict.isEmpty { return "{}" }
            let pairs = dict.sorted(by: { $0.key < $1.key })
                .map { "\"\($0.key)\"=>\(stringifyUnescaped($0.value))" }
            return "{\(pairs.joined(separator: ", "))}"
        case let ordered as RuntimeObject:
            if ordered.isEmpty { return "{}" }
            let pairs = ordered.map { "\"\($0.key)\"=>\(stringifyUnescaped($0.value))" }
            return "{\(pairs.joined(separator: ", "))}"
        default:
            return String(describing: value)
        }
    }

    internal func joinedStringifiedValues(_ array: [Any], separator: String, escapeElements: Bool) -> String {
        guard !array.isEmpty else { return "" }

        var parts: [String] = []
        parts.reserveCapacity(array.count)

        var estimatedCapacity = separator.utf8.count * max(0, array.count - 1)
        for value in array {
            let rendered = escapeElements ? stringify(value) : stringifyUnescaped(value)
            estimatedCapacity += rendered.utf8.count
            parts.append(rendered)
        }

        var result = ""
        result.reserveCapacity(estimatedCapacity)

        for index in parts.indices {
            if index > 0 {
                result += separator
            }
            result += parts[index]
        }

        return result
    }

    @inline(__always)
    internal func integerValue(_ value: Any) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(exactly: double.rounded(.towardZero))
        case is Bool:
            return nil
        case let string as String:
            return Int(string)
        case let inline as InlineString:
            return Int(inline.string)
        case let safeHTML as SafeHTML:
            return Int(safeHTML.value)
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    @inline(__always)
    internal func numericValue(_ value: Any) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case is Bool:
            return nil
        case let string as String:
            return coercedNumericString(string)
        case let inline as InlineString:
            return coercedNumericString(inline.string)
        case let safeHTML as SafeHTML:
            return Double(safeHTML.value)
        case let number as NSNumber:
            return number.doubleValue
        default:
            return nil
        }
    }
    
    internal func isTruthy(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case is NSNull:
            return false
        default:
            return true
        }
    }
    
    internal func isEqual(_ left: Any, _ right: Any) -> Bool {
        if let left = left as? LiquidSpecialValue, let right = right as? LiquidSpecialValue { return left == right }
        if let special = left as? LiquidSpecialValue { return special == .blank ? isBlank(right) : isEmpty(right) }
        if let special = right as? LiquidSpecialValue { return special == .blank ? isBlank(left) : isEmpty(left) }
        if left is NSNull || right is NSNull { return left is NSNull && right is NSNull }
        if let left = RuntimeEqualityKey.make(left), let right = RuntimeEqualityKey.make(right) { return left == right }
        // Implement Liquid equality semantics
        // IMPORTANT: Bool must be checked BEFORE Int/Double because Swift bridges
        // Bool to NSNumber, making true matchable as Int(1) and false as Int(0)
        switch (left, right) {
        case (let l as Bool, let r as Bool):
            return l == r
        case (is Bool, _), (_, is Bool):
            // Bool compared to non-Bool is always false in Shopify Liquid
            return false
        case (let l as String, let r as String):
            return l.utf8.elementsEqual(r.utf8)
        // Shopify 'empty' keyword (empty string) equals empty arrays and empty dicts
        case (let s as String, let arr as [Any]) where s.isEmpty:
            return arr.isEmpty
        case (let arr as [Any], let s as String) where s.isEmpty:
            return arr.isEmpty
        case (let s as String, let dict as [String: Any]) where s.isEmpty:
            return dict.isEmpty
        case (let dict as [String: Any], let s as String) where s.isEmpty:
            return dict.isEmpty
        case (let s as String, let ordered as RuntimeObject) where s.isEmpty:
            return ordered.isEmpty
        case (let ordered as RuntimeObject, let s as String) where s.isEmpty:
            return ordered.isEmpty
        case (let l as Int, let r as Int):
            return l == r
        case (let l as Double, let r as Double):
            return l == r
        case (let l as Int, let r as Double):
            return Double(l) == r
        case (let l as Double, let r as Int):
            return l == Double(r)
        case (is NSNull, is NSNull):
            return true
        // Handle NSNumber types
        case (let l as NSNumber, let r as NSNumber):
            return l == r
        case (let l as NSNumber, let r as Int):
            return l.intValue == r
        case (let l as Int, let r as NSNumber):
            return l == r.intValue
        case (let l as NSNumber, let r as Double):
            return l.doubleValue == r
        case (let l as Double, let r as NSNumber):
            return l == r.doubleValue
        // String compared to number: not equal in Shopify Liquid (different types)
        case (is String, is Int), (is Int, is String):
            return false
        case (is String, is Double), (is Double, is String):
            return false
        default:
            // Fallback: compare stringified values for same-type comparisons
            return stringify(left) == stringify(right)
        }
    }

    internal func isLess(_ left: Any, _ right: Any) throws -> Bool {
        if left is LiquidSpecialValue || right is LiquidSpecialValue { return false }
        return try compareValues(left, right) < 0
    }

    internal func isLessEqual(_ left: Any, _ right: Any) throws -> Bool {
        if left is LiquidSpecialValue || right is LiquidSpecialValue { return false }
        return try compareValues(left, right) <= 0
    }

    internal func isGreater(_ left: Any, _ right: Any) throws -> Bool {
        if left is LiquidSpecialValue || right is LiquidSpecialValue { return false }
        return try compareValues(left, right) > 0
    }

    internal func isGreaterEqual(_ left: Any, _ right: Any) throws -> Bool {
        if left is LiquidSpecialValue || right is LiquidSpecialValue { return false }
        return try compareValues(left, right) >= 0
    }

    internal func compareValues(_ left: Any, _ right: Any) throws -> Int {
        if let left = left as? Int, let right = right as? Int {
            return left == right ? 0 : (left < right ? -1 : 1)
        }
        // Both numeric (Int or Double, but NOT String coerced to number)
        let leftIsNumeric = left is Int || left is Double
        let rightIsNumeric = right is Int || right is Double

        if leftIsNumeric && rightIsNumeric {
            let l = numericValue(left) ?? 0
            let r = numericValue(right) ?? 0
            if l < r { return -1 }
            if l > r { return 1 }
            return 0
        }

        // Both strings
        if let l = left as? String, let r = right as? String {
            return l.utf8.elementsEqual(r.utf8) ? 0 : (l.utf8.lexicographicallyPrecedes(r.utf8) ? -1 : 1)
        }

        // NSNull comparisons
        if left is NSNull && right is NSNull { return 0 }
        if left is NSNull || right is NSNull {
            throw RenderError.typeError(expected: "comparable types", actual: "nil vs \(type(of: left is NSNull ? right : left))", operation: "comparison")
        }

        // Incompatible types — error (Shopify behavior)
        throw RenderError.typeError(expected: "comparable types", actual: "\(type(of: left)) vs \(type(of: right))", operation: "comparison")
    }
    
    @inline(__always)
    internal func isFloatLike(_ value: Any) -> Bool {
        if value is Double { return true }
        if let str = value as? String { return str.contains(".") && Double(str)?.isFinite == true }
        if let inline = value as? InlineString { return inline.string.contains(".") && Double(inline.string)?.isFinite == true }
        return false
    }

    // MARK: - Dictionary Helpers (OrderedDictionary support)

    @inline(__always)
    internal func orderedDictPairs(_ value: Any) -> [(key: String, value: Any)]? {
        if let ordered = value as? RuntimeObject {
            return ordered.map { (key: $0.key, value: $0.value) }
        }
        if let dict = value as? [String: Any] {
            return dict.sorted(by: { $0.key < $1.key })
        }
        return nil
    }

    @inline(__always)
    internal func dictValue(_ value: Any, forKey key: String) -> Any? {
        if let ordered = value as? RuntimeObject {
            return ordered[key]
        }
        if let dict = value as? [String: Any] {
            return dict[key]
        }
        return nil
    }

    @inline(__always)
    internal func isDictLike(_ value: Any) -> Bool {
        value is [String: Any] || value is RuntimeObject
    }

    @inline(__always)
    internal func dictCount(_ value: Any) -> Int? {
        if let ordered = value as? RuntimeObject {
            return ordered.count
        }
        if let dict = value as? [String: Any] {
            return dict.count
        }
        return nil
    }

    internal func add(_ left: Any, _ right: Any) throws -> Any {
        if let l = left as? Int, let r = right as? Int {
            let (result, overflow) = l.addingReportingOverflow(r)
            guard !overflow else { throw LiquidError.invalidValue("Integer overflow") }
            return result
        }
        let hasFloat = isFloatLike(left) || isFloatLike(right)
        let l = numericValue(left) ?? 0
        let r = numericValue(right) ?? 0
        let result = l + r
        if !hasFloat, result == result.rounded(.towardZero) { return try checkedInteger(result) }
        return result
    }

    internal func subtract(_ left: Any, _ right: Any) throws -> Any {
        if let l = left as? Int, let r = right as? Int {
            let (result, overflow) = l.subtractingReportingOverflow(r)
            guard !overflow else { throw LiquidError.invalidValue("Integer overflow") }
            return result
        }
        let hasFloat = isFloatLike(left) || isFloatLike(right)
        let l = numericValue(left) ?? 0
        let r = numericValue(right) ?? 0
        let result = l - r
        if !hasFloat, result == result.rounded(.towardZero) { return try checkedInteger(result) }
        return result
    }

    internal func multiply(_ left: Any, _ right: Any) throws -> Any {
        if let l = left as? Int, let r = right as? Int {
            let (result, overflow) = l.multipliedReportingOverflow(by: r)
            guard !overflow else { throw LiquidError.invalidValue("Integer overflow") }
            return result
        }
        let hasFloat = isFloatLike(left) || isFloatLike(right)
        let l = numericValue(left) ?? 0
        let r = numericValue(right) ?? 0
        let result = l * r
        if !hasFloat, result == result.rounded(.towardZero) { return try checkedInteger(result) }
        return result
    }

    internal func divide(_ left: Any, _ right: Any) throws -> Any {
        // Integer division when both operands are integers (Shopify behavior: 5/3=1)
        if let l = left as? Int, let r = right as? Int {
            guard r != 0 else { throw RenderError.arithmeticError("Division by zero") }
            guard !(l == Int.min && r == -1) else { throw LiquidError.invalidValue("Integer overflow") }
            let quotient = l / r
            let remainder = l % r
            return remainder != 0 && ((l < 0) != (r < 0)) ? quotient - 1 : quotient
        }
        // Float division if either operand is actually a Double or float-like string
        let hasFloat = isFloatLike(left) || isFloatLike(right)
        let l = numericValue(left) ?? 0
        let r = numericValue(right) ?? 0
        guard r != 0 else {
            throw RenderError.arithmeticError("Division by zero")
        }
        let result = l / r
        // If neither input was a float, return Int (string coercion case)
        if !hasFloat, result == result.rounded(.towardZero) {
            return try checkedInteger(result)
        }
        return result
    }

    internal func modulo(_ left: Any, _ right: Any) throws -> Any {
        if let l = left as? Int, let r = right as? Int {
            guard r != 0 else { throw RenderError.arithmeticError("Division by zero") }
            if l == Int.min && r == -1 { return 0 }
            let remainder = l % r
            return remainder != 0 && ((remainder < 0) != (r < 0)) ? remainder + r : remainder
        }
        let hasFloat = isFloatLike(left) || isFloatLike(right)
        let l = numericValue(left) ?? 0
        let r = numericValue(right) ?? 0
        guard r != 0 else {
            throw RenderError.arithmeticError("Division by zero")
        }
        let remainder = l.truncatingRemainder(dividingBy: r)
        let result = remainder != 0 && ((remainder < 0) != (r < 0)) ? remainder + r : remainder
        if !hasFloat, result == result.rounded(.towardZero) {
            return try checkedInteger(result)
        }
        return result
    }

    // MARK: - Split Filter (shared implementation)

    internal func applySplitFilter(_ value: Any, separator: Any) -> Any {
        let str = stringify(value)
        if separator is NSNull {
            return str.isEmpty ? [Any]() : str.unicodeScalars.map { String($0) } as [Any]
        }
        let sep = stringify(separator)
        if sep.isEmpty {
            return str.isEmpty ? [Any]() : str.unicodeScalars.map { String($0) } as [Any]
        }
        // Ruby's split(" ") splits on ANY whitespace run
        if sep == " " {
            let parts = str.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            return parts.map { String($0) } as [Any]
        }
        // Standard split — preserve empty parts if any non-empty parts exist
        let parts = str.components(separatedBy: sep)
        return parts.contains(where: { !$0.isEmpty }) ? parts : [Any]()
    }

    internal func contains(_ haystack: Any, _ needle: Any) -> Bool {
        // Shopify: contains with false/nil/undefined needle always returns false
        if needle is Bool || needle is NSNull { return false }
        if let s = needle as? String, s.isEmpty { return false }  // undefined var

        if let str = haystack as? String {
            return str.range(of: stringify(needle), options: .literal) != nil
        }
        if let array = haystack as? [Any] {
            return array.contains { isEqual($0, needle) }
        }
        return false
    }
    
    internal func getSize(_ value: Any) -> Int {
        runtimeValueSize(value) ?? dictCount(value) ?? 0
    }
    

    internal func getFirst(_ value: Any) -> Any {
        if let string = value as? String { return string.unicodeScalars.first.map(String.init) ?? "" }
        if let array = value as? [Any], !array.isEmpty {
            return array[0]
        }
        if let pairs = orderedDictPairs(value), let first = pairs.first {
            return [first.key, first.value] as [Any]
        }
        return NSNull()
    }

    internal func getLast(_ value: Any) -> Any {
        if let string = value as? String { return string.unicodeScalars.last.map(String.init) ?? "" }
        if let array = value as? [Any], !array.isEmpty {
            return array[array.count - 1]
        }
        return ""
    }
    
    internal func isNilOrEmpty(_ value: Any) -> Bool {
        switch value {
        case is NSNull:
            return true
        case let str as String:
            return str.isEmpty
        case let array as [Any]:
            return array.isEmpty
        case let dict as [String: Any]:
            return dict.isEmpty
        case let object as RuntimeObject:
            return object.isEmpty
        case let bool as Bool:
            return !bool
        default:
            // Check for empty string representation
            let str = stringify(value)
            return str.isEmpty || str == "\"\""
        }
    }
    
    internal func isEmpty(_ value: Any) -> Bool {
        switch value {
        case let string as String: return string.isEmpty
        case let array as [Any]: return array.isEmpty
        case let object as RuntimeObject: return object.isEmpty
        case let object as [String: Any]: return object.isEmpty
        default: return false
        }
    }
    
    internal func isBlank(_ value: Any) -> Bool {
        if let boolean = value as? Bool { return !boolean }
        if value is NSNull { return true }
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return isEmpty(value)
    }
    
    internal func joinArray(_ value: Any, separator: String) -> String {
        guard let array = value as? [Any] else { return stringify(value) }
        // Flatten nested arrays before joining (Shopify behavior)
        let flat = flattenArray(array)
        return joinedStringifiedValues(flat, separator: separator, escapeElements: true)
    }

    internal func compareForSort(_ a: Any, _ b: Any) -> Bool {
        // If both are numeric, compare numerically
        if let na = numericValue(a), let nb = numericValue(b),
           (a is Int || a is Double), (b is Int || b is Double) {
            return na < nb
        }
        return stringify(a) < stringify(b)
    }

    internal func compareForSortNatural(_ a: Any, _ b: Any) -> Bool {
        if a is NSNull { return false }
        if b is NSNull { return true }
        if let na = numericValue(a), let nb = numericValue(b),
           (a is Int || a is Double), (b is Int || b is Double) {
            return na < nb
        }
        return stringify(a).lowercased() < stringify(b).lowercased()
    }

    internal func flattenArray(_ array: [Any]) -> [Any] {
        var result: [Any] = []
        for item in array {
            if let nested = item as? [Any] {
                result.append(contentsOf: flattenArray(nested))
            } else {
                result.append(item)
            }
        }
        return result
    }
    
    internal func reverseValue(_ value: Any) -> Any {
        if let array = value as? [Any] {
            return Array(array.reversed())
        }
        return value
    }
    
    internal func sortValue(_ value: Any) -> Any {
        if let array = value as? [Any] {
            return array.sorted { compareForSort($0, $1) }
        }
        return value
    }
    
    internal func roundNumber(_ value: Any, precision: Int) -> Any {
        let num: Double
        switch value {
        case let d as Double: num = d
        case let i as Int: if precision >= 0 { return i } else { num = Double(i) }
        case let n as NSNumber: num = n.doubleValue
        default:
            guard let n = numericValue(value) else { return 0 }
            num = n
        }
        let result = roundedDouble(num, precision: precision)
        if precision <= 0, let integer = Int(exactly: result) { return integer }
        return result
    }

    @inline(__always)
    internal func renderRoundedValueFast(_ value: Any, precision: Int) -> String {
        switch value {
        case let num as Double:
            return stringifyRoundedDouble(roundedDouble(num, precision: precision))
        case let num as Int:
            return precision >= 0
                ? String(num)
                : stringifyRoundedDouble(roundedDouble(Double(num), precision: precision))
        case let number as NSNumber:
            let doubleValue = number.doubleValue
            if precision >= 0, doubleValue.rounded(.towardZero) == doubleValue {
                return String(number.intValue)
            }
            return stringifyRoundedDouble(roundedDouble(doubleValue, precision: precision))
        case let string as String:
            guard let num = Double(string) else {
                return stringify(string)
            }
            return stringifyRoundedDouble(roundedDouble(num, precision: precision))
        case let inline as InlineString:
            guard let num = Double(inline.string) else {
                return stringify(inline)
            }
            return stringifyRoundedDouble(roundedDouble(num, precision: precision))
        case let safeHTML as SafeHTML:
            guard let num = Double(safeHTML.value) else {
                return stringify(safeHTML)
            }
            return stringifyRoundedDouble(roundedDouble(num, precision: precision))
        default:
            let roundedValue = roundNumber(value, precision: precision)
            return stringify(roundedValue)
        }
    }


    @inline(__always)
    internal func stringifyRoundedDouble(_ value: Double) -> String {
        value == floor(value) ? String(Int(value)) : String(value)
    }

    @inline(__always)
    internal func roundedDouble(_ num: Double, precision: Int) -> Double {
        let multiplier: Double
        switch precision {
        case 0:
            return num.rounded()
        case 1:
            multiplier = 10
        case 2:
            multiplier = 100
        case 3:
            multiplier = 1_000
        case 4:
            multiplier = 10_000
        default:
            multiplier = pow(10.0, Double(precision))
        }
        return (num * multiplier).rounded() / multiplier
    }
    
    internal func getProperty(from object: Any, key: String) -> Any? {
        // This is a simplified implementation
        // In a full implementation, you'd use Mirror or KVC
        if let val = dictValue(object, forKey: key) { return val }
        if isDictLike(object) { return nil }
        return nil
    }
}

internal func checkedInteger(_ value: Double) throws -> Int {
    guard let integer = Int(exactly: value.rounded(.towardZero)) else { throw LiquidError.invalidValue("Number exceeds integer range") }
    return integer
}

internal func coercedNumericString(_ text: String) -> Double? {
    if text.contains("."), let number = Double(text), number.isFinite { return number }
    let scalars = text.unicodeScalars.drop(while: { [9, 10, 11, 12, 13, 32].contains($0.value) })
    var prefix = ""
    var position = 0
    for scalar in scalars {
        if position == 0 && (scalar == "+" || scalar == "-") { prefix.unicodeScalars.append(scalar) }
        else if (48...57).contains(scalar.value) { prefix.unicodeScalars.append(scalar) }
        else { break }
        position += 1
    }
    return Double(prefix) ?? 0
}
