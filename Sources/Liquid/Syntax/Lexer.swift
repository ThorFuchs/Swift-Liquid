// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  Lexer.swift
//  LiquidLexer
//
//

import Foundation

private enum LexerContext {
    case text        // Outside of any Liquid constructs
    case tag         // Inside {% ... %} tags
    case variable    // Inside {{ ... }} variables  
    case filter      // After | pipe in variable or tag context
}

internal final class Lexer {
    private static let openBrace: UInt8 = 0x7B
    private static let closeBrace: UInt8 = 0x7D
    private static let percent: UInt8 = 0x25
    private static let pipe: UInt8 = 0x7C
    private static let colon: UInt8 = 0x3A
    private static let comma: UInt8 = 0x2C
    private static let dot: UInt8 = 0x2E
    private static let equals: UInt8 = 0x3D
    private static let exclamation: UInt8 = 0x21
    private static let lessThan: UInt8 = 0x3C
    private static let greaterThan: UInt8 = 0x3E
    private static let leftParen: UInt8 = 0x28
    private static let rightParen: UInt8 = 0x29
    private static let leftBracket: UInt8 = 0x5B
    private static let rightBracket: UInt8 = 0x5D
    private static let doubleQuote: UInt8 = 0x22
    private static let singleQuote: UInt8 = 0x27
    private static let backslash: UInt8 = 0x5C
    private static let underscore: UInt8 = 0x5F
    private static let newline: UInt8 = 0x0A
    private static let dash: UInt8 = 0x2D // '-' for whitespace control

    // MARK: - Properties

    private let bytes: [UInt8]
    private let sourceProvenance: DiagnosticSourceProvenance

    private var byteIndex: Int = 0
    
    private var line: Int = 1
    
    private var column: Int = 1
    
    private var context: LexerContext = .text

    private var filterParentContext: LexerContext = .text
    
    // MARK: - Initialization
    
    internal init(_ input: String, sourceProvenance: DiagnosticSourceProvenance = .unmapped) {
        self.bytes = Array(input.utf8)
        self.sourceProvenance = sourceProvenance
    }
    
    // MARK: - Public Interface
    
    internal func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        tokens.reserveCapacity(max(8, bytes.count / 6))
        byteIndex = 0
        line = 1
        column = 1
        context = .text
        filterParentContext = .text

        while !isAtEnd {
            let start = currentPosition
            let firstToken = tokens.count
            do {
                try tokenizeNext(&tokens, startPosition: start)
            } catch {
                guard case .unexpectedCharacter(let character, let offset, _) = error else { throw error }
                let origin: DiagnosticOriginResolution
                switch sourceProvenance {
                case .original(let identity):
                    origin = try diagnosticOrigin(character, at: offset, start: start.position,
                        tokens: tokens[firstToken...], identity: identity)
                case .unmapped:
                    origin = .unmapped(.unspecifiedOrRewrittenSource)
                }
                throw LexerError.unexpectedCharacter(character, position: offset, origin: origin)
            }
        }

        // Post-process: apply whitespace trimming from {%- -%} {{- -}} markers
        applyWhitespaceTrimming(&tokens)

        return tokens
    }

    private func diagnosticOrigin(_ character: Character, at offset: Int, start: Int,
                                  tokens: ArraySlice<Token>, identity: DiagnosticSourceIdentity) throws -> DiagnosticOriginResolution {
        try Task.checkCancellation()
        guard let opening = tokens.first else { return .unmapped(.incompleteOrAmbiguousConstruct) }
        let variable = opening.type == .variableStart
        guard variable || (opening.type == .tagStart && tokens.count >= 2),
              start >= 0, bytes.count - start >= 2 else { return .unmapped(.incompleteOrAmbiguousConstruct) }
        // Error presentation only: pinned Ruby tokenizer.rb next_tag_token and
        // next_variable_token use first terminators/brace transitions. This never
        // admits source, advances the native cursor, or creates rendering nodes.
        let closing: (UInt8, UInt8) = variable ? (125, 125) : (37, 125)
        var end = start + 2
        while end < bytes.count - 1 {
            if end & 255 == 0 { try Task.checkCancellation() }
            if bytes[end] == closing.0, bytes[end + 1] == closing.1 { break }
            if variable, bytes[end] == 125 || (bytes[end] == 123 && bytes[end + 1] == 37) {
                return .unmapped(.incompleteOrAmbiguousConstruct)
            }
            end += 1
        }
        guard end < bytes.count - 1, offset < end else { return .unmapped(.incompleteOrAmbiguousConstruct) }
        var lower = start + 2
        var upper = end
        if opening.trimLeft { lower += 1 }
        if upper > lower, bytes[upper - 1] == 45 { upper -= 1 }
        var anchor = start
        var presentation = DiagnosticContextPresentation.outputMarkup
        var header: Range<Int>?
        var headerSpelling: String?
        if !variable {
            let name = tokens[tokens.startIndex + 1]
            guard name.type != .liquid else { return .unmapped(.liquidInnerContext) }
            let spelling: String
            switch name.type {
            case .identifier(let value): spelling = value.string
            case .assign, .render, .echo, .increment, .decrement: spelling = name.type.sourceLexeme
            default:
                guard let keyword = name.type.keywordString else { return .unmapped(.incompleteOrAmbiguousConstruct) }
                spelling = keyword
            }
            guard name.position >= lower, name.position <= upper,
                  spelling.utf8.count <= upper - name.position else { return .unmapped(.invalidBoundary) }
            header = name.position..<(name.position + spelling.utf8.count)
            headerSpelling = spelling
            lower = name.position + spelling.utf8.count
            // Pinned block_body.rb FullToken header whitespace and
            // ParserSwitching markup.strip. The byte owner validates spelling.
            while lower < upper, bytes[lower] == 32 || (9...13).contains(bytes[lower]) {
                if lower & 255 == 0 { try Task.checkCancellation() }
                lower += 1
            }
            anchor = lower
            if name.type != .echo {
                presentation = .markup
                while lower < upper, bytes[lower] == 0 || bytes[lower] == 32 || (9...13).contains(bytes[lower]) {
                    if lower & 255 == 0 { try Task.checkCancellation() }
                    lower += 1
                }
                while upper > lower, bytes[upper - 1] == 0 || bytes[upper - 1] == 32 || (9...13).contains(bytes[upper - 1]) {
                    if upper & 255 == 0 { try Task.checkCancellation() }
                    upper -= 1
                }
            }
        }
        guard lower <= upper else { return .unmapped(.invalidBoundary) }
        let frame = DiagnosticSourceFrame(construct: start..<(end + 2), markup: lower..<upper,
            anchor: anchor, presentation: presentation, header: header, headerSpelling: headerSpelling)
        return try DiagnosticSourceSnapshot(admittedUTF8: bytes, identity: identity)
            .unexpectedCharacter(character, at: offset, frame: frame)
    }

    private func applyWhitespaceTrimming(_ tokens: inout [Token]) {
        for i in tokens.indices {
            let token = tokens[i]
            switch token.type {
            case .variableStart, .tagStart:
                if token.trimLeft, i > 0 {
                    if case .text(let content) = tokens[i - 1].type {
                        let trimmed = InlineString(content.string.trailingWhitespaceTrimmed())
                        tokens[i - 1] = Token(
                            type: .text(trimmed),
                            position: tokens[i - 1].position,
                            line: tokens[i - 1].line,
                            column: tokens[i - 1].column
                        )
                    }
                }
            case .variableEnd, .tagEnd:
                if token.trimRight, i + 1 < tokens.count {
                    if case .text(let content) = tokens[i + 1].type {
                        let trimmed = InlineString(content.string.leadingWhitespaceTrimmed())
                        tokens[i + 1] = Token(
                            type: .text(trimmed),
                            position: tokens[i + 1].position,
                            line: tokens[i + 1].line,
                            column: tokens[i + 1].column
                        )
                    }
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Tokenization
    
    private func tokenizeNext(_ tokens: inout [Token], startPosition: TokenPosition) throws(LexerError) {
        // Check for Liquid constructs
        if current == Self.openBrace {
            if peek() == Self.openBrace {
                try tokenizeVariable(&tokens, start: startPosition)
                return
            } else if peek() == Self.percent {
                try tokenizeTag(&tokens, start: startPosition)
                if tokens.count >= 2, case .identifier(let name) = tokens[tokens.count - 2].type,
                   name.equals("doc") {
                    try skipDocBlock(&tokens)
                }
                // After tokenizing a comment tag, skip to endcomment
                // (avoids lexer errors from invalid syntax inside comments)
                if tokens.count >= 2,
                   tokens[tokens.count - 2].type == .comment {
                    try skipCommentBlock(&tokens)
                }
                // After tokenizing a raw tag, skip to endraw
                // (avoids lexer errors from partial tags like %} or }} inside raw)
                if tokens.count >= 2,
                   tokens[tokens.count - 2].type == .raw {
                    skipRawBlock(&tokens)
                }
                return
            }
        }

        // Collect text until next Liquid construct
        try tokenizeText(&tokens, start: startPosition)
    }

    private func skipDocBlock(_ tokens: inout [Token]) throws(LexerError) {
        let remaining = String(decoding: bytes[byteIndex...], as: UTF8.self)
        guard let closing = remaining.range(of: #"\{%-?\s*enddoc\s*-?%\}"#, options: .regularExpression) else {
            throw LexerError.unclosedDelimiter("doc", position: byteIndex)
        }
        let body = remaining[..<closing.lowerBound]
        if body.range(of: #"\{%-?\s*doc(?:\s|%)"#, options: .regularExpression) != nil {
            throw LexerError.unclosedDelimiter("nested doc", position: byteIndex)
        }
        let before = body.utf8.count
        let endPosition = byteIndex + before
        let endTag = String(remaining[closing])
        let trimLeft = endTag.hasPrefix("{%-")
        let trimRight = endTag.hasSuffix("-%}")
        let end = byteIndex + remaining[..<closing.upperBound].utf8.count
        while byteIndex < end { advance() }
        tokens.append(Token(type: .tagStart, position: endPosition, line: line, column: column, trimLeft: trimLeft))
        tokens.append(Token(type: .identifier(InlineString("enddoc")), position: endPosition, line: line, column: column))
        tokens.append(Token(type: .tagEnd, position: byteIndex - 2, line: line, column: column, trimRight: trimRight))
    }

    private func skipCommentBlock(_ tokens: inout [Token]) throws(LexerError) {
        var depth = 1
        let end = bytes.count

        while byteIndex < end && depth > 0 {
            if bytes[byteIndex] == Self.openBrace, byteIndex + 1 < end, bytes[byteIndex + 1] == Self.openBrace {
                let remaining = String(decoding: bytes[byteIndex...], as: UTF8.self)
                guard let close = remaining.range(of: "}}"),
                      remaining.range(of: "endcomment").map({ close.lowerBound < $0.lowerBound }) ?? true else {
                    throw LexerError.unclosedDelimiter("{{", position: byteIndex)
                }
            }
            // Look for {% ... %}
            if bytes[byteIndex] == Self.openBrace,
               byteIndex + 1 < end,
               bytes[byteIndex + 1] == Self.percent {
                // Save position for potential token creation
                let tagStartPos = byteIndex
                let tagStartLine = line
                let tagStartCol = column
                advanceASCII() // {
                advanceASCII() // %
                // Skip optional trim marker
                if byteIndex < end, bytes[byteIndex] == Self.dash {
                    advanceASCII()
                }
                skipWhitespace()

                // Check for "comment" or "endcomment" keyword
                let wordStart = byteIndex
                while byteIndex < end, bytes[byteIndex].isIdentifierContinueByte || bytes[byteIndex].isIdentifierStartByte {
                    advanceASCII()
                }
                let wordLen = byteIndex - wordStart
                let word = bytes[wordStart..<byteIndex]

                if wordLen == 10, word.elementsEqual("endcomment".utf8) {
                    depth -= 1
                    if depth == 0 {
                        // Emit tagStart, endcomment, tagEnd
                        tokens.append(Token(type: .tagStart, position: tagStartPos, line: tagStartLine, column: tagStartCol))
                        tokens.append(Token(type: .endcomment, position: tagStartPos, line: tagStartLine, column: tagStartCol))
                        skipWhitespace()
                        // Skip optional trim marker before %}
                        let trimRight = byteIndex < end && bytes[byteIndex] == Self.dash
                        if trimRight { advanceASCII() }
                        // Skip %}
                        if byteIndex < end, bytes[byteIndex] == Self.percent { advanceASCII() }
                        if byteIndex < end, bytes[byteIndex] == Self.closeBrace { advanceASCII() }
                        tokens.append(Token(type: .tagEnd, position: tagStartPos, line: tagStartLine, column: tagStartCol, trimRight: trimRight))
                        context = .text
                        return
                    }
                } else if wordLen == 7, word.elementsEqual("comment".utf8) {
                    depth += 1
                } else if wordLen == 3, word.elementsEqual("raw".utf8) {
                    // Skip {% raw %} ... {% endraw %} inside comments
                    // First skip to closing %} of the raw tag
                    while byteIndex < end {
                        if bytes[byteIndex] == Self.percent, byteIndex + 1 < end, bytes[byteIndex + 1] == Self.closeBrace {
                            advanceASCII(); advanceASCII(); break
                        } else if bytes[byteIndex] == Self.dash, byteIndex + 2 < end, bytes[byteIndex + 1] == Self.percent, bytes[byteIndex + 2] == Self.closeBrace {
                            advanceASCII(); advanceASCII(); advanceASCII(); break
                        }
                        advance()
                    }
                    // Now scan for {% endraw %}
                    while byteIndex < end {
                        if bytes[byteIndex] == Self.openBrace, byteIndex + 1 < end, bytes[byteIndex + 1] == Self.percent {
                            let probe = byteIndex + 2
                            var p = probe
                            // Skip trim marker and whitespace
                            if p < end, bytes[p] == Self.dash { p += 1 }
                            while p < end, bytes[p] == 0x20 || bytes[p] == 0x09 || bytes[p] == 0x0A || bytes[p] == 0x0D { p += 1 }
                            if p + 6 <= end,
                               bytes[p] == 0x65, bytes[p+1] == 0x6E, bytes[p+2] == 0x64,
                               bytes[p+3] == 0x72, bytes[p+4] == 0x61, bytes[p+5] == 0x77 {
                                // Found endraw — skip past the closing %}
                                byteIndex = p + 6
                                while byteIndex < end {
                                    if bytes[byteIndex] == Self.percent, byteIndex + 1 < end, bytes[byteIndex + 1] == Self.closeBrace {
                                        advanceASCII(); advanceASCII(); break
                                    } else if bytes[byteIndex] == Self.dash, byteIndex + 2 < end, bytes[byteIndex + 1] == Self.percent, bytes[byteIndex + 2] == Self.closeBrace {
                                        advanceASCII(); advanceASCII(); advanceASCII(); break
                                    }
                                    advance()
                                }
                                break
                            }
                        }
                        advance()
                    }
                    continue // Don't fall through to the "skip to %}" below
                }
                // Skip to closing %}
                while byteIndex < end {
                    if bytes[byteIndex] == Self.percent,
                       byteIndex + 1 < end,
                       bytes[byteIndex + 1] == Self.closeBrace {
                        advanceASCII() // %
                        advanceASCII() // }
                        break
                    } else if bytes[byteIndex] == Self.dash,
                              byteIndex + 2 < end,
                              bytes[byteIndex + 1] == Self.percent,
                              bytes[byteIndex + 2] == Self.closeBrace {
                        advanceASCII() // -
                        advanceASCII() // %
                        advanceASCII() // }
                        break
                    }
                    advance()
                }
            } else {
                advance()
            }
        }
    }

    private func skipRawBlock(_ tokens: inout [Token]) {
        let end = bytes.count
        let rawStart = byteIndex
        let rawStartLine = line
        let rawStartCol = column

        // Scan for {% endraw %} or {%- endraw -%}
        while byteIndex < end {
            if bytes[byteIndex] == Self.openBrace,
               byteIndex + 1 < end,
               bytes[byteIndex + 1] == Self.percent {
                let tagPos = byteIndex
                let tagLine = line
                let tagCol = column
                var probe = byteIndex + 2
                // Skip optional trim marker
                var trimLeft = false
                if probe < end, bytes[probe] == Self.dash {
                    trimLeft = true
                    probe += 1
                }
                // Skip whitespace
                while probe < end, bytes[probe] == 0x20 || bytes[probe] == 0x09 || bytes[probe] == 0x0A || bytes[probe] == 0x0D {
                    probe += 1
                }
                // Check for "endraw"
                if probe + 6 <= end,
                   bytes[probe] == 0x65, bytes[probe+1] == 0x6E, bytes[probe+2] == 0x64,
                   bytes[probe+3] == 0x72, bytes[probe+4] == 0x61, bytes[probe+5] == 0x77 {
                    let afterWord = probe + 6
                    // Ensure it's not part of a longer identifier
                    if afterWord >= end || (!bytes[afterWord].isIdentifierContinueByte && !bytes[afterWord].isDigitByte) {
                        // Emit raw text content
                        if tagPos > rawStart {
                            let rawContent = InlineString(String(bytes: Array(bytes[rawStart..<tagPos]), encoding: .utf8) ?? "")
                            tokens.append(Token(type: .text(rawContent), position: rawStart, line: rawStartLine, column: rawStartCol))
                        }
                        // Advance past {%
                        byteIndex = tagPos
                        advanceASCII() // {
                        advanceASCII() // %
                        if trimLeft { advanceASCII() } // -
                        skipWhitespace()
                        // Emit tagStart, endraw, tagEnd
                        tokens.append(Token(type: .tagStart, position: tagPos, line: tagLine, column: tagCol, trimLeft: trimLeft))
                        // Skip "endraw"
                        for _ in 0..<6 { advanceASCII() }
                        tokens.append(Token(type: .endraw, position: tagPos, line: tagLine, column: tagCol))
                        skipWhitespace()
                        // Skip optional trim marker before %}
                        let trimRight = byteIndex < end && bytes[byteIndex] == Self.dash
                        if trimRight { advanceASCII() }
                        // Skip %}
                        if byteIndex < end, bytes[byteIndex] == Self.percent { advanceASCII() }
                        if byteIndex < end, bytes[byteIndex] == Self.closeBrace { advanceASCII() }
                        tokens.append(Token(type: .tagEnd, position: tagPos, line: tagLine, column: tagCol, trimRight: trimRight))
                        context = .text
                        return
                    }
                }
            }
            advance()
        }
    }

    private func tokenizeVariable(_ tokens: inout [Token], start: TokenPosition) throws(LexerError) {
        advanceASCII() // consume first {
        advanceASCII() // consume second {

        // Check for whitespace trim marker: {{-
        let trimLeft = byteIndex < bytes.count && bytes[byteIndex] == Self.dash
        if trimLeft {
            advanceASCII() // consume -
        }

        context = .variable  // Enter variable context
        tokens.append(Token(
            type: .variableStart,
            position: start.position,
            line: start.line,
            column: start.column,
            trimLeft: trimLeft
        ))

        // Skip whitespace
        skipWhitespace()

        let end = bytes.count
        
        // Tokenize the content inside
        while byteIndex < end {
            let byte = bytes[byteIndex]
            let nextByte = byteIndex + 1 < end ? bytes[byteIndex + 1] : 0

            if byte == Self.closeBrace, nextByte == Self.closeBrace {
                break
            }

            // Check for -}} whitespace trim marker
            if byte == Self.dash, byteIndex + 2 < end,
               bytes[byteIndex + 1] == Self.closeBrace, bytes[byteIndex + 2] == Self.closeBrace {
                break
            }

            if byte.isWhitespaceByte {
                skipWhitespace()
                continue
            }

            let tokenPosition = byteIndex
            let tokenLine = line
            let tokenColumn = column

            switch byte {
            case Self.pipe:
                advanceASCII()
                filterParentContext = context == .filter ? filterParentContext : context
                context = .filter  // Enter filter context
                tokens.append(Token(type: .filter, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.colon:
                advanceASCII()
                tokens.append(Token(type: .colon, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.comma:
                advanceASCII()
                // Exit filter context on comma.
                if context == .filter {
                    context = filterParentContext
                }
                tokens.append(Token(type: .comma, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.leftParen:
                advanceASCII()
                tokens.append(Token(type: .leftParen, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.rightParen:
                advanceASCII()
                tokens.append(Token(type: .rightParen, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.leftBracket:
                advanceASCII()
                tokens.append(Token(type: .leftBracket, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.rightBracket:
                advanceASCII()
                tokens.append(Token(type: .rightBracket, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.dot:
                if nextByte == Self.dot {
                    advanceASCII()
                    advanceASCII()
                    tokens.append(Token(type: .range, position: tokenPosition, line: tokenLine, column: tokenColumn))
                } else {
                    advanceASCII()
                    tokens.append(Token(type: .dot, position: tokenPosition, line: tokenLine, column: tokenColumn))
                }

            case Self.equals:
                advanceASCII()
                tokens.append(Token(type: .equals, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.doubleQuote, Self.singleQuote:
                let tokenStart = TokenPosition(position: tokenPosition, line: tokenLine, column: tokenColumn)
                try tokenizeString(&tokens, start: tokenStart, quote: byte)

            case let c where c.isDigitByte:
                let tokenStart = TokenPosition(position: tokenPosition, line: tokenLine, column: tokenColumn)
                try tokenizeNumber(&tokens, start: tokenStart)

            case Self.dash:
                // Check if this is a negative number literal (-5, -3.14)
                // vs a trim marker (-%}) — look ahead for digit
                let nextIdx = byteIndex + 1
                if nextIdx < end, bytes[nextIdx].isDigitByte {
                    // Negative number literal — only if previous token is not a value
                    // (to distinguish from subtraction like `5 - 3`)
                    let isUnary = tokens.isEmpty || {
                        let lastType = tokens.last!.type
                        switch lastType {
                        case .number, .string, .identifier: return false
                        case .rightParen, .rightBracket: return false
                        default: return true
                        }
                    }()
                    if isUnary {
                        let tokenStart = TokenPosition(position: tokenPosition, line: tokenLine, column: tokenColumn)
                        advanceASCII() // consume -
                        try tokenizeNumber(&tokens, start: tokenStart, negative: true)
                    } else {
                        throw LexerError.unexpectedCharacter(currentCharacter, position: byteIndex)
                    }
                } else {
                    throw LexerError.unexpectedCharacter(currentCharacter, position: byteIndex)
                }

            case let c where c.isIdentifierStartByte:
                let tokenStart = TokenPosition(position: tokenPosition, line: tokenLine, column: tokenColumn)
                try tokenizeIdentifier(&tokens, start: tokenStart)

            default:
                throw LexerError.unexpectedCharacter(currentCharacter, position: byteIndex)
            }
        }

        // Check for -}} trim marker before closing
        var trimRight = false
        if byteIndex < end, bytes[byteIndex] == Self.dash {
            trimRight = true
            advanceASCII() // consume -
        }

        // Consume closing }}
        if byteIndex + 1 < end, bytes[byteIndex] == Self.closeBrace, bytes[byteIndex + 1] == Self.closeBrace {
            let endPosition = byteIndex
            let endLine = line
            let endColumn = column
            advanceASCII() // consume first }
            advanceASCII() // consume second }

            context = .text  // Exit variable context
            tokens.append(Token(type: .variableEnd, position: endPosition, line: endLine, column: endColumn, trimRight: trimRight))
        } else {
            throw LexerError.unterminatedString(position: start.position)
        }
    }
    
    private func tokenizeTag(_ tokens: inout [Token], start: TokenPosition) throws(LexerError) {
        advanceASCII() // consume {
        advanceASCII() // consume %

        // Check for whitespace trim marker: {%-
        let trimLeft = byteIndex < bytes.count && bytes[byteIndex] == Self.dash
        if trimLeft {
            advanceASCII() // consume -
        }

        context = .tag  // Enter tag context
        tokens.append(Token(
            type: .tagStart,
            position: start.position,
            line: start.line,
            column: start.column,
            trimLeft: trimLeft
        ))

        // Skip whitespace
        skipWhitespace()

        // Handle inline comments: {% # ... %}
        // If the first non-whitespace character is #, skip everything until %} or -%}
        // Each continuation line must also start with # (enforce leading hash)
        if byteIndex < bytes.count, bytes[byteIndex] == 0x23 { // 0x23 = '#'
            while byteIndex < bytes.count {
                if bytes[byteIndex] == Self.dash,
                   byteIndex + 2 < bytes.count,
                   bytes[byteIndex + 1] == Self.percent,
                   bytes[byteIndex + 2] == Self.closeBrace {
                    break
                }
                if bytes[byteIndex] == Self.percent,
                   byteIndex + 1 < bytes.count,
                   bytes[byteIndex + 1] == Self.closeBrace {
                    break
                }
                // Check for newline — next non-whitespace on new line must be #
                if bytes[byteIndex] == 0x0A { // newline
                    advanceASCII()
                    // Skip leading whitespace on new line
                    while byteIndex < bytes.count, bytes[byteIndex] == 0x20 || bytes[byteIndex] == 0x09 {
                        advanceASCII()
                    }
                    // Check for %} / -%} (end of tag)
                    if byteIndex < bytes.count {
                        if (bytes[byteIndex] == Self.percent && byteIndex + 1 < bytes.count && bytes[byteIndex + 1] == Self.closeBrace) ||
                           (bytes[byteIndex] == Self.dash && byteIndex + 2 < bytes.count && bytes[byteIndex + 1] == Self.percent && bytes[byteIndex + 2] == Self.closeBrace) {
                            break
                        }
                        // Next non-ws character must be #
                        if bytes[byteIndex] != 0x23 {
                            throw LexerError.unexpectedCharacter(Character(UnicodeScalar(bytes[byteIndex])), position: byteIndex)
                        }
                    }
                    continue
                }
                advanceASCII()
            }
            // Emit comment token so parser recognizes it
            tokens.append(Token(
                type: .comment,
                position: start.position,
                line: start.line,
                column: start.column
            ))

            // Check for -%} trim marker
            var trimRight = false
            if byteIndex < bytes.count, bytes[byteIndex] == Self.dash {
                trimRight = true
                advanceASCII()
            }

            // Consume closing %} and emit tag end + synthetic endcomment block
            if byteIndex + 1 < bytes.count,
               bytes[byteIndex] == Self.percent,
               bytes[byteIndex + 1] == Self.closeBrace {
                let endPos = byteIndex
                let endLn = line
                let endCol = column
                advanceASCII()
                advanceASCII()
                context = .text
                tokens.append(Token(type: .tagEnd, position: endPos, line: endLn, column: endCol, trimRight: trimRight))
                // Emit synthetic {% endcomment %} so the parser can treat it as a block comment
                tokens.append(Token(type: .tagStart, position: endPos, line: endLn, column: endCol))
                tokens.append(Token(type: .endcomment, position: endPos, line: endLn, column: endCol))
                tokens.append(Token(type: .tagEnd, position: endPos, line: endLn, column: endCol))
            }
            return
        }

        let end = bytes.count

        // Tokenize the content inside tag
        while byteIndex < end {
            let byte = bytes[byteIndex]
            let nextByte = byteIndex + 1 < end ? bytes[byteIndex + 1] : 0

            if byte == Self.percent, nextByte == Self.closeBrace {
                break
            }

            // Check for -%} whitespace trim marker
            if byte == Self.dash, byteIndex + 2 < end,
               bytes[byteIndex + 1] == Self.percent, bytes[byteIndex + 2] == Self.closeBrace {
                break
            }

            if byte.isWhitespaceByte {
                skipWhitespace()
                continue
            }

            if tokens.count >= 2, tokens.last?.type == .assign,
               tokens[tokens.count - 2].type == .tagStart {
                let nameStart = byteIndex
                while byteIndex < end, !bytes[byteIndex].isWhitespaceByte, bytes[byteIndex] != Self.equals {
                    advance()
                }
                if byteIndex > nameStart {
                    tokens.append(Token(type: .identifier(InlineString(utf8: bytes[nameStart..<byteIndex])), position: nameStart, line: line, column: column))
                    continue
                }
            }

            let tokenPosition = byteIndex
            let tokenLine = line
            let tokenColumn = column

            switch byte {
            case Self.equals:
                if nextByte == Self.equals {
                    advanceASCII()
                    advanceASCII()
                    tokens.append(Token(type: .equals, position: tokenPosition, line: tokenLine, column: tokenColumn))
                } else {
                    // Single = is assignment in tags
                    advanceASCII()
                    tokens.append(Token(type: .equals, position: tokenPosition, line: tokenLine, column: tokenColumn))
                }
                
            case Self.exclamation:
                if nextByte == Self.equals {
                    advanceASCII()
                    advanceASCII()
                    tokens.append(Token(type: .notEquals, position: tokenPosition, line: tokenLine, column: tokenColumn))
                } else {
                    throw LexerError.unexpectedCharacter("!", position: tokenPosition)
                }
                
            case Self.lessThan:
                if nextByte == Self.equals {
                    advanceASCII()
                    advanceASCII()
                    tokens.append(Token(type: .lessThanOrEqual, position: tokenPosition, line: tokenLine, column: tokenColumn))
                } else if nextByte == Self.greaterThan {
                    // <> is alternate not-equal operator
                    advanceASCII()
                    advanceASCII()
                    tokens.append(Token(type: .notEquals, position: tokenPosition, line: tokenLine, column: tokenColumn))
                } else {
                    advanceASCII()
                    tokens.append(Token(type: .lessThan, position: tokenPosition, line: tokenLine, column: tokenColumn))
                }
                
            case Self.greaterThan:
                if nextByte == Self.equals {
                    advanceASCII()
                    advanceASCII()
                    tokens.append(Token(type: .greaterThanOrEqual, position: tokenPosition, line: tokenLine, column: tokenColumn))
                } else {
                    advanceASCII()
                    tokens.append(Token(type: .greaterThan, position: tokenPosition, line: tokenLine, column: tokenColumn))
                }
                
            case Self.dot:
                if nextByte == Self.dot {
                    advanceASCII()
                    advanceASCII()
                    tokens.append(Token(type: .range, position: tokenPosition, line: tokenLine, column: tokenColumn))
                } else {
                    advanceASCII()
                    tokens.append(Token(type: .dot, position: tokenPosition, line: tokenLine, column: tokenColumn))
                }
                
            case Self.pipe:
                advanceASCII()
                filterParentContext = context == .filter ? filterParentContext : context
                context = .filter  // Enter filter context
                tokens.append(Token(type: .filter, position: tokenPosition, line: tokenLine, column: tokenColumn))
                
            case Self.comma:
                advanceASCII()
                // Exit filter context on comma.
                if context == .filter {
                    context = filterParentContext
                }
                tokens.append(Token(type: .comma, position: tokenPosition, line: tokenLine, column: tokenColumn))
                
            case Self.colon:
                advanceASCII()
                tokens.append(Token(type: .colon, position: tokenPosition, line: tokenLine, column: tokenColumn))
                
            case Self.leftParen:
                advanceASCII()
                tokens.append(Token(type: .leftParen, position: tokenPosition, line: tokenLine, column: tokenColumn))
                
            case Self.rightParen:
                advanceASCII()
                tokens.append(Token(type: .rightParen, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.leftBracket:
                advanceASCII()
                tokens.append(Token(type: .leftBracket, position: tokenPosition, line: tokenLine, column: tokenColumn))

            case Self.rightBracket:
                advanceASCII()
                tokens.append(Token(type: .rightBracket, position: tokenPosition, line: tokenLine, column: tokenColumn))
                
            case Self.doubleQuote, Self.singleQuote:
                let tokenStart = TokenPosition(position: tokenPosition, line: tokenLine, column: tokenColumn)
                try tokenizeString(&tokens, start: tokenStart, quote: byte)
                
            case let c where c.isDigitByte:
                let tokenStart = TokenPosition(position: tokenPosition, line: tokenLine, column: tokenColumn)
                try tokenizeNumber(&tokens, start: tokenStart)

            case Self.dash:
                // Negative number literal (-5, -3.14)
                // Note: -%} trim markers are already handled before this switch
                let nextIdx = byteIndex + 1
                if nextIdx < end, bytes[nextIdx].isDigitByte {
                    let isUnary = tokens.isEmpty || {
                        let lastType = tokens.last!.type
                        switch lastType {
                        case .number, .string, .identifier: return false
                        case .rightParen, .rightBracket: return false
                        default: return true
                        }
                    }()
                    if isUnary {
                        let tokenStart = TokenPosition(position: tokenPosition, line: tokenLine, column: tokenColumn)
                        advanceASCII() // consume -
                        try tokenizeNumber(&tokens, start: tokenStart, negative: true)
                    } else {
                        throw LexerError.unexpectedCharacter(currentCharacter, position: byteIndex)
                    }
                } else {
                    // Bare `-` not followed by digit or `%}` — invalid in Liquid
                    throw LexerError.unexpectedCharacter(currentCharacter, position: byteIndex)
                }

            case let c where c.isIdentifierStartByte:
                let tokenStart = TokenPosition(position: tokenPosition, line: tokenLine, column: tokenColumn)
                try tokenizeIdentifier(&tokens, start: tokenStart)

            case 0x23: // '#' — inline comment inside tag, skip to end of line
                while byteIndex < bytes.count {
                    let b = bytes[byteIndex]
                    if b == 0x0A /* \n */ { break } // stop at newline
                    if b == Self.percent, byteIndex + 1 < bytes.count, bytes[byteIndex + 1] == Self.closeBrace { break }
                    if b == Self.dash, byteIndex + 2 < bytes.count, bytes[byteIndex + 1] == Self.percent, bytes[byteIndex + 2] == Self.closeBrace { break }
                    advanceASCII()
                }

            default:
                throw LexerError.unexpectedCharacter(currentCharacter, position: byteIndex)
            }
        }

        // Check for -%} trim marker before closing
        var trimRight = false
        if byteIndex < end, bytes[byteIndex] == Self.dash {
            trimRight = true
            advanceASCII() // consume -
        }

        // Consume closing %}
        if byteIndex + 1 < end, bytes[byteIndex] == Self.percent, bytes[byteIndex + 1] == Self.closeBrace {
            let endPosition = byteIndex
            let endLine = line
            let endColumn = column
            advanceASCII() // consume %
            advanceASCII() // consume }

            context = .text  // Exit tag context
            tokens.append(Token(type: .tagEnd, position: endPosition, line: endLine, column: endColumn, trimRight: trimRight))
        } else {
            throw LexerError.unterminatedString(position: start.position)
        }
    }
    
    private func tokenizeText(_ tokens: inout [Token], start: TokenPosition) throws(LexerError) {
        let contentStart = byteIndex
        let end = bytes.count
        var index = byteIndex
        var currentLine = line
        var currentColumn = column

        while index < end {
            let byte = bytes[index]

            if byte == Self.openBrace {
                let nextIndex = index + 1
                if nextIndex < end {
                    let next = bytes[nextIndex]
                    if next == Self.openBrace || next == Self.percent {
                        break
                    }
                }
            }

            if byte == Self.newline {
                index += 1
                currentLine += 1
                currentColumn = 1
                continue
            }

            if byte < 0x80 {
                let runStart = index
                index += 1

                while index < end {
                    let next = bytes[index]
                    if next == Self.openBrace || next == Self.newline || next >= 0x80 {
                        break
                    }
                    index += 1
                }

                currentColumn += index - runStart
                continue
            }

            index += 1
            if !byte.isUTF8ContinuationByte {
                currentColumn += 1
            }
        }

        byteIndex = index
        line = currentLine
        column = currentColumn
        
        if byteIndex > contentStart {
            tokens.append(Token(
                type: .text(makeInlineString(from: contentStart, to: byteIndex)),
                position: start.position,
                line: start.line,
                column: start.column
            ))
        }
    }
    
    private func tokenizeString(_ tokens: inout [Token], start: TokenPosition, quote: UInt8) throws(LexerError) {
        advance() // consume opening quote
        
        let contentStart = byteIndex
        if let simpleContent = try tokenizeSimpleStringContent(startPosition: start.position, quote: quote) {
            advance() // consume closing quote
            tokens.append(Token(
                type: .string(simpleContent),
                position: start.position,
                line: start.line,
                column: start.column
            ))
            return
        }

        var unescapedSegmentStart = byteIndex
        var contentBuffer: String?
        
        while !isAtEnd && current != quote {
            if current == Self.backslash {
                if contentBuffer == nil {
                    contentBuffer = makeString(from: contentStart, to: byteIndex)
                } else if byteIndex > unescapedSegmentStart {
                    contentBuffer?.append(makeString(from: unescapedSegmentStart, to: byteIndex))
                }
                advance() // consume backslash
                if !isAtEnd {
                    // Handle escape sequences
                    switch current {
                    case 0x6E: contentBuffer?.append("\n")
                    case 0x74: contentBuffer?.append("\t")
                    case 0x72: contentBuffer?.append("\r")
                    case Self.backslash: contentBuffer?.append("\\")
                    case Self.doubleQuote: contentBuffer?.append("\"")
                    case Self.singleQuote: contentBuffer?.append("'")
                    default: 
                        contentBuffer?.append("\\")
                        contentBuffer?.append(currentScalarString())
                    }
                    advance()
                    unescapedSegmentStart = byteIndex
                }
            } else {
                advance()
            }
        }
        
        if isAtEnd {
            throw LexerError.unterminatedString(position: start.position)
        }
        
        let content: InlineString
        if var buffer = contentBuffer {
            if byteIndex > unescapedSegmentStart {
                buffer.append(makeString(from: unescapedSegmentStart, to: byteIndex))
            }
            content = InlineString(buffer)
        } else {
            content = makeInlineString(from: contentStart, to: byteIndex)
        }

        advance() // consume closing quote
        
        tokens.append(Token(
            type: .string(content),
            position: start.position,
            line: start.line,
            column: start.column
        ))
    }

    @inline(__always)
    private func tokenizeSimpleStringContent(startPosition: Int, quote: UInt8) throws(LexerError) -> InlineString? {
        let end = bytes.count
        var index = byteIndex
        var currentLine = line
        var currentColumn = column

        while index < end {
            let byte = bytes[index]

            if byte == quote {
                let content = makeInlineString(from: byteIndex, to: index)
                byteIndex = index
                line = currentLine
                column = currentColumn
                return content
            }

            if byte == Self.backslash {
                return nil
            }

            index += 1
            if byte == Self.newline {
                currentLine += 1
                currentColumn = 1
            } else if !byte.isUTF8ContinuationByte {
                currentColumn += 1
            }
        }

        throw LexerError.unterminatedString(position: startPosition)
    }
    
    private func tokenizeNumber(_ tokens: inout [Token], start: TokenPosition, negative: Bool = false) throws(LexerError) {
        var hasDot = false
        var integerPart: Double = 0
        var fractionalPart: Double = 0
        var divisor: Double = 1

        while !isAtEnd {
            let byte = current

            if byte.isDigitByte {
                let digit = Double(byte - 0x30)
                if hasDot {
                    fractionalPart = (fractionalPart * 10) + digit
                    divisor *= 10
                } else {
                    integerPart = (integerPart * 10) + digit
                }
                advanceASCII()
                continue
            }

            guard byte == Self.dot, !hasDot else {
                break
            }

            // Stop before consuming a range operator.
            if peek() == Self.dot {
                break
            }

            hasDot = true
            advanceASCII()
        }

        var number = hasDot ? integerPart + (fractionalPart / divisor) : integerPart
        if negative { number = -number }
        let spelling = String(decoding: bytes[start.position..<byteIndex], as: UTF8.self)
        guard number.isFinite, hasDot || Int(spelling) != nil else {
            throw LexerError.invalidNumber(spelling, position: start.position)
        }
        
        tokens.append(Token(
            type: .number(number, isFloat: hasDot),
            position: start.position,
            line: start.line,
            column: start.column,
            exactInteger: hasDot ? nil : Int(spelling)
        ))
    }
    
    private func tokenizeIdentifier(_ tokens: inout [Token], start: TokenPosition) throws(LexerError) {
        let identifierStart = byteIndex

        let end = bytes.count
        var index = byteIndex
        var currentColumn = column

        while index < end {
            let byte = bytes[index]
            if byte.isIdentifierContinueByte {
                if !byte.isUTF8ContinuationByte {
                    currentColumn += 1
                }
                index += 1
            } else if byte == 0x2D /* '-' */ && (index + 1) < end && bytes[index + 1].isIdentifierStartByte {
                // Shopify Liquid allows hyphens inside identifiers (e.g. some-thing).
                // Consume the hyphen only when immediately followed by an identifier char,
                // so "x - y" (with spaces) still tokenizes as three separate tokens.
                currentColumn += 1
                index += 1
            } else {
                break
            }
        }

        // Allow trailing '?' for Ruby-style predicate identifiers (e.g., foo?, blank?)
        if index < end && bytes[index] == 0x3F /* '?' */ {
            currentColumn += 1
            index += 1
        }

        byteIndex = index
        column = currentColumn

        let name = makeInlineString(from: identifierStart, to: byteIndex)
        if context == .variable, !name.equals("contains") {
            tokens.append(Token(type: .identifier(name), position: start.position, line: start.line, column: start.column))
            return
        }
        if ["macro", "call", "input", "pipeline", "import", "from", "slot", "fill", "block", "extends", "render_block", "debug", "recursive", "loop"].contains(name.string) {
            tokens.append(Token(type: .identifier(name), position: start.position, line: start.line, column: start.column))
            return
        }

        if let tokenType = commonKeywordTokenType(from: identifierStart, to: byteIndex, context: context) {
            tokens.append(Token(
                type: tokenType,
                position: start.position,
                line: start.line,
                column: start.column
            ))
            return
        }

        let identifier = makeInlineString(from: identifierStart, to: byteIndex)
        
        // Check if it's a keyword, considering context
        let tokenType: TokenType
        
        // In filter context, treat context-sensitive keywords as identifiers
        if context == .filter && isContextSensitiveKeyword(identifier) {
            tokenType = .identifier(identifier)
        } else {
            tokenType = keywordTokenType(for: identifier)
        }
        
        tokens.append(Token(
            type: tokenType,
            position: start.position,
            line: start.line,
            column: start.column
        ))
    }

    @inline(__always)
    private func commonKeywordTokenType(from start: Int, to end: Int, context: LexerContext) -> TokenType? {
        let count = end - start
        guard count >= 2, count <= 9 else {
            return nil
        }

        let first = bytes[start]
        guard first < 0x80 else {
            return nil
        }

        switch count {
        case 2:
            switch first {
            case 0x69:
                if bytes[start + 1] == 0x66 { return .if }
                if bytes[start + 1] == 0x6E { return .in }
                if bytes[start + 1] == 0x73 { return .is }
            case 0x6F:
                if bytes[start + 1] == 0x72 { return .or }
            default:
                break
            }

        case 3:
            switch first {
            case 0x61:
                if bytes[start + 1] == 0x6E, bytes[start + 2] == 0x64 { return .and }
            case 0x66:
                if bytes[start + 1] == 0x6F, bytes[start + 2] == 0x72 { return .for }
            case 0x72:
                if context != .filter,
                   bytes[start + 1] == 0x61,
                   bytes[start + 2] == 0x77 {
                    return .raw
                }
            default:
                break
            }

        case 4:
            switch first {
            case 0x63:
                if bytes[start + 1] == 0x61,
                   bytes[start + 2] == 0x6C,
                   bytes[start + 3] == 0x6C {
                    return .call
                }
            case 0x65:
                if bytes[start + 1] == 0x6C,
                   bytes[start + 2] == 0x73,
                   bytes[start + 3] == 0x65 {
                    return .else
                }
                if bytes[start + 1] == 0x63,
                   bytes[start + 2] == 0x68,
                   bytes[start + 3] == 0x6F {
                    return .echo
                }
            case 0x66:
                if bytes[start + 1] == 0x72,
                   bytes[start + 2] == 0x6F,
                   bytes[start + 3] == 0x6D {
                    return .from
                }
            case 0x77:
                if bytes[start + 1] == 0x68,
                   bytes[start + 2] == 0x65,
                   bytes[start + 3] == 0x6E {
                    return .when
                }
                if bytes[start + 1] == 0x69,
                   bytes[start + 2] == 0x74,
                   bytes[start + 3] == 0x68 {
                    return .with
                }
            default:
                break
            }

        case 5:
            switch first {
            case 0x65:
                if bytes[start + 1] == 0x6C,
                   bytes[start + 2] == 0x73,
                   bytes[start + 3] == 0x69,
                   bytes[start + 4] == 0x66 {
                    return .elsif
                }
                if bytes[start + 1] == 0x6D,
                   bytes[start + 2] == 0x70,
                   bytes[start + 3] == 0x74,
                   bytes[start + 4] == 0x79 {
                    return .empty
                }
                if bytes[start + 1] == 0x6E,
                   bytes[start + 2] == 0x64,
                   bytes[start + 3] == 0x69,
                   bytes[start + 4] == 0x66 {
                    return .endif
                }
            case 0x62:
                if bytes[start + 1] == 0x72,
                   bytes[start + 2] == 0x65,
                   bytes[start + 3] == 0x61,
                   bytes[start + 4] == 0x6B {
                    return .break
                }
                if bytes[start + 1] == 0x6C,
                   bytes[start + 2] == 0x6F,
                   bytes[start + 3] == 0x63,
                   bytes[start + 4] == 0x6B {
                    return .block
                }
            case 0x63:
                if bytes[start + 1] == 0x79,
                   bytes[start + 2] == 0x63,
                   bytes[start + 3] == 0x6C,
                   bytes[start + 4] == 0x65 {
                    return .cycle
                }
            case 0x69:
                if bytes[start + 1] == 0x6E,
                   bytes[start + 2] == 0x70,
                   bytes[start + 3] == 0x75,
                   bytes[start + 4] == 0x74 {
                    return .input
                }
            case 0x6D:
                if bytes[start + 1] == 0x61,
                   bytes[start + 2] == 0x63,
                   bytes[start + 3] == 0x72,
                   bytes[start + 4] == 0x6F {
                    return .macro
                }
            default:
                break
            }

        case 6:
            switch first {
            case 0x61:
                if bytes[start + 1] == 0x73,
                   bytes[start + 2] == 0x73,
                   bytes[start + 3] == 0x69,
                   bytes[start + 4] == 0x67,
                   bytes[start + 5] == 0x6E {
                    return .assign
                }
            case 0x65:
                if bytes[start + 1] == 0x6E,
                   bytes[start + 2] == 0x64,
                   bytes[start + 3] == 0x66,
                   bytes[start + 4] == 0x6F,
                   bytes[start + 5] == 0x72 {
                    return .endfor
                }
                if bytes[start + 1] == 0x6C,
                   bytes[start + 2] == 0x73,
                   bytes[start + 3] == 0x65,
                   bytes[start + 4] == 0x69,
                   bytes[start + 5] == 0x66 {
                    return .elsif
                }
            case 0x69:
                if bytes[start + 1] == 0x6D,
                   bytes[start + 2] == 0x70,
                   bytes[start + 3] == 0x6F,
                   bytes[start + 4] == 0x72,
                   bytes[start + 5] == 0x74 {
                    return .import
                }
            case 0x6C:
                if bytes[start + 1] == 0x69,
                   bytes[start + 2] == 0x71,
                   bytes[start + 3] == 0x75,
                   bytes[start + 4] == 0x69,
                   bytes[start + 5] == 0x64 {
                    return .liquid
                }
            case 0x72:
                if bytes[start + 1] == 0x65,
                   bytes[start + 2] == 0x6E,
                   bytes[start + 3] == 0x64,
                   bytes[start + 4] == 0x65,
                   bytes[start + 5] == 0x72 {
                    return .render
                }
            case 0x75:
                if bytes[start + 1] == 0x6E,
                   bytes[start + 2] == 0x6C,
                   bytes[start + 3] == 0x65,
                   bytes[start + 4] == 0x73,
                   bytes[start + 5] == 0x73 {
                    return .unless
                }
            default:
                break
            }

        case 7:
            switch first {
            case 0x63:
                if bytes[start + 1] == 0x61,
                   bytes[start + 2] == 0x70,
                   bytes[start + 3] == 0x74,
                   bytes[start + 4] == 0x75,
                   bytes[start + 5] == 0x72,
                   bytes[start + 6] == 0x65 {
                    return .capture
                }
                if bytes[start + 1] == 0x6F,
                   bytes[start + 2] == 0x6D,
                   bytes[start + 3] == 0x6D,
                   bytes[start + 4] == 0x65,
                   bytes[start + 5] == 0x6E,
                   bytes[start + 6] == 0x74 {
                    return .comment
                }
            case 0x69:
                if bytes[start + 1] == 0x6E,
                   bytes[start + 2] == 0x63,
                   bytes[start + 3] == 0x6C,
                   bytes[start + 4] == 0x75,
                   bytes[start + 5] == 0x64,
                   bytes[start + 6] == 0x65 {
                    return .include
                }
            default:
                break
            }

        case 8:
            switch first {
            case 0x63:
                if bytes[start + 1] == 0x6F,
                   bytes[start + 2] == 0x6E,
                   bytes[start + 3] == 0x74,
                   bytes[start + 4] == 0x69,
                   bytes[start + 5] == 0x6E,
                   bytes[start + 6] == 0x75,
                   bytes[start + 7] == 0x65 {
                    return .continue
                }
            case 0x65:
                if bytes[start + 1] == 0x6E,
                   bytes[start + 2] == 0x64,
                   bytes[start + 3] == 0x6D,
                   bytes[start + 4] == 0x61,
                   bytes[start + 5] == 0x63,
                   bytes[start + 6] == 0x72,
                   bytes[start + 7] == 0x6F {
                    return .endmacro
                }
            case 0x74:
                if bytes[start + 1] == 0x61,
                   bytes[start + 2] == 0x62,
                   bytes[start + 3] == 0x6C,
                   bytes[start + 4] == 0x65,
                   bytes[start + 5] == 0x72,
                   bytes[start + 6] == 0x6F,
                   bytes[start + 7] == 0x77 {
                    return .tablerow
                }
            default:
                break
            }

        case 9:
            if first == 0x65,
               bytes[start + 1] == 0x6E,
               bytes[start + 2] == 0x64,
               bytes[start + 3] == 0x75,
               bytes[start + 4] == 0x6E,
               bytes[start + 5] == 0x6C,
               bytes[start + 6] == 0x65,
               bytes[start + 7] == 0x73,
               bytes[start + 8] == 0x73 {
                return .endunless
            }

        default:
            break
        }

        return nil
    }
    
    private func isContextSensitiveKeyword(_ identifier: InlineString) -> Bool {
        identifier.equals("raw")
    }
    
    private func keywordTokenType(for identifier: InlineString) -> TokenType {
        guard let firstByte = identifier.firstUTF8Byte else {
            return .identifier(identifier)
        }

        switch identifier.utf8Count {
        case 2:
            switch firstByte {
            case 0x69:
                if identifier.equals("if") { return .if }
                if identifier.equals("in") { return .in }
                if identifier.equals("is") { return .is }
            case 0x6F:
                if identifier.equals("or") { return .or }
            default:
                break
            }

        case 3:
            switch firstByte {
            case 0x61:
                if identifier.equals("and") { return .and }
            case 0x66:
                if identifier.equals("for") { return .for }
            case 0x72:
                if identifier.equals("raw") { return .raw }
            default:
                break
            }

        case 4:
            switch firstByte {
            case 0x63:
                if identifier.equals("call") { return .call }
                if identifier.equals("case") { return .case }
            case 0x65:
                if identifier.equals("echo") { return .echo }
                if identifier.equals("else") { return .else }
            case 0x66:
                if identifier.equals("from") { return .from }
            case 0x77:
                if identifier.equals("when") { return .when }
                if identifier.equals("with") { return .with }
            default:
                break
            }

        case 5:
            switch firstByte {
            case 0x62:
                if identifier.equals("block") { return .block }
                if identifier.equals("break") { return .break }
            case 0x63:
                if identifier.equals("cycle") { return .cycle }
            case 0x65:
                if identifier.equals("elsif") { return .elsif }
                if identifier.equals("empty") { return .empty }
                if identifier.equals("endif") { return .endif }
            case 0x69:
                if identifier.equals("input") { return .input }
            case 0x6D:
                if identifier.equals("macro") { return .macro }
            default:
                break
            }

        case 6:
            switch firstByte {
            case 0x61:
                if identifier.equals("assign") { return .assign }
            case 0x65:
                if identifier.equals("elseif") { return .elsif }
                if identifier.equals("endfor") { return .endfor }
                if identifier.equals("endraw") { return .endraw }
            case 0x69:
                if identifier.equals("import") { return .import }
            case 0x6C:
                if identifier.equals("liquid") { return .liquid }
            case 0x72:
                if identifier.equals("render") { return .render }
            case 0x75:
                if identifier.equals("unless") { return .unless }
            default:
                break
            }

        case 7:
            switch firstByte {
            case 0x63:
                if identifier.equals("capture") { return .capture }
                if identifier.equals("comment") { return .comment }
            case 0x65:
                if identifier.equals("else_if") { return .elsif }
                if identifier.equals("endcase") { return .endcase }
            case 0x69:
                if identifier.equals("include") { return .include }
            default:
                break
            }

        case 8:
            switch firstByte {
            case 0x63:
                if identifier.equals("contains") { return .contains }
                if identifier.equals("continue") { return .continue }
            case 0x65:
                if identifier.equals("endblock") { return .endblock }
                if identifier.equals("endmacro") { return .endmacro }
            case 0x74:
                if identifier.equals("tablerow") { return .tablerow }
            default:
                break
            }

        case 9:
            switch firstByte {
            case 0x64:
                if identifier.equals("decrement") { return .decrement }
            case 0x65:
                if identifier.equals("endliquid") { return .endliquid }
                if identifier.equals("endunless") { return .endunless }
            case 0x69:
                if identifier.equals("increment") { return .increment }
            default:
                break
            }

        case 10:
            if firstByte == 0x65 {
                if identifier.equals("endcapture") { return .endcapture }
                if identifier.equals("endcomment") { return .endcomment }
            }

        case 11:
            if firstByte == 0x65, identifier.equals("endtablerow") {
                return .endtablerow
            }

        case 12:
            if firstByte == 0x72, identifier.equals("render_block") {
                return .render_block
            }

        default:
            break
        }

        return .identifier(identifier)
    }
    
    // MARK: - Utility Methods
    
    @inline(__always)
    private var current: UInt8 {
        guard byteIndex < bytes.count else { return 0 }
        return bytes[byteIndex]
    }
    
    @inline(__always)
    private var currentCharacter: Character {
        Character(currentScalarString())
    }
    
    @inline(__always)
    private func peek() -> UInt8? {
        let nextPos = byteIndex + 1
        guard nextPos < bytes.count else { return nil }
        return bytes[nextPos]
    }
    
    @inline(__always)
    private var isAtEnd: Bool {
        return byteIndex >= bytes.count
    }
    
    @inline(__always)
    private var currentPosition: TokenPosition {
        return TokenPosition(position: byteIndex, line: line, column: column)
    }
    
    @discardableResult
    @inline(__always)
    private func advance() -> UInt8 {
        let char = current
        byteIndex += 1
        
        if char == Self.newline {
            line += 1
            column = 1
        } else if !char.isUTF8ContinuationByte {
            column += 1
        }
        
        return char
    }

    @inline(__always)
    private func advanceASCII() {
        byteIndex += 1
        column += 1
    }
    
    @inline(__always)
    private func skipWhitespace() {
        let end = bytes.count
        var index = byteIndex
        var currentLine = line
        var currentColumn = column

        while index < end {
            switch bytes[index] {
            case 0x09, 0x0D, 0x20:
                let runStart = index
                index += 1

                while index < end {
                    let next = bytes[index]
                    guard next == 0x09 || next == 0x0D || next == 0x20 else {
                        break
                    }
                    index += 1
                }

                currentColumn += index - runStart
            case Self.newline:
                index += 1
                currentLine += 1
                currentColumn = 1
            default:
                byteIndex = index
                line = currentLine
                column = currentColumn
                return
            }
        }

        byteIndex = index
        line = currentLine
        column = currentColumn
    }
    
    @inline(__always)
    private func makeString(from start: Int, to end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    @inline(__always)
    private func makeInlineString(from start: Int, to end: Int) -> InlineString {
        InlineString(utf8: bytes[start..<end])
    }

    @inline(__always)
    private func currentScalarString() -> String {
        let width = utf8ScalarWidth(for: current)
        let end = min(bytes.count, byteIndex + width)
        return makeString(from: byteIndex, to: end)
    }

    @inline(__always)
    private func utf8ScalarWidth(for byte: UInt8) -> Int {
        switch byte {
        case 0x00...0x7F:
            return 1
        case 0xC0...0xDF:
            return 2
        case 0xE0...0xEF:
            return 3
        case 0xF0...0xF7:
            return 4
        default:
            return 1
        }
    }

}

// MARK: - Supporting Types

private struct TokenPosition {
    let position: Int
    let line: Int
    let column: Int
}

private extension UInt8 {
    @inline(__always)
    var isWhitespaceByte: Bool {
        switch self {
        case 0x09, 0x0A, 0x0D, 0x20:
            return true
        default:
            return false
        }
    }

    @inline(__always)
    var isDigitByte: Bool {
        switch self {
        case 0x30...0x39:
            return true
        default:
            return false
        }
    }

    @inline(__always)
    var isIdentifierStartByte: Bool {
        switch self {
        case 0x41...0x5A, 0x61...0x7A, 0x5F, 0x80...0xFF:
            return true
        default:
            return false
        }
    }

    @inline(__always)
    var isIdentifierContinueByte: Bool {
        isIdentifierStartByte || isDigitByte
    }

    @inline(__always)
    var isUTF8ContinuationByte: Bool {
        (self & 0b1100_0000) == 0b1000_0000
    }
}

// MARK: - String Whitespace Trimming Helpers

extension String {
    func trailingWhitespaceTrimmed() -> String {
        var end = endIndex
        while end > startIndex {
            let prev = index(before: end)
            if self[prev].isWhitespace || self[prev].isNewline {
                end = prev
            } else {
                break
            }
        }
        return String(self[startIndex ..< end])
    }

    func leadingWhitespaceTrimmed() -> String {
        var start = startIndex
        while start < endIndex {
            if self[start].isWhitespace || self[start].isNewline {
                start = index(after: start)
            } else {
                break
            }
        }
        return String(self[start ..< endIndex])
    }
}
