// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  HTMLEscape.swift
//  LiquidUtilities
//
//  HTML escaping utilities for security
//

import Foundation

internal enum HTMLEscape {
    
    private static let escapeMap: [Character: String] = [
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        "\"": "&quot;",
        "'": "&#39;"
    ]
    
    internal static func escape(_ string: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(string.count * 2) // Pre-allocate for performance
        
        for char in string {
            if let replacement = escapeMap[char] {
                escaped.append(replacement)
            } else {
                escaped.append(char)
            }
        }
        
        return escaped
    }
    
    internal static func escapeOnce(_ string: String) -> String {
        // Strategy: Parse the string and identify existing entities, then escape only raw characters
        var result = ""
        result.reserveCapacity(string.count * 2)
        
        var index = string.startIndex
        
        while index < string.endIndex {
            let char = string[index]
            
            // Check if this is the start of an HTML entity
            if char == "&" {
                // Look ahead to see if this is a valid entity
                if let entityEnd = findEntityEnd(in: string, from: index) {
                    // This is an existing entity - keep it as-is
                    result.append(String(string[index..<entityEnd]))
                    index = entityEnd
                    continue
                } else {
                    // This is a bare & that needs escaping
                    result.append("&amp;")
                    index = string.index(after: index)
                    continue
                }
            }
            
            // Check for characters that need escaping (excluding &)
            if let replacement = escapeMapExceptAmpersand[char] {
                result.append(replacement)
            } else {
                result.append(char)
            }
            
            index = string.index(after: index)
        }
        
        return result
    }
    
    private static let escapeMapExceptAmpersand: [Character: String] = [
        "<": "&lt;",
        ">": "&gt;",
        "\"": "&quot;",
        "'": "&#39;"
    ]
    
    private static func findEntityEnd(in string: String, from startIndex: String.Index) -> String.Index? {
        guard string[startIndex] == "&" else { return nil }
        
        var index = string.index(after: startIndex)
        var entityContent = ""
        
        // Look for the semicolon, with reasonable length limit
        while index < string.endIndex && entityContent.count < 20 {
            let char = string[index]
            
            if char == ";" {
                // Found potential entity end - validate the content
                if isValidHTMLEntity(entityContent) {
                    return string.index(after: index) // Return position after semicolon
                } else {
                    return nil // Not a valid entity
                }
            }
            
            // Only allow alphanumeric characters and # for entities
            if char.isLetter || char.isNumber || char == "#" {
                entityContent.append(char)
                index = string.index(after: index)
            } else {
                // Invalid character in entity - this isn't an entity
                return nil
            }
        }
        
        // Reached end of string or length limit without finding semicolon
        return nil
    }
    
    private static func isValidHTMLEntity(_ entity: String) -> Bool {
        // Check numeric entities
        if entity.hasPrefix("#") {
            let numberPart = String(entity.dropFirst())
            
            if numberPart.hasPrefix("x") || numberPart.hasPrefix("X") {
                // Hexadecimal entity like &#xFF;
                let hexPart = String(numberPart.dropFirst())
                return !hexPart.isEmpty && hexPart.allSatisfy { $0.isHexDigit }
            } else {
                // Decimal entity like &#123;
                return !numberPart.isEmpty && numberPart.allSatisfy { $0.isNumber }
            }
        }
        
        // Check named entities
        return knownHTMLEntities.contains(entity.lowercased())
    }
    
    private static let knownHTMLEntities: Set<String> = [
        // Basic entities
        "amp", "lt", "gt", "quot", "apos",
        
        // Common named entities  
        "nbsp", "copy", "reg", "trade", "hellip", "mdash", "ndash",
        "lsquo", "rsquo", "ldquo", "rdquo", "bull", "middot",
        "laquo", "raquo", "iexcl", "iquest", "sect", "para",
        "micro", "plusmn", "sup2", "sup3", "frac14", "frac12", "frac34",
        "times", "divide", "cent", "pound", "yen", "euro",
        "alpha", "beta", "gamma", "delta", "epsilon", "pi", "sigma",
        "hearts", "diams", "clubs", "spades",
        "larr", "uarr", "rarr", "darr", "harr",
        
        // Additional common entities
        "acute", "cedil", "circ", "macr", "ring", "tilde", "uml",
        "ensp", "emsp", "thinsp", "zwnj", "zwj", "lrm", "rlm",
        "shy", "deg", "ordm", "ordf"
    ]
    
    internal static func escapeAttribute(_ string: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(string.count * 2)
        
        for char in string {
            switch char {
            case "&":
                escaped.append("&amp;")
            case "<":
                escaped.append("&lt;")
            case ">":
                escaped.append("&gt;")
            case "\"":
                escaped.append("&quot;")
            case "'":
                escaped.append("&#39;")
            case "/":
                escaped.append("&#47;")
            case "=":
                escaped.append("&#61;")
            case "`":
                escaped.append("&#96;")
            case "\n":
                escaped.append("&#10;")
            case "\r":
                escaped.append("&#13;")
            case "\t":
                escaped.append("&#9;")
            default:
                // Escape non-ASCII characters as well for safety
                if char.isASCII {
                    escaped.append(char)
                } else {
                    let scalar = String(char).unicodeScalars.first!
                    escaped.append("&#\(scalar.value);")
                }
            }
        }
        
        return escaped
    }
    
    internal static func escapeJavaScript(_ string: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(string.count * 2)
        
        for char in string {
            switch char {
            case "\\":
                escaped.append("\\\\")
            case "\"":
                escaped.append("\\\"")
            case "'":
                escaped.append("\\'")
            case "\n":
                escaped.append("\\n")
            case "\r":
                escaped.append("\\r")
            case "\t":
                escaped.append("\\t")
            case "\u{2028}": // Line separator
                escaped.append("\\u2028")
            case "\u{2029}": // Paragraph separator
                escaped.append("\\u2029")
            case "<":
                // Escape < to prevent </script> injection
                escaped.append("\\u003C")
            case ">":
                escaped.append("\\u003E")
            case "/":
                escaped.append("\\/")
            default:
                escaped.append(char)
            }
        }
        
        return escaped
    }
    
    internal static func escapeURL(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
    
    internal static func containsDangerousHTML(_ string: String) -> Bool {
        let dangerousPatterns = [
            "<script",
            "</script",
            "javascript:",
            "onerror=",
            "onload=",
            "onclick=",
            "onmouseover=",
            "<iframe",
            "<object",
            "<embed",
            "<link",
            "<meta",
            "vbscript:",
            "data:text/html"
        ]
        
        let lowercased = string.lowercased()
        for pattern in dangerousPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }
        
        return false
    }
}

internal protocol HTMLEscapable {
    var htmlEscaped: String { get }
}

extension String: HTMLEscapable {
    internal var htmlEscaped: String {
        return HTMLEscape.escape(self)
    }
}

extension Substring: HTMLEscapable {
    internal var htmlEscaped: String {
        return HTMLEscape.escape(String(self))
    }
}

internal struct SafeHTML: Sendable {
    internal let value: String
    
    internal init(_ value: String) {
        self.value = value
    }
    
    internal init(unsafe value: String) {
        // In production, you might want to validate or sanitize here
        self.value = value
    }
}
