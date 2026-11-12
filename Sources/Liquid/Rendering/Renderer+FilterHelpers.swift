// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  Renderer+FilterHelpers.swift
//  LiquidRenderer
//
//

import Foundation

extension Renderer {
    // MARK: - Filter Helper Functions
    
    internal func truncateString(_ str: String, length: Int, ending: String) -> String {
        if str.unicodeScalars.count <= length { return str }
        
        let endingLength = ending.unicodeScalars.count
        let truncateLength = length > endingLength ? length - endingLength : 0
        return String(String.UnicodeScalarView(str.unicodeScalars.prefix(truncateLength))) + ending
    }
    
    internal func truncateWords(_ str: String, count: Int, ending: String) -> String {
        // Ruby String#split(" ") recognizes ASCII whitespace, not every
        // Unicode whitespace scalar.
        let words = str.unicodeScalars.split(omittingEmptySubsequences: true) {
            [9, 10, 11, 12, 13, 32].contains($0.value)
        }
        if words.count <= count { return str }

        return words.prefix(count).map { String(String.UnicodeScalarView($0)) }.joined(separator: " ") + ending
    }
    
    internal func stripHTML(_ str: String) -> String {
        var result = str
        // Shopify applies one case-sensitive block expression before removing tags.
        if let blocks = try? NSRegularExpression(pattern: "<script.*?</script>|<!--.*?-->|<style.*?</style>", options: .dotMatchesLineSeparators) {
            result = blocks.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        guard let regex = try? NSRegularExpression(pattern: "<.*?>", options: .dotMatchesLineSeparators) else {
            return result
        }
        return regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
    }
    
    internal func slugify(_ str: String) -> String {
        var slug = str.lowercased()
        slug = slug.replacingOccurrences(of: " ", with: "-")
        
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        slug = slug.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
        
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
    
    internal func compactArray(_ value: Any, key: String? = nil) -> Any {
        // Non-array: wrap as single-element array (Shopify behavior)
        let array: [Any]
        if let arr = value as? [Any] { array = arr }
        else if value is NSNull { return [Any]() }
        else if let s = value as? String, s.isEmpty { return [Any]() }
        else { array = [value] }

        if let key {
            // compact('key'): remove items where item[key] is nil
            return array.filter { item in
                guard isDictLike(item) else { return true }
                guard let val = dictValue(item, forKey: key) else { return false }
                return !(systemPrimary(val) is NSNull)
            }
        }

        return array.compactMap { item -> Any? in
            if systemPrimary(item) is NSNull { return nil }
            return item
        }
    }

    internal func uniqueArray(_ value: Any, key: String? = nil) throws -> Any {
        guard let array = value as? [Any] else { return value }
        var seen = Set<RuntimeEqualityKey>()
        var unique: [Any] = []
        for item in flattenArray(array) {
            try budget.step()
            let selected = key.map { dictValue(item, forKey: $0) ?? NSNull() } ?? item
            guard let identity = RuntimeEqualityKey.make(selected) else { throw LiquidError.invalidValue("Unsupported value for uniq") }
            if seen.insert(identity).inserted { unique.append(item) }
        }
        return unique
    }
    
    internal func formatDate(_ value: Any, format: String) throws -> Any {
        guard !format.isEmpty else { return value }
        let date: LiquidDate
        if let integer = value as? Int {
            date = try LiquidDate(seconds: integer)
        } else if let text = value as? String {
            if text.lowercased() == "now" || text.lowercased() == "today" {
                date = try LiquidDate.from(referenceTime)
            } else if !text.isEmpty && text.utf8.allSatisfy({ (48...57).contains($0) }) {
                guard let seconds = Int(text) else { throw LiquidError.invalidValue("Date epoch is outside the supported range") }
                date = try LiquidDate(seconds: seconds)
            } else if let parsed = try parseLiquidDate(text.lowercased(), referenceTime: referenceTime) {
                date = parsed
            } else { return value }
        } else { return value }
        return try renderStrftime(format, date: date, budget: budget)
    }

    internal func whereFilter(_ value: Any, args: [Any]) throws -> Any {
        // where filter: filters an array to elements where a property equals a value
        // Usage: {{ products | where: 'available', true }}
        // Usage: {{ products | where: 'title' }}  (truthy check)
        let array: [Any]
        if let items = value as? [Any] { array = items }
        else if isDictLike(value) || value is String { array = [value] }
        else if value is NSNull { return value }
        else { throw RenderError.typeError(expected: "array", actual: "\(type(of: value))", operation: "where") }
        guard args.count >= 1 else { return value }

        let property = stringify(args[0])
        // Ruby treats nil as an omitted target, but an empty string is a target.
        let targetArg: Any? = args.count >= 2 ? args[1] : nil
        let hasTarget = targetArg != nil && !(targetArg is NSNull)
        var selected: [Any] = []
        for item in array {
            try Task.checkCancellation()
            let itemValue: Any?
            if let string = systemPrimary(item) as? String {
                itemValue = property.isEmpty || string.range(of: property, options: .literal) != nil ? property : nil
            } else {
                itemValue = getObjectProperty(item, key: property)
            }
            if hasTarget {
                if areValuesEqual(itemValue, targetArg) { selected.append(item) }
            } else if let itemValue, !(itemValue is NSNull), isTruthy(itemValue) {
                selected.append(item)
            }
        }
        return selected
    }
    
    internal func mapFilter(_ value: Any, args: [Any]) throws -> Any {
        // map filter: extracts a property from each element in an array
        // Usage: {{ products | map: 'title' }}
        // Hash input: wrap as single-element array
        let array: [Any]
        if let arr = value as? [Any] {
            // Flatten nested arrays (Shopify behavior)
            array = arr.flatMap { item -> [Any] in
                if let nested = systemPrimary(item) as? [Any] { return nested }
                return [item]
            }
        } else if isDictLike(value) || value is RuntimeSelf || value is String {
            array = [value]
        } else if value is NSNull {
            return [Any]()
        } else {
            throw RenderError.typeError(expected: "array", actual: "\(type(of: value))", operation: "map")
        }
        guard let property = args.first else { return value }

        let propertyName = stringify(property)
        // Each element must be a hash/object — Shopify throws for non-objects
        var result: [Any] = []
        result.reserveCapacity(array.count)
        for item in array {
            if let selfValue = item as? RuntimeSelf {
                result.append(selfValue.lookup(propertyName) ?? NSNull())
            } else if isDictLike(item) {
                result.append(dictValue(item, forKey: propertyName) as Any? ?? NSNull())
            } else if systemPrimary(item) is [Any] {
                // Empty arrays or nested arrays are not objects
                throw RenderError.typeError(expected: "hash", actual: "array", operation: "map")
            } else if systemPrimary(item) is NSNull {
                result.append(NSNull())
            } else if let string = systemPrimary(item) as? String {
                result.append(string.range(of: propertyName, options: .literal) == nil ? NSNull() : propertyName as Any)
            } else if systemPrimary(item) is Int || systemPrimary(item) is Double || systemPrimary(item) is Bool {
                throw RenderError.typeError(expected: "hash", actual: "\(type(of: item))", operation: "map")
            } else {
                result.append(getObjectProperty(item, key: propertyName) ?? NSNull())
            }
        }
        return result
    }
    
    internal func getObjectProperty(_ object: Any, key: String) -> Any? {
        let object = systemPrimary(object)
        // Handle different object types
        if let val = dictValue(object, forKey: key) { return val }
        else if isDictLike(object) { return nil }
 else if let safeHTML = object as? SafeHTML {
            return getObjectProperty(safeHTML.value, key: key)
        }
        // For other types, use Mirror reflection
        let mirror = Mirror(reflecting: object)
        for child in mirror.children {
            if child.label == key {
                return child.value
            }
        }
        return nil
    }
    
    internal func areValuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        let a = a.map { systemPrimary($0) }; let b = b.map { systemPrimary($0) }
        // Handle nil/NSNull — treat Swift nil and NSNull as equivalent
        let aIsNil = a == nil || a is NSNull
        let bIsNil = b == nil || b is NSNull
        if aIsNil && bIsNil { return true }
        if aIsNil || bIsNil { return false }
        
        // Unwrap the values
        let valueA = a!
        let valueB = b!
        
        // Compare based on types
        switch (valueA, valueB) {
        case let (strA as String, strB as String):
            return strA.utf8.elementsEqual(strB.utf8)
        case let (intA as Int, intB as Int):
            return intA == intB
        case let (doubleA as Double, doubleB as Double):
            return doubleA == doubleB
        case let (boolA as Bool, boolB as Bool):
            return boolA == boolB
        case (is NSNull, is NSNull):
            return true
        case let (numA as NSNumber, numB as NSNumber):
            return numA == numB
        case let (dateA as Date, dateB as Date):
            return dateA == dateB
        default:
            // Try string comparison as fallback
            return stringify(valueA) == stringify(valueB)
        }
    }
    
    internal func sortFilter(_ value: Any, args: [Any]) throws -> Any {
        // sort filter: sorts an array by a property or by the elements themselves
        // Usage: {{ products | sort }} or {{ products | sort: 'price' }}
        guard let array = value as? [Any] else { return value }

        // Resolve property name — treat nil/empty (undefined var) as no property
        let propertyName: String? = {
            guard let arg = args.first else { return nil }
            let s = stringify(arg)
            return s.isEmpty ? nil : s
        }()

        if let propertyName {
            return array.sorted { a, b in
                let aValue = getObjectProperty(a, key: propertyName)
                let bValue = getObjectProperty(b, key: propertyName)
                if aValue == nil && bValue == nil { return false }
                if aValue == nil { return false }
                if bValue == nil { return true }
                let left = aValue!, right = bValue!
                if let a = left as? Int, let b = right as? Int { return a < b }
                if (left is Int || left is Double), (right is Int || right is Double),
                   let a = numericValue(left), let b = numericValue(right) { return a < b }
                return stringify(left) < stringify(right)
            }
        } else {
            var primitiveKinds = Set<Int>()
            var booleans = Set<Bool>()
            for item in array {
                if let boolean = item as? Bool { primitiveKinds.insert(2); booleans.insert(boolean) }
                else if item is String { primitiveKinds.insert(1) }
                else if item is Int || item is Double { primitiveKinds.insert(0) }
            }
            if primitiveKinds.count > 1 || booleans.count > 1 {
                throw RenderError.custom("cannot sort values of incompatible types")
            }
            // Check for incompatible mixed complex/primitive types
            let hasComplex = array.contains { isDictLike($0) || systemPrimary($0) is [Any] }
            let hasPrimitive = array.contains { let v = systemPrimary($0); return v is String || v is Int || v is Double || v is Bool }
            if hasComplex && hasPrimitive {
                throw RenderError.typeError(expected: "homogeneous array", actual: "mixed complex/primitive types", operation: "sort")
            }
            return array.sorted { compareForSort($0, $1) }
        }
    }

    internal func sortNaturalFilter(_ value: Any, args: [Any]) throws -> Any {
        // sort_natural: case-insensitive sort, items without key go to end
        guard let array = value as? [Any] else { return value }

        let propertyName: String? = {
            guard let arg = args.first else { return nil }
            let s = stringify(arg)
            return s.isEmpty ? nil : s
        }()

        if let propertyName {
            return try array.sorted { a, b in
                try compareForSortNatural(getObjectProperty(a, key: propertyName) ?? NSNull(),
                                          getObjectProperty(b, key: propertyName) ?? NSNull())
            }
        } else {
            return try array.sorted { try compareForSortNatural($0, $1) }
        }
    }

    internal func sumValues(_ value: Any, property: String? = nil) throws -> Any {
        guard let array = value as? [Any] else {
            if let integer = value as? Int { return integer }
            guard let number = numericValue(value) else { return 0 }
            if let string = value as? String {
                if let integer = Int(string) { return integer }
                if !string.contains(".") || Double(string) == nil { return try checkedInteger(number) }
            }
            return number
        }
        var result: Any = 0
        // Ruby Liquid converts Float inputs to decimal before summing and only
        // converts back to Float once at the end. Keep the existing arithmetic
        // path as a fallback when Foundation cannot represent an exact sum.
        var decimalResult = Decimal.zero
        var decimalExact = true
        var hasFloat = false
        for item in flattenArray(array) {
            try budget.step()
            let target: Any
            if let property {
                guard isDictLike(item) else { throw RenderError.typeError(expected: "hash", actual: "value", operation: "sum") }
                target = dictValue(item, forKey: property) ?? 0
            } else { target = item }
            let primary = systemPrimary(target)
            let number: Any?
            if primary is Int || primary is Double { number = primary }
            else if let text = primary as? String {
                if let integer = Int(text) { number = integer }
                else { number = Double(text) }
            } else { number = nil }
            guard let number else { continue }
            result = try add(result, number)
            if number is Double { hasFloat = true }
            if decimalExact {
                let text: String
                if let integer = number as? Int { text = String(integer) }
                else if let floating = number as? Double, floating.isFinite { text = String(floating) }
                else { decimalExact = false; continue }
                if var operand = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
                    if let floating = number as? Double, NSDecimalNumber(decimal: operand).doubleValue != floating {
                        decimalExact = false
                        continue
                    }
                    var previous = decimalResult
                    var next = Decimal.zero
                    if NSDecimalAdd(&next, &previous, &operand, .plain) == .noError {
                        decimalResult = next
                    } else { decimalExact = false }
                } else { decimalExact = false }
            }
        }
        if hasFloat && decimalExact { return NSDecimalNumber(decimal: decimalResult).doubleValue }
        return result
    }
    
    internal func jsonEncode(_ value: Any) throws -> Any {
        // Handle scalar types that need special JSON encoding
        switch value {
        case let str as String:
            // Strings need to be quoted to be valid JSON
            let escaped = str
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "/", with: "\\/")
            return SafeHTML("\"\(escaped)\"")
        case let bool as Bool:
            return SafeHTML(bool ? "true" : "false")
        case let int as Int:
            return SafeHTML(String(int))
        case let double as Double:
            return SafeHTML(String(double))
        case is NSNull:
            return SafeHTML("null")
        case let safeHTML as SafeHTML:
            // SafeHTML wraps a string value - extract it and treat as string
            let stringValue = String(describing: safeHTML.value)
            let escaped = stringValue
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "/", with: "\\/")
            return SafeHTML("\"\(escaped)\"")
        case let date as Date:
            // Encode date as ISO8601 string
            let dateStr = ISO8601DateFormatter().string(from: date)
            return SafeHTML("\"\(dateStr)\"")
        default:
            // For arrays and objects, use JSONSerialization
            let jsonValue = convertToJSONCompatible(value)
            let data = try JSONSerialization.data(withJSONObject: jsonValue, options: [.sortedKeys])
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw RenderError.filterError("json", underlying: "Failed to encode value as JSON")
            }
            return SafeHTML(jsonString)
        }
    }
    
    internal func convertToJSONCompatible(_ value: Any) -> Any {
        switch value {
        case let array as [Any]:
            return array.map { convertToJSONCompatible($0) }
        case let dict as [String: Any]:
            return dict.mapValues { convertToJSONCompatible($0) }
        case let ordered as RuntimeObject:
            var result: [String: Any] = [:]
            for (key, val) in ordered {
                result[key] = convertToJSONCompatible(val)
            }
            return result
        case let safeHTML as SafeHTML:
            return safeHTML.value
        case is NSNull:
            return NSNull()
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let bool as Bool:
            return bool
        case let num as Double:
            return num
        case let num as Int:
            return num
        case let str as String:
            return str
        default:
            return String(describing: value)
        }
    }
    

}
