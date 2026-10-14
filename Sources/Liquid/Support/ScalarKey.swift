// SPDX-License-Identifier: Apache-2.0

// Liquid string keys preserve scalar spelling; Swift's canonically equivalent
// String equality must not merge distinct Liquid properties.
internal struct ScalarKey: Hashable {
    let string: String
    init(_ string: String) { self.string = string }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.string.utf8.elementsEqual(rhs.string.utf8) }
    func hash(into hasher: inout Hasher) { for byte in string.utf8 { hasher.combine(byte) } }
}

internal struct RuntimeVariables: ExpressibleByDictionaryLiteral, Sequence {
    private var storage: [ScalarKey: Any] = [:]
    init(_ pairs: [(String, Any)] = []) { for (key, value) in pairs { storage[ScalarKey(key)] = value } }
    init(dictionaryLiteral elements: (String, Any)...) { self.init(elements) }
    subscript(_ key: String) -> Any? {
        get { storage[ScalarKey(key)] }
        set {
            if newValue is LiquidSpecialValue { storage[ScalarKey(key)] = "" }
            else { storage[ScalarKey(key)] = newValue }
        }
    }
    mutating func reserveCapacity(_ count: Int) { storage.reserveCapacity(count) }
    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }
    mutating func removeValue(forKey key: String) { storage.removeValue(forKey: ScalarKey(key)) }
    mutating func removeAll(keepingCapacity: Bool) { storage.removeAll(keepingCapacity: keepingCapacity) }
    func makeIterator() -> IndexingIterator<[(key: String, value: Any)]> {
        storage.map { (key: $0.key.string, value: $0.value) }.makeIterator()
    }
}
