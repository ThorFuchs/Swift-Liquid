// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  TokenType.swift
//  LiquidCore
//
//

import Foundation

internal enum TokenType: Equatable, Sendable {
    // MARK: - Text Content
    case text(InlineString)
    
    // MARK: - Liquid Delimiters
    case variableStart
    case variableEnd
    case tagStart
    case tagEnd
    
    // MARK: - Identifiers and Literals
    case identifier(InlineString)
    case string(InlineString)
    case number(Double, isFloat: Bool = false)
    
    // MARK: - Operators and Punctuation
    case filter
    case colon
    case comma
    case dot
    case equals
    case notEquals
    case lessThan
    case greaterThan
    case lessThanOrEqual
    case greaterThanOrEqual
    case range
    case leftParen
    case rightParen
    case leftBracket
    case rightBracket
    
    // MARK: - Logical Operators
    case contains
    case and
    case or
    case `is`
    
    // MARK: - Control Flow Tags
    case `if`
    case elsif
    case `else`
    case endif
    case unless
    case endunless
    case `case`
    case when
    case endcase
    
    // MARK: - Loop Tags
    case `for`
    case endfor
    case `in`
    case empty
    case `break`
    case `continue`
    case tablerow
    case endtablerow
    case cycle
    
    // MARK: - Variable Tags
    case assign
    case capture
    case endcapture
    case increment
    case decrement
    
    // MARK: - Include and Template Tags
    case include
    case render
    case block
    case endblock
    case macro
    case endmacro
    case `import`
    case from
    case input
    case call
    case render_block
    case with
    case recursive
    case loop
    
    // MARK: - Utility Tags
    case comment
    case endcomment
    case raw
    case endraw
    case liquid
    case endliquid
    case echo
    case debug
    case pipeline
    case endpipeline
}

// MARK: - TokenType Extensions

extension TokenType {
    internal var keywordString: String? {
        switch self {
        case .include: return "include"
        case .for: return "for"
        case .if: return "if"
        case .elsif: return "elsif"
        case .else: return "else"
        case .unless: return "unless"
        case .case: return "case"
        case .when: return "when"
        case .comment: return "comment"
        case .raw: return "raw"
        case .capture: return "capture"
        case .tablerow: return "tablerow"
        case .cycle: return "cycle"
        default: return nil
        }
    }

    internal var sourceLexeme: String {
        switch self {
        case .text(let content):
            return content.string
        case .variableStart:
            return "{{"
        case .variableEnd:
            return "}}"
        case .tagStart:
            return "{%"
        case .tagEnd:
            return "%}"
        case .identifier(let name):
            return name.string
        case .string(let value):
            let escaped = value.string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case .number(let value, _):
            if value.rounded(.towardZero) == value {
                return String(Int(value))
            }
            return String(value)
        case .filter:
            return "|"
        case .colon:
            return ":"
        case .comma:
            return ","
        case .dot:
            return "."
        case .equals:
            return "="
        case .notEquals:
            return "!="
        case .lessThan:
            return "<"
        case .greaterThan:
            return ">"
        case .lessThanOrEqual:
            return "<="
        case .greaterThanOrEqual:
            return ">="
        case .range:
            return ".."
        case .leftParen:
            return "("
        case .rightParen:
            return ")"
        case .leftBracket:
            return "["
        case .rightBracket:
            return "]"
        case .contains:
            return "contains"
        case .and:
            return "and"
        case .or:
            return "or"
        case .is:
            return "is"
        case .if:
            return "if"
        case .elsif:
            return "elsif"
        case .else:
            return "else"
        case .endif:
            return "endif"
        case .unless:
            return "unless"
        case .endunless:
            return "endunless"
        case .case:
            return "case"
        case .when:
            return "when"
        case .endcase:
            return "endcase"
        case .for:
            return "for"
        case .endfor:
            return "endfor"
        case .in:
            return "in"
        case .empty:
            return "empty"
        case .break:
            return "break"
        case .continue:
            return "continue"
        case .tablerow:
            return "tablerow"
        case .endtablerow:
            return "endtablerow"
        case .cycle:
            return "cycle"
        case .assign:
            return "assign"
        case .capture:
            return "capture"
        case .endcapture:
            return "endcapture"
        case .increment:
            return "increment"
        case .decrement:
            return "decrement"
        case .include:
            return "include"
        case .render:
            return "render"
        case .block:
            return "block"
        case .endblock:
            return "endblock"
        case .macro:
            return "macro"
        case .endmacro:
            return "endmacro"
        case .import:
            return "import"
        case .from:
            return "from"
        case .input:
            return "input"
        case .call:
            return "call"
        case .render_block:
            return "render_block"
        case .with:
            return "with"
        case .recursive:
            return "recursive"
        case .loop:
            return "loop"
        case .comment:
            return "comment"
        case .endcomment:
            return "endcomment"
        case .raw:
            return "raw"
        case .endraw:
            return "endraw"
        case .liquid:
            return "liquid"
        case .endliquid:
            return "endliquid"
        case .echo:
            return "echo"
        case .debug:
            return "debug"
        case .pipeline:
            return "pipeline"
        case .endpipeline:
            return "endpipeline"
        }
    }

    internal var requiresEndTag: Bool {
        switch self {
        case .if, .unless, .case, .for, .capture, .comment, .raw, .liquid,
             .block, .macro, .tablerow, .pipeline:
            return true
        default:
            return false
        }
    }
    
    internal var isControlFlow: Bool {
        switch self {
        case .if, .elsif, .else, .endif, .unless, .endunless, 
             .case, .when, .endcase:
            return true
        default:
            return false
        }
    }
    
    internal var isLoop: Bool {
        switch self {
        case .for, .endfor, .in, .empty, .break, .continue, .tablerow, .endtablerow, .cycle:
            return true
        default:
            return false
        }
    }
    
    internal var isOperator: Bool {
        switch self {
        case .filter, .equals, .notEquals, .lessThan, .greaterThan,
             .lessThanOrEqual, .greaterThanOrEqual, .contains, .and, .or, .is, .range:
            return true
        default:
            return false
        }
    }
    
    internal var endTag: TokenType? {
        switch self {
        case .if: return .endif
        case .unless: return .endunless
        case .case: return .endcase
        case .for: return .endfor
        case .capture: return .endcapture
        case .comment: return .endcomment
        case .raw: return .endraw
        case .liquid: return .endliquid
        case .block: return .endblock
        case .macro: return .endmacro
        case .tablerow: return .endtablerow
        case .pipeline: return .endpipeline
        default: return nil
        }
    }
}

// MARK: - CustomStringConvertible

extension TokenType: CustomStringConvertible {
    internal var description: String {
        switch self {
        case .text(let content): return "text(\(content))"
        case .variableStart: return "{{"
        case .variableEnd: return "}}"
        case .tagStart: return "{%"
        case .tagEnd: return "%}"
        case .identifier(let name): return "identifier(\(name))"
        case .string(let value): return "string(\(value))"
        case .number(let value, _): return "number(\(value))"
        case .filter: return "|"
        case .colon: return ":"
        case .comma: return ","
        case .dot: return "."
        case .equals: return "=="
        case .notEquals: return "!="
        case .lessThan: return "<"
        case .greaterThan: return ">"
        case .lessThanOrEqual: return "<="
        case .greaterThanOrEqual: return ">="
        case .range: return ".."
        case .leftParen: return "("
        case .rightParen: return ")"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .contains: return "contains"
        case .and: return "and"
        case .or: return "or"
        case .is: return "is"
        case .if: return "if"
        case .elsif: return "elsif"
        case .else: return "else"
        case .endif: return "endif"
        case .unless: return "unless"
        case .endunless: return "endunless"
        case .case: return "case"
        case .when: return "when"
        case .endcase: return "endcase"
        case .for: return "for"
        case .endfor: return "endfor"
        case .in: return "in"
        case .empty: return "empty"
        case .break: return "break"
        case .continue: return "continue"
        case .tablerow: return "tablerow"
        case .endtablerow: return "endtablerow"
        case .cycle: return "cycle"
        case .assign: return "assign"
        case .capture: return "capture"
        case .endcapture: return "endcapture"
        case .increment: return "increment"
        case .decrement: return "decrement"
        case .include: return "include"
        case .render: return "render"
        case .block: return "block"
        case .endblock: return "endblock"
        case .macro: return "macro"
        case .endmacro: return "endmacro"
        case .import: return "import"
        case .from: return "from"
        case .input: return "input"
        case .call: return "call"
        case .render_block: return "render_block"
        case .with: return "with"
        case .recursive: return "recursive"
        case .loop: return "loop"
        case .comment: return "comment"
        case .endcomment: return "endcomment"
        case .raw: return "raw"
        case .endraw: return "endraw"
        case .liquid: return "liquid"
        case .endliquid: return "endliquid"
        case .echo: return "echo"
        case .debug: return "debug"
        case .pipeline: return "pipeline"
        case .endpipeline: return "endpipeline"
        }
    }
}
