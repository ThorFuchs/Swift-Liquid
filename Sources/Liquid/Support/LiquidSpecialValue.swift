// SPDX-License-Identifier: Apache-2.0
internal enum LiquidSpecialValue: String, Sendable, Hashable {
    case empty, blank
}

internal struct RuntimeRange {
    let start: Int
    let end: Int
    var description: String { "\(start)..\(end)" }
    var values: [Any] { start > end ? [] : Array(start...end) }
}
