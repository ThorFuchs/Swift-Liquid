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
        /// Creates a property without normalizing its key or coercing its value.
        /// - Parameters:
        ///   - key: Property name with its exact Unicode scalar spelling.
        ///   - value: Typed property value.
        public init(_ key: String, _ value: LiquidValue) { self.key = key; self.value = value }
    }
    /// Properties in insertion order.
    public private(set) var entries: [Entry]
    /// Creates an object from ordered entries.
    /// Exact repeated keys replace the value at the first occurrence's position.
    /// - Parameter entries: Properties in the desired iteration order.
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
    /// - Parameter elements: Key/value pairs; exact repeated keys replace in place.
    public init(dictionaryLiteral elements: (String, LiquidValue)...) {
        self.init(elements.map { Entry($0.0, $0.1) })
    }
    /// Looks up a property by exact Unicode scalar spelling, without coercion.
    /// - Parameter key: Exact property name; canonical-equivalent spellings remain distinct.
    /// - Returns: The retained value, or nil when the property is absent.
    public subscript(key: String) -> LiquidValue? { entries.first { ScalarKey($0.key) == ScalarKey(key) }?.value }
}

extension LiquidValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    /// Creates a text value from a Swift string literal.
    /// - Parameter value: Text retained without Unicode normalization.
    public init(stringLiteral value: String) { self = .string(value) }
    /// Creates a machine-width integer from a Swift literal.
    /// - Parameter value: Exact native integer value.
    public init(integerLiteral value: Int) { self = .integer(value) }
    /// Creates a floating-point value; operations reject non-finite numbers.
    /// - Parameter value: Native Double value; this is not an exact decimal model.
    public init(floatLiteral value: Double) { self = .number(value) }
    /// Creates a Boolean value from a Swift literal.
    /// - Parameter value: The Boolean value, distinct from native integers.
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    /// Creates an ordered array from a Swift literal.
    /// - Parameter elements: Typed values in their literal order.
    public init(arrayLiteral elements: LiquidValue...) { self = .array(elements) }
    /// Creates an ordered object from a Swift literal.
    /// - Parameter elements: Key/value pairs; exact repeated keys replace in place.
    public init(dictionaryLiteral elements: (String, LiquidValue)...) {
        self = .object(LiquidObject(elements.map { .init($0.0, $0.1) }))
    }
    /// Creates the Liquid null value from Swift nil.
    /// - Parameter nilLiteral: The empty payload supplied by the nil-literal protocol.
    public init(nilLiteral: ()) { self = .null }
}
