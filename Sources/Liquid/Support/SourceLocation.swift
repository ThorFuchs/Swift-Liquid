// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  SourceLocation.swift
//  LiquidCore
//
//

import Foundation

internal struct LiquidSourceLocation: Sendable, Equatable, Codable {
    internal let line: Int
    
    internal let column: Int
    
    internal let position: Int
    
    internal let templateName: String?
    
    internal init(line: Int, column: Int, position: Int, templateName: String? = nil) {
        self.line = line
        self.column = column
        self.position = position
        self.templateName = templateName
    }
    
    internal init(from token: Token) {
        self.line = token.line
        self.column = token.column
        self.position = token.position
        self.templateName = nil
    }
    
    internal static let unknown = LiquidSourceLocation(line: 0, column: 0, position: 0)
}

// MARK: - CustomStringConvertible

extension LiquidSourceLocation: CustomStringConvertible {
    internal var description: String {
        if let templateName = templateName {
            return "\(templateName):\(line):\(column)"
        } else {
            return "\(line):\(column)"
        }
    }
}

// MARK: - Comparable

extension LiquidSourceLocation: Comparable {
    internal static func < (lhs: LiquidSourceLocation, rhs: LiquidSourceLocation) -> Bool {
        if lhs.line != rhs.line {
            return lhs.line < rhs.line
        }
        return lhs.column < rhs.column
    }
}
