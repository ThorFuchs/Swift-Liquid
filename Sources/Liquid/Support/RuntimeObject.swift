// SPDX-License-Identifier: Apache-2.0

// Invocation-local bridge used by the adapted evaluator. No values cross a task boundary.
internal struct RuntimeObject: RandomAccessCollection {
    typealias Element = (key: String, value: Any)
    let elements: [Element]
    private let positions: [ScalarKey: Int]
    init(uniqueKeysWithValues pairs: [(String, Any)]) {
        elements = pairs.map { (key: $0.0, value: $0.1) }
        positions = Dictionary(uniqueKeysWithValues: pairs.enumerated().map { (ScalarKey($0.element.0), $0.offset) })
    }
    var startIndex: Int { elements.startIndex }
    var endIndex: Int { elements.endIndex }
    subscript(position: Int) -> Element { elements[position] }
    subscript(key: String) -> Any? { positions[ScalarKey(key)].map { elements[$0].value } }
}
