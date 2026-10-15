// SPDX-License-Identifier: Apache-2.0
internal enum LiquidSpecialValue: String, Sendable, Hashable {
    case empty, blank
}

internal struct RuntimeRange: Sendable {
    let start: Int
    let end: Int
    // Checked at range admission; property access never materializes the range.
    let count: Int
    var description: String { "\(start)..\(end)" }
    var values: [Any] { start > end ? [] : Array(start...end) }

    func commandValue(for key: String) -> Int? {
        switch key {
        case "first": return start
        case "last": return end
        case "size": return count
        default: return nil
        }
    }
}
