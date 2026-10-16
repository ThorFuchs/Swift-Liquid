// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  LexerError.swift
//  LiquidCore
//
//

import Foundation

internal enum LexerError: Error, Sendable, Equatable {
    case unexpectedCharacter(Character, position: Int, origin: DiagnosticOriginResolution? = nil)
    
    case unterminatedString(position: Int)
    
    case invalidNumber(String, position: Int)
    
    case invalidEscapeSequence(Character, position: Int)
    
    case invalidUTF8(position: Int)
    
    case unclosedDelimiter(String, position: Int)
    
    case unexpectedEndOfInput(position: Int)
}

// MARK: - Error Information

extension LexerError {
    internal var message: String {
        switch self {
        case .unexpectedCharacter(let char, _, .resolved(let origin)?):
            let context = origin.presentation == .outputMarkup ? "{{" + origin.contextText + "}}" : origin.contextText
            return "Unexpected character \(char) in \"\(context)\""
        case .unexpectedCharacter(let char, _, _):
            return "Unexpected character '\(char)'"
        case .unterminatedString:
            return "Unterminated string literal"
        case .invalidNumber(let string, _):
            return "Invalid number '\(string)'"
        case .invalidEscapeSequence(let char, _):
            return "Invalid escape sequence '\\\(char)'"
        case .invalidUTF8:
            return "Invalid UTF-8 sequence"
        case .unclosedDelimiter(let delimiter, _):
            return "Unclosed delimiter '\(delimiter)'"
        case .unexpectedEndOfInput:
            return "Unexpected end of input"
        }
    }
    
    internal var position: Int {
        switch self {
        case .unexpectedCharacter(_, let pos, _),
             .unterminatedString(let pos),
             .invalidNumber(_, let pos),
             .invalidEscapeSequence(_, let pos),
             .invalidUTF8(let pos),
             .unclosedDelimiter(_, let pos),
             .unexpectedEndOfInput(let pos):
            return pos
        }
    }
    
    internal var category: ErrorCategory {
        switch self {
        case .unexpectedCharacter, .invalidUTF8:
            return .syntax
        case .unterminatedString, .unclosedDelimiter:
            return .unterminated
        case .invalidNumber, .invalidEscapeSequence:
            return .malformed
        case .unexpectedEndOfInput:
            return .incomplete
        }
    }
}

// MARK: - Error Recovery

extension LexerError {
    internal var suggestion: String? {
        switch self {
        case .unexpectedCharacter(let char, _, _):
            if char.isWhitespace {
                return "Check for missing delimiters or incorrect tag structure"
            } else {
                return "Remove or escape the unexpected character"
            }
        case .unterminatedString:
            return "Add a closing quote to complete the string literal"
        case .invalidNumber(let string, _):
            if string.contains(".") {
                return "Check decimal point placement in the number"
            } else {
                return "Ensure the number contains only valid digits"
            }
        case .invalidEscapeSequence(let char, _):
            return "Use a valid escape sequence or escape the backslash: \\\(char) or \\\\"
        case .invalidUTF8:
            return "Ensure the template file is saved with UTF-8 encoding"
        case .unclosedDelimiter(let delimiter, _):
            switch delimiter {
            case "{{":
                return "Add '}}'  to close the variable"
            case "{%":
                return "Add '%}' to close the tag"
            default:
                return "Add the closing delimiter for '\(delimiter)'"
            }
        case .unexpectedEndOfInput:
            return "Complete the template with proper closing tags"
        }
    }
}

internal enum ErrorCategory: String, Sendable, CaseIterable {
    case syntax = "Syntax Error"
    case unterminated = "Unterminated Construct"
    case malformed = "Malformed Content"
    case incomplete = "Incomplete Template"
}

// MARK: - CustomStringConvertible

extension LexerError: CustomStringConvertible {
    internal var description: String {
        let suggestion = self.suggestion.map { " (\($0))" } ?? ""
        return "\(category.rawValue): \(message) at position \(position)\(suggestion)"
    }
}

extension LexerError: LocalizedError {
    internal var errorDescription: String? {
        return description
    }
    
    internal var recoverySuggestion: String? {
        return suggestion
    }
}
