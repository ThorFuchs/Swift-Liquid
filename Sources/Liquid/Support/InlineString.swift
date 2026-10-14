// SPDX-License-Identifier: Apache-2.0
import Foundation

// Native String storage replaces upstream's unsafe inline byte representation.
internal struct InlineString: Sendable, Hashable, Comparable, ExpressibleByStringLiteral, CustomStringConvertible {
    let string: String
    init(_ string: String = "") { self.string = string }
    init<Bytes: Collection>(utf8 bytes: Bytes) where Bytes.Element == UInt8 {
        string = String(decoding: bytes, as: UTF8.self)
    }
    init(stringLiteral value: String) { string = value }
    var utf8Count: Int { string.utf8.count }
    var firstUTF8Byte: UInt8? { string.utf8.first }
    var isEmpty: Bool { string.isEmpty }
    var description: String { string }
    func equals(_ literal: StaticString) -> Bool {
        literal.withUTF8Buffer { string.utf8.elementsEqual($0) }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.string.utf8.elementsEqual(rhs.string.utf8) }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.string.utf8.lexicographicallyPrecedes(rhs.string.utf8) }
    func hash(into hasher: inout Hasher) { for byte in string.utf8 { hasher.combine(byte) } }
    func appending(_ other: String) -> Self { .init(string + other) }
    func appending(_ other: Self) -> Self { appending(other.string) }
    func prepending(_ other: String) -> Self { .init(other + string) }
    func contains(_ value: String) -> Bool { string.contains(value) }
    func hasPrefix(_ value: String) -> Bool { string.hasPrefix(value) }
    func hasSuffix(_ value: String) -> Bool { string.hasSuffix(value) }
    func lowercased() -> Self { .init(string.lowercased()) }
    func uppercased() -> Self { .init(string.uppercased()) }
    func trimmingWhitespace() -> Self { .init(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
}
