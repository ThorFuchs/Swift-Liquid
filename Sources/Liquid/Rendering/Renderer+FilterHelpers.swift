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
        // Split on any whitespace (space, tab, newline), normalize to single spaces
        let words = str.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        if words.count <= count { return str }

        return words.prefix(count).joined(separator: " ") + ending
    }
    
    internal func stripHTML(_ str: String) -> String {
        var result = str
        // First strip <script>...</script> and <style>...</style> blocks entirely
        for tag in ["script", "style"] {
            let blockPattern = "<\(tag)[^>]*>.*?</\(tag)>"
            if let regex = try? NSRegularExpression(pattern: blockPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
            }
        }
        // Then strip HTML comments
        if let commentRegex = try? NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators) {
            result = commentRegex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }
        // Then strip remaining tags
        let tagPattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) else {
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
                return !(val is NSNull)
            }
        }

        return array.compactMap { item -> Any? in
            if item is NSNull { return nil }
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
        guard let array = value as? [Any] else {
            if value is NSNull { return value }
            throw RenderError.typeError(expected: "array", actual: "\(type(of: value))", operation: "where")
        }
        guard args.count >= 1 else { return value }

        let property = stringify(args[0])
        // Treat nil/NSNull/empty second arg as undefined → truthy check
        let targetArg: Any? = args.count >= 2 ? args[1] : nil
        let hasTarget = targetArg != nil && !(targetArg is NSNull) && !((targetArg as? String) == "")

        if hasTarget {
            return array.filter { item in
                let itemValue = getObjectProperty(item, key: property)
                return areValuesEqual(itemValue, targetArg)
            }
        } else {
            // Single-arg: keep items where property is truthy
            return array.filter { item in
                guard let propVal = getObjectProperty(item, key: property) else { return false }
                if propVal is NSNull { return false }
                return isTruthy(propVal)
            }
        }
    }
    
    internal func mapFilter(_ value: Any, args: [Any]) throws -> Any {
        // map filter: extracts a property from each element in an array
        // Usage: {{ products | map: 'title' }}
        // Hash input: wrap as single-element array
        let array: [Any]
        if let arr = value as? [Any] {
            // Flatten nested arrays (Shopify behavior)
            array = arr.flatMap { item -> [Any] in
                if let nested = item as? [Any] { return nested }
                return [item]
            }
        } else if isDictLike(value) {
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
            if isDictLike(item) {
                result.append(dictValue(item, forKey: propertyName) as Any? ?? NSNull())
            } else if item is [Any] {
                // Empty arrays or nested arrays are not objects
                throw RenderError.typeError(expected: "hash", actual: "array", operation: "map")
            } else if item is NSNull {
                result.append(NSNull())
            } else if item is Int || item is Double || item is Bool || item is String {
                throw RenderError.typeError(expected: "hash", actual: "\(type(of: item))", operation: "map")
            } else {
                result.append(getObjectProperty(item, key: propertyName) ?? NSNull())
            }
        }
        return result
    }
    
    internal func getObjectProperty(_ object: Any, key: String) -> Any? {
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
                return stringify(aValue!) < stringify(bValue!)
            }
        } else {
            // Check for incompatible mixed complex/primitive types
            let hasComplex = array.contains { isDictLike($0) || $0 is [Any] }
            let hasPrimitive = array.contains { $0 is String || $0 is Int || $0 is Double || $0 is Bool }
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
            return array.sorted { a, b in
                let aValue = getObjectProperty(a, key: propertyName)
                let bValue = getObjectProperty(b, key: propertyName)
                if aValue == nil && bValue == nil { return false }
                if aValue == nil { return false }
                if bValue == nil { return true }
                return stringify(aValue!).lowercased() < stringify(bValue!).lowercased()
            }
        } else {
            return array.sorted { compareForSortNatural($0, $1) }
        }
    }

    internal func sumValues(_ value: Any, property: String? = nil) throws -> Any {
        guard let array = value as? [Any] else {
            if let integer = value as? Int { return integer }
            return numericValue(value) ?? 0
        }
        var result: Any = 0
        for item in flattenArray(array) {
            try budget.step()
            let target: Any
            if let property {
                guard isDictLike(item) else { throw RenderError.typeError(expected: "hash", actual: "value", operation: "sum") }
                target = dictValue(item, forKey: property) ?? 0
            } else { target = item }
            if target is Int || target is Double { result = try add(result, target) }
            else if let text = target as? String {
                if let integer = Int(text) { result = try add(result, integer) }
                else if let number = Double(text) { result = try add(result, number) }
            }
        }
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
