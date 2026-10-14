// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Values that can be supplied to a Liquid template across concurrency boundaries.
///
/// Only `null` and `false` are falsy. Object literals retain their insertion order.
public indirect enum LiquidValue: Sendable, Equatable {
    /// Liquid's `nil` value.
    case null
    /// A Boolean value.
    case bool(Bool)
    /// A signed machine-width integer.
    case integer(Int)
    /// A finite binary floating-point number.
    case number(Double)
    /// Unicode text.
    case string(String)
    /// An ordered sequence of values.
    case array([LiquidValue])
    /// An object whose entries retain insertion order.
    case object(LiquidObject)

    internal var runtimeValue: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .integer(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.runtimeValue)
        case .object(let object): RuntimeObject(uniqueKeysWithValues: object.entries.map { ($0.key, $0.value.runtimeValue) })
        }
    }
}

/// An ordered Liquid object. Repeated keys replace the value at its original position.
public struct LiquidObject: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    /// An object entry.
    public struct Entry: Sendable, Equatable {
        /// The property name.
        public let key: String
        /// The property value.
        public let value: LiquidValue
        /// Creates a property.
        public init(_ key: String, _ value: LiquidValue) { self.key = key; self.value = value }
    }
    /// Properties in insertion order.
    public private(set) var entries: [Entry]
    /// Creates an object from ordered entries.
    public init(_ entries: [Entry] = []) {
        self.entries = []
        var positions: [ScalarKey: Int] = [:]
        for entry in entries {
            let key = ScalarKey(entry.key)
            if let position = positions[key] { self.entries[position] = entry }
            else { positions[key] = self.entries.count; self.entries.append(entry) }
        }
    }
    /// Creates an object from a Swift dictionary literal, preserving literal order.
    public init(dictionaryLiteral elements: (String, LiquidValue)...) {
        self.init(elements.map { Entry($0.0, $0.1) })
    }
    /// Looks up a property without coercion.
    public subscript(key: String) -> LiquidValue? { entries.first { ScalarKey($0.key) == ScalarKey(key) }?.value }
}

extension LiquidValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: LiquidValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, LiquidValue)...) {
        self = .object(LiquidObject(elements.map { .init($0.0, $0.1) }))
    }
    public init(nilLiteral: ()) { self = .null }
}
