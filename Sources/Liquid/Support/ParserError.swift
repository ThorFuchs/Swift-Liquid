// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  ParserError.swift
//  LiquidCore
//
//

import Foundation

internal enum ParserError: Error, Sendable, Equatable {
    case unexpectedToken(Token)
    
    case expectedToken(TokenType, got: TokenType)
    
    case expectedIdentifier
    
    case expectedNumber
    
    case expectedString
    
    case expectedExpression
    
    case expectedTestOperator
    
    case unknownTag(String)

    case unsupportedFeature(String)
    
    case unclosedTag(String)
    
    case invalidForLoopParameter
    
    case unknownForLoopParameter(String)
    
    case invalidRange
    
    case malformedFilter(String)
    
    case nestingTooDeep(Int)
    
    case invalidAssignmentTarget
    
    case duplicateParameter(String)
    
    case missingRequiredParameter(String)
    
    case invalidParameterValue(String, expected: String)
}

// MARK: - Error Information

extension ParserError {
    internal var message: String {
        switch self {
        case .unexpectedToken(let token):
            return "Unexpected token: \(token.type)"
        case .expectedToken(let expected, let got):
            return "Expected \(expected) but found \(got)"
        case .expectedIdentifier:
            return "Expected identifier"
        case .expectedNumber:
            return "Expected number"
        case .expectedString:
            return "Expected string literal"
        case .expectedExpression:
            return "Expected expression"
        case .expectedTestOperator:
            return "Expected test operator after 'is'"
        case .unknownTag(let tag):
            return "Unknown tag '\(tag)'"
        case .unsupportedFeature(let feature):
            return "Unsupported feature: \(feature)"
        case .unclosedTag(let tag):
            return "Unclosed tag '\(tag)'"
        case .invalidForLoopParameter:
            return "Invalid for loop parameter"
        case .unknownForLoopParameter(let param):
            return "Unknown for loop parameter '\(param)'"
        case .invalidRange:
            return "Invalid range expression"
        case .malformedFilter(let filter):
            return "Malformed filter '\(filter)'"
        case .nestingTooDeep(let depth):
            return "Nesting too deep (\(depth) levels)"
        case .invalidAssignmentTarget:
            return "Invalid assignment target"
        case .duplicateParameter(let param):
            return "Duplicate parameter '\(param)'"
        case .missingRequiredParameter(let param):
            return "Missing required parameter '\(param)'"
        case .invalidParameterValue(let param, let expected):
            return "Invalid value for parameter '\(param)' (expected \(expected))"
        }
    }
    
    internal var category: ParserErrorCategory {
        switch self {
        case .unexpectedToken, .expectedToken, .expectedIdentifier, .expectedNumber, 
             .expectedString, .expectedExpression, .expectedTestOperator:
            return .syntax
        case .unknownTag, .unknownForLoopParameter:
            return .unknown
        case .unsupportedFeature:
            return .semantic
        case .unclosedTag:
            return .structure
        case .invalidForLoopParameter, .invalidRange, .malformedFilter, 
             .invalidAssignmentTarget, .invalidParameterValue:
            return .semantic
        case .nestingTooDeep:
            return .limit
        case .duplicateParameter, .missingRequiredParameter:
            return .parameter
        }
    }
    
    internal var sourceLocation: SourceLocation? {
        switch self {
        case .unexpectedToken(let token):
            return token.sourceLocation
        default:
            return nil
        }
    }
}

// MARK: - Error Recovery and Suggestions

extension ParserError {
    internal var suggestion: String? {
        switch self {
        case .unexpectedToken(let token):
            switch token.type {
            case .tagEnd:
                return "Check if you're missing a tag name or expression"
            case .variableEnd:
                return "Ensure the variable expression is complete"
            default:
                return "Check the syntax around this token"
            }
        case .expectedToken(let expected, let got):
            switch expected {
            case .tagEnd:
                return "Add '%}' to close the tag"
            case .variableEnd:
                return "Add '}}' to close the variable"
            case .colon:
                return "Add ':' for named parameter syntax"
            default:
                return "Replace \(got) with \(expected)"
            }
        case .expectedIdentifier:
            return "Provide a valid variable or tag name"
        case .expectedNumber:
            return "Use a numeric value (e.g., 42, 3.14)"
        case .expectedString:
            return "Use a quoted string (e.g., \"hello\" or 'world')"
        case .expectedExpression:
            return "Provide a valid expression (variable, literal, or operation)"
        case .expectedTestOperator:
            return "Use a valid test like 'defined', 'empty', 'number', etc."
        case .unknownTag(let tag):
            return checkTagNameSuggestion(for: tag)
        case .unsupportedFeature(let feature):
            return "Use only the actively supported 1.x syntax surface. \(feature)"
        case .unclosedTag(let tag):
            return "Add {% end\(tag) %} to close the \(tag) block"
        case .invalidForLoopParameter:
            return "Use valid parameters: limit, offset, reversed, or if"
        case .unknownForLoopParameter(let param):
            return "Use valid parameters: limit, offset, reversed, or if (not '\(param)')"
        case .invalidRange:
            return "Use numeric values for range bounds (e.g., (1..10))"
        case .malformedFilter(let filter):
            return "Check the syntax for filter '\(filter)' and its arguments"
        case .nestingTooDeep:
            return "Reduce the nesting depth of your template structure"
        case .invalidAssignmentTarget:
            return "Assign only to simple variable names"
        case .duplicateParameter(let param):
            return "Remove the duplicate '\(param)' parameter"
        case .missingRequiredParameter(let param):
            return "Add the required '\(param)' parameter"
        case .invalidParameterValue(let param, let expected):
            return "Provide a \(expected) value for parameter '\(param)'"
        }
    }
    
    private func checkTagNameSuggestion(for tag: String) -> String? {
        let commonTags = [
            "if", "elsif", "else", "endif",
            "unless", "endunless",
            "case", "when", "endcase",
            "for", "endfor",
            "assign", "capture", "endcapture",
            "include", "render",
            "comment", "endcomment",
            "raw", "endraw",
            "cycle", "tablerow", "endtablerow"
        ]
        
        // Simple Levenshtein distance for typo detection
        let suggestions = commonTags.filter { levenshteinDistance(tag, $0) <= 2 }
        
        if !suggestions.isEmpty {
            return "Did you mean: \(suggestions.joined(separator: ", "))?"
        } else {
            return "Use a built-in tag or register a custom tag"
        }
    }
}

internal enum ParserErrorCategory: String, Sendable, CaseIterable {
    case syntax = "Syntax Error"
    case unknown = "Unknown Element"
    case structure = "Structure Error"
    case semantic = "Semantic Error"
    case limit = "Limit Exceeded"
    case parameter = "Parameter Error"
}

// MARK: - Utility Functions

private func levenshteinDistance(_ a: String, _ b: String) -> Int {
    let aChars = Array(a)
    let bChars = Array(b)
    let aCount = aChars.count
    let bCount = bChars.count
    
    if aCount == 0 { return bCount }
    if bCount == 0 { return aCount }
    
    var matrix = Array(repeating: Array(repeating: 0, count: bCount + 1), count: aCount + 1)
    
    for i in 0...aCount { matrix[i][0] = i }
    for j in 0...bCount { matrix[0][j] = j }
    
    for i in 1...aCount {
        for j in 1...bCount {
            let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
            matrix[i][j] = min(
                matrix[i-1][j] + 1,     // deletion
                matrix[i][j-1] + 1,     // insertion
                matrix[i-1][j-1] + cost // substitution
            )
        }
    }
    
    return matrix[aCount][bCount]
}

// MARK: - CustomStringConvertible

extension ParserError: CustomStringConvertible {
    internal var description: String {
        let locationInfo = sourceLocation?.description ?? "unknown location"
        let suggestion = self.suggestion.map { " (\($0))" } ?? ""
        return "\(category.rawValue): \(message) at \(locationInfo)\(suggestion)"
    }
}

extension ParserError: LocalizedError {
    internal var errorDescription: String? {
        return description
    }
    
    internal var recoverySuggestion: String? {
        return suggestion
    }
}
