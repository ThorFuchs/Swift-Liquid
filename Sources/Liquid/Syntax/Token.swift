// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  Token.swift
//  LiquidCore
//
//

import Foundation

internal struct Token: Sendable, Equatable {
    // MARK: - Properties
    
    internal let type: TokenType
    
    internal let position: Int
    
    internal let line: Int
    
    internal let column: Int
    
    internal let trimLeft: Bool
    
    internal let trimRight: Bool
    internal let exactInteger: Int?
    
    // MARK: - Initialization
    
    internal init(
        type: TokenType,
        position: Int,
        line: Int,
        column: Int,
        trimLeft: Bool = false,
        trimRight: Bool = false,
        exactInteger: Int? = nil
    ) {
        self.type = type
        self.position = position
        self.line = line
        self.column = column
        self.trimLeft = trimLeft
        self.trimRight = trimRight
        self.exactInteger = exactInteger
    }
}

// MARK: - Token Extensions

extension Token {
    internal var isDelimiter: Bool {
        switch type {
        case .variableStart, .variableEnd, .tagStart, .tagEnd:
            return true
        default:
            return false
        }
    }
    
    internal var isOpeningDelimiter: Bool {
        switch type {
        case .variableStart, .tagStart:
            return true
        default:
            return false
        }
    }
    
    internal var isClosingDelimiter: Bool {
        switch type {
        case .variableEnd, .tagEnd:
            return true
        default:
            return false
        }
    }
    
    internal var isText: Bool {
        if case .text = type {
            return true
        }
        return false
    }
    
    internal var isIdentifier: Bool {
        if case .identifier = type {
            return true
        }
        return false
    }
    
    internal var isLiteral: Bool {
        switch type {
        case .string, .number:
            return true
        case .identifier(let name):
            // Check for boolean literals
            return name.equals("true")
                || name.equals("false")
                || name.equals("nil")
                || name.equals("null")
        default:
            return false
        }
    }
    
    internal var stringValue: String? {
        switch type {
        case .text(let content), .identifier(let content), .string(let content):
            return content.description
        default:
            return nil
        }
    }
    
    internal var numberValue: Double? {
        if case .number(let value, _) = type {
            return value
        }
        return nil
    }
}

// MARK: - Token Position Information

extension Token {
    internal var sourceLocation: SourceLocation {
        SourceLocation(
            position: position,
            line: line,
            column: column
        )
    }
    
    internal var positionDescription: String {
        "line \(line), column \(column)"
    }
}

internal struct SourceLocation: Sendable, Equatable {
    internal let position: Int
    
    internal let line: Int
    
    internal let column: Int
    
    internal init(position: Int, line: Int, column: Int) {
        self.position = position
        self.line = line
        self.column = column
    }
}

// MARK: - CustomStringConvertible

extension Token: CustomStringConvertible {
    internal var description: String {
        let trimInfo = (trimLeft || trimRight) ? 
            " (trim: \(trimLeft ? "left" : "")\(trimLeft && trimRight ? "+" : "")\(trimRight ? "right" : ""))" : ""
        return "\(type) at \(positionDescription)\(trimInfo)"
    }
}

extension SourceLocation: CustomStringConvertible {
    internal var description: String {
        "line \(line), column \(column) (position \(position))"
    }
}

// MARK: - Token Collection Utilities

extension Collection where Element == Token {
    internal func first(where type: TokenType) -> Token? {
        return first { $0.type == type }
    }
    
    internal func filter(by type: TokenType) -> [Token] {
        return filter { $0.type == type }
    }
    
    internal func contains(type: TokenType) -> Bool {
        return contains { $0.type == type }
    }
}
