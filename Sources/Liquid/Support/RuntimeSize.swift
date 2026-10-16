// SPDX-License-Identifier: Apache-2.0

// The typed public value domain. Nil means no size command; the filter's
// documented nil/unsupported fallback is zero. Text counts Unicode scalars.
internal func runtimeValueSize(_ value: Any) -> Int? {
    if let range = value as? RuntimeRange { return range.count }
    if value is Int { return MemoryLayout<Int>.size }
    if let string = value as? String { return string.unicodeScalars.count }
    if let array = value as? [Any] { return array.count }
    if let object = value as? RuntimeObject { return object.count }
    return nil
}

internal func runtimeSizeProperty(_ value: Any) -> Any? {
    if let object = value as? RuntimeObject { return object["size"] ?? object.count }
    // Engine-created loop records expose their declared fields, including
    // length. They are not user-supplied maps with an implicit size command.
    if let fields = value as? [String: Any] { return fields["size"] }
    return runtimeValueSize(value)
}
