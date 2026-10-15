// SPDX-License-Identifier: Apache-2.0
import Foundation

extension LiquidValue {
    /// Reads a complete JSON document and preserves object member order.
    ///
    /// Integers outside `Int` use finite Double representation. Use strings when
    /// an application needs exact large numbers. Nesting is capped at 128 levels.
    /// - Parameter json: UTF-8 JSON text.
    /// - Throws: ``LiquidJSONError`` for malformed or unsupported JSON.
    public init(json: String) throws {
        var reader = LiquidJSONReader(bytes: Array(json.utf8))
        self = try reader.readValue()
        reader.skipWhitespace()
        guard reader.position == reader.bytes.count else { throw reader.error("Trailing data") }
    }
}

/// A JSON input error with a zero-based byte offset.
public struct LiquidJSONError: Error, Sendable, CustomStringConvertible {
    /// The UTF-8 byte offset where reading failed.
    public let byteOffset: Int
    /// A human-readable explanation.
    public let message: String
    /// A formatted error message.
    public var description: String { "JSON at byte \(byteOffset): \(message)" }
}

private struct LiquidJSONReader {
    let bytes: [UInt8]
    var position = 0
    func error(_ message: String) -> LiquidJSONError { .init(byteOffset: position, message: message) }
    var current: UInt8? { position < bytes.count ? bytes[position] : nil }
    mutating func skipWhitespace() {
        while let c = current, [9, 10, 13, 32].contains(c) { position += 1 }
    }
    mutating func consume(_ byte: UInt8) -> Bool {
        if current == byte { position += 1; return true }
        return false
    }
    mutating func require(_ byte: UInt8) throws {
        skipWhitespace()
        guard consume(byte) else { throw error("Expected '\(UnicodeScalar(byte))'") }
    }
    mutating func readString() throws -> String {
        let start = position
        guard consume(34) else { throw error("Expected a string") }
        while let c = current {
            position += 1
            if c == 92 {
                guard current != nil else { throw error("Unterminated string escape") }
                position += 1
            } else if c == 34 {
                do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<position])) }
                catch { throw self.error("Invalid JSON string") }
            }
        }
        throw error("Unterminated string")
    }
    private enum Container {
        case array([LiquidValue])
        case object([LiquidObject.Entry], Set<ScalarKey>, String)
    }

    mutating func readValue() throws -> LiquidValue {
        // A bounded explicit stack keeps the public 128-level contract independent
        // of executor-thread stack size, including sanitizer-instrumented builds.
        var containers: [Container] = []
        var value: LiquidValue?
        while true {
            if value == nil {
                guard containers.count <= 128 else { throw error("Nesting exceeds 128 levels") }
                try Task.checkCancellation()
                skipWhitespace()
                guard let byte = current else { throw error("Expected a JSON value") }
                switch byte {
                case 34: value = .string(try readString())
                case 123:
                    position += 1; skipWhitespace()
                    if consume(125) { value = .object(.init()) }
                    else {
                        let key = try readString()
                        try require(58)
                        containers.append(.object([], [ScalarKey(key)], key))
                        continue
                    }
                case 91:
                    position += 1; skipWhitespace()
                    if consume(93) { value = .array([]) }
                    else { containers.append(.array([])); continue }
                case 116: value = try readKeyword("true", value: .bool(true))
                case 102: value = try readKeyword("false", value: .bool(false))
                case 110: value = try readKeyword("null", value: .null)
                case 45, 48...57: value = try readNumber()
                default: throw error("Expected a JSON value")
                }
            }
            guard let child = value else { throw error("Expected a JSON value") }
            guard let container = containers.popLast() else { return child }
            skipWhitespace()
            switch consume container {
            case .array(var values):
                values.append(child)
                if consume(93) { value = .array(values) }
                else {
                    try require(44)
                    containers.append(.array(values))
                    value = nil
                }
            case .object(var entries, var keys, let key):
                entries.append(.init(key, child))
                if consume(125) { value = .object(.init(entries)) }
                else {
                    try require(44)
                    skipWhitespace()
                    let nextKey = try readString()
                    guard keys.insert(ScalarKey(nextKey)).inserted else { throw error("Duplicate object key") }
                    try require(58)
                    containers.append(.object(entries, keys, nextKey))
                    value = nil
                }
            }
        }
    }

    mutating func readNumber() throws -> LiquidValue {
        let start = position
        _ = consume(45)
        guard let c = current else { throw error("Missing number") }
        if c == 48 { position += 1 }
        else {
            guard (49...57).contains(c) else { throw error("Invalid number") }
            readDigits()
        }
        if consume(46) {
            guard let c = current, (48...57).contains(c) else { throw error("Missing fractional digits") }
            readDigits()
        }
        if consume(101) || consume(69) {
            if !consume(43) { _ = consume(45) }
            guard let c = current, (48...57).contains(c) else { throw error("Missing exponent digits") }
            readDigits()
        }
        let lexeme = String(decoding: bytes[start..<position], as: UTF8.self)
        if let integer = Int(lexeme) { return .integer(integer) }
        guard let number = Double(lexeme), number.isFinite else { throw error("Number exceeds finite numeric range") }
        return .number(number)
    }
    mutating func readDigits() {
        while let c = current, (48...57).contains(c) { position += 1 }
    }
    mutating func readKeyword(_ keyword: String, value: LiquidValue) throws -> LiquidValue {
        let literal = Array(keyword.utf8)
        guard bytes.dropFirst(position).starts(with: literal) else { throw error("Invalid literal") }
        position += literal.count
        return value
    }
}
