// SPDX-License-Identifier: Apache-2.0
import Foundation

// Structural identity for standard values, used by uniq without serialization
// or canonically equivalent String hashing.
internal indirect enum RuntimeEqualityKey: Hashable {
    case null, boolean(Bool), integer(Int), number(Double), string(ScalarKey)
    case array([RuntimeEqualityKey]), object([Member]), range(Int, Int)
    struct Member: Hashable { let key: ScalarKey; let value: RuntimeEqualityKey }

    static func make(_ value: Any) -> Self? {
        switch value {
        case is NSNull: return .null
        case let value as Bool: return .boolean(value)
        case let value as Int: return .integer(value)
        case let value as Double:
            if let integer = Int(exactly: value) { return .integer(integer) }
            return .number(value)
        case let value as String: return .string(ScalarKey(value))
        case let value as SafeHTML: return .string(ScalarKey(value.value))
        case let range as RuntimeRange: return .range(range.start, range.end)
        case let values as [Any]:
            var keys: [Self] = []
            for value in values { guard let key = make(value) else { return nil }; keys.append(key) }
            return .array(keys)
        case let object as RuntimeObject: return members(Array(object))
        case let object as [String: Any]: return members(object.map { (key: $0.key, value: $0.value) })
        default: return nil
        }
    }

    private static func members(_ values: [(key: String, value: Any)]) -> Self? {
        var members: [Member] = []
        for (key, value) in values {
            guard let value = make(value) else { return nil }
            members.append(Member(key: ScalarKey(key), value: value))
        }
        members.sort { $0.key.string.utf8.lexicographicallyPrecedes($1.key.string.utf8) }
        return .object(members)
    }
}
