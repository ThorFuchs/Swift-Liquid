// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  StringUtils.swift
//  LiquidUtilities
//
//

import Foundation

internal enum StringUtils {
    internal static func trimmingWhitespaceAndNewlines(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal static func isBlank(_ string: String) -> Bool {
        string.allSatisfy(\.isWhitespace)
    }

    internal static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }
}
