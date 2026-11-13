// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  Parser.swift
//  LiquidParser
//
//

import Foundation

internal final class Parser {
    private static let eofToken = Token(
        type: .text(InlineString()),
        position: 0,
        line: 0,
        column: 0
    )

    // MARK: - Properties
    
    private let tokens: [Token]

    private let source: String?
    private let sourceProvenance: DiagnosticSourceProvenance
    private let liquidBody: Bool
    private let syntaxMode: LiquidSyntaxMode
    private let extensionProfile: LiquidExtensionProfile
    private let lineOffset: Int
    private let maxNestingDepth: Int
    private var parseDepth = 0

    private var hasOriginalSource: Bool {
        if case .original = sourceProvenance { return true }
        return false
    }

    
    private var current: Int = 0

    private var currentTokenStorage: Token

    private var nextTokenStorage: Token




    
    // MARK: - Initialization
    
    internal init(
        consuming tokens: [Token],
        source: String? = nil,
        sourceProvenance: DiagnosticSourceProvenance = .unmapped,
        liquidBody: Bool = false,
        syntaxMode: LiquidSyntaxMode = .lax,
        extensionProfile: LiquidExtensionProfile = .standard,
        maxNestingDepth: Int = 64,
        lineOffset: Int = 0
    ) {
        self.tokens = tokens
        self.source = source
        self.sourceProvenance = sourceProvenance
        self.liquidBody = liquidBody
        self.syntaxMode = syntaxMode
        self.extensionProfile = extensionProfile
        self.lineOffset = lineOffset
        self.maxNestingDepth = maxNestingDepth
        self.currentTokenStorage = tokens.first ?? Self.eofToken
        self.nextTokenStorage = tokens.count > 1 ? tokens[1] : Self.eofToken
    }
    
    // MARK: - Public Interface
    
    internal func parse() throws ->ASTNode {
        current = 0
        refreshLookahead()
        var nodes: [ASTNode] = []
        nodes.reserveCapacity(max(4, tokens.count / 3))
        
        do {
            while !isAtEnd {
                let node = try parseNode()
                nodes.append(node)
            }
            return .template(nodes)
        } catch let error as ParserError {
            // Presentation follows the existing first rejection, without another
            // parse or cursor advance. A nested rewritten parser marks its gap;
            // the outer parser must not attach an unrelated original frame.
            guard case .expectedToken(let expected, let got, nil) = error else { throw error }
            let origin = try expectedTokenOrigin(got)
            throw ParserError.expectedToken(expected, got: got, origin: origin)
        }
    }
    
    // Error-only producer selection. Token boundaries come from the existing
    // lexer; the byte owner validates candidate spans and typed reason spelling.
    // Successful parses neither copy nor scan original diagnostic bytes.
    private func expectedTokenOrigin(_ got: TokenType) throws -> DiagnosticOriginResolution {
        try Task.checkCancellation()
        guard case .original(let identity) = sourceProvenance, let source else {
            return .unmapped(.unspecifiedOrRewrittenSource)
        }
        guard current < tokens.count, currentToken.type == got else {
            return .unmapped(.incompleteOrAmbiguousConstruct)
        }
        var openingIndex = current
        while !tokens[openingIndex].isOpeningDelimiter {
            if openingIndex & 255 == 0 { try Task.checkCancellation() }
            if openingIndex == 0 || (openingIndex != current && tokens[openingIndex].isClosingDelimiter) {
                return .unmapped(.incompleteOrAmbiguousConstruct)
            }
            openingIndex -= 1
        }
        let opening = tokens[openingIndex]
        let variable = opening.type == .variableStart
        let closingType: TokenType = variable ? .variableEnd : .tagEnd
        var closingIndex = current
        while closingIndex < tokens.count && tokens[closingIndex].type != closingType {
            if closingIndex & 255 == 0 { try Task.checkCancellation() }
            if tokens[closingIndex].isOpeningDelimiter { return .unmapped(.incompleteOrAmbiguousConstruct) }
            closingIndex += 1
        }
        guard closingIndex < tokens.count else { return .unmapped(.incompleteOrAmbiguousConstruct) }
        let closing = tokens[closingIndex]
        let bytes = Array(source.utf8)
        let start = opening.position
        guard bytes.count >= 2, start >= 0, start <= bytes.count - 2,
              bytes[start] == 123, bytes[start + 1] == (variable ? 123 : 37),
              closing.position >= start + 2, closing.position <= bytes.count - 2 else {
            return .unmapped(.invalidBoundary)
        }
        // Pinned Ruby's first terminator/brace transitions may disagree with
        // native quoted-token boundaries. Such frames stay explicitly unmapped.
        var end = start + 2
        while end < bytes.count - 1 {
            if end & 255 == 0 { try Task.checkCancellation() }
            if bytes[end] == (variable ? 125 : 37) && bytes[end + 1] == 125 { break }
            if variable && (bytes[end] == 125 || (bytes[end] == 123 && bytes[end + 1] == 37)) {
                return .unmapped(.incompleteOrAmbiguousConstruct)
            }
            end += 1
        }
        guard end == closing.position else { return .unmapped(.incompleteOrAmbiguousConstruct) }
        var lower = start + 2
        var upper = end
        if opening.trimLeft {
            guard lower < upper && bytes[lower] == 45 else { return .unmapped(.invalidBoundary) }
            lower += 1
        }
        if closing.trimRight {
            guard upper > lower && bytes[upper - 1] == 45 else { return .unmapped(.invalidBoundary) }
            upper -= 1
        }
        var anchor = start
        var presentation = DiagnosticContextPresentation.outputMarkup
        var header: Range<Int>?
        var headerSpelling: String?
        if !variable {
            guard openingIndex + 1 < closingIndex else { return .unmapped(.incompleteOrAmbiguousConstruct) }
            let name = tokens[openingIndex + 1]
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
            while lower < upper && (bytes[lower] == 32 || (9...13).contains(bytes[lower])) {
                if lower & 255 == 0 { try Task.checkCancellation() }
                lower += 1
            }
            anchor = lower
            if name.type != .echo {
                presentation = name.type == .when ? .reasonOnly : .markup
                while lower < upper && (bytes[lower] == 0 || bytes[lower] == 32 || (9...13).contains(bytes[lower])) {
                    if lower & 255 == 0 { try Task.checkCancellation() }
                    lower += 1
                }
                while upper > lower && (bytes[upper - 1] == 0 || bytes[upper - 1] == 32 || (9...13).contains(bytes[upper - 1])) {
                    if upper & 255 == 0 { try Task.checkCancellation() }
                    upper -= 1
                }
            }
        }
        let spelling: String
        switch got {
        case .identifier(let value): spelling = value.string
        case .variableEnd, .tagEnd, .leftParen, .rightParen, .leftBracket, .rightBracket,
             .colon, .comma, .dot, .range, .filter:
            spelling = got.sourceLexeme
        default: return .unmapped(.reasonDoesNotMatchOriginalToken)
        }
        let frame = DiagnosticSourceFrame(construct: start..<(end + 2), markup: lower..<upper,
            anchor: anchor, presentation: presentation, header: header, headerSpelling: headerSpelling)
        return try DiagnosticSourceSnapshot(admittedUTF8: bytes, identity: identity)
            .expectedToken(spelling, at: currentToken.position, frame: frame, atMarkupEnd: current == closingIndex)
    }

    // MARK: - Node Parsing
    
    @inline(__always)
    private func parseNode() throws ->ASTNode {
        try Task.checkCancellation()
        guard parseDepth < maxNestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
        parseDepth += 1
        defer { parseDepth -= 1 }
        switch currentTokenStorage.type {
        case .text(let content):
            advance()
            return .text(content)
            
        case .variableStart:
            return try parseVariable()
            
        case .tagStart:
            return try parseTag()
            
        default:
            throw ParserError.unexpectedToken(currentToken)
        }
    }
    
    @inline(__always)
    private func parseVariable() throws ->ASTNode {
        let line = currentToken.line + lineOffset
        advance() // consume {{
        if currentTokenStorage.type == .variableEnd {
            advance()
            return .output(.literal(.null), location: .init(line: line, suppressErrorText: false, hasOriginalSource: hasOriginalSource))
        }
        
        let expression = try parseExpression()

        // Ruby's lax variable parser retains a leading expression when one
        // further non-filter token immediately precedes the closing delimiter.
        let hasFilters: Bool
        if case .filtered = expression { hasFilters = true } else { hasFilters = false }
        if syntaxMode == .lax, !hasFilters, nextTokenStorage.type == .variableEnd {
            switch currentToken.type {
            case .identifier, .number, .string, .equals:
                advance()
            default: break
            }
        }
        if syntaxMode == .lax, hasFilters, currentToken.type == .rightParen,
           nextTokenStorage.type == .variableEnd {
            advance()
        }
        
        guard currentTokenStorage.type == .variableEnd else {
            if let error = trailingTokenError(currentToken) { throw error }
            throw ParserError.unexpectedToken(currentToken)
        }
        advance() // consume }}
        
        return .output(expression, location: .init(line: line, suppressErrorText: false, hasOriginalSource: hasOriginalSource))
    }
    
    @inline(__always)
    private func parseTag() throws ->ASTNode {
        advance() // consume {%

        let tagToken = currentTokenStorage
        advance()

        if liquidBody {
            let delimiter: String?
            switch tagToken.type {
            case .endif: delimiter = "endif"
            case .endunless: delimiter = "endunless"
            case .endcase: delimiter = "endcase"
            case .endfor: delimiter = "endfor"
            case .endtablerow: delimiter = "endtablerow"
            case .endcapture: delimiter = "endcapture"
            default: delimiter = nil
            }
            if let delimiter {
                throw LiquidError.syntax(message: "'\(delimiter)' is not a valid delimiter for liquid tags. use %}", line: nil, column: nil)
            }
        }

        switch tagToken.type {
        case .if:
            return try parseIfTag()
        case .unless:
            return try parseUnlessTag()
        case .case:
            return try parseCaseTag()
        case .for:
            return try parseForTag()
        case .tablerow:
            return try parseTableRowTag()
        case .assign:
            return try parseAssignTag()
        case .capture:
            return try parseCaptureTag()





        case .increment:
            return try parseIncrementTag()
        case .decrement:
            return try parseDecrementTag()
        case .break:
            return try parseBreakTag()
        case .continue:
            return try parseContinueTag()
        case .echo:
            return try parseEchoTag()

        case .comment:
            return try parseCommentTag()
        case .raw:
            return try parseRawTag()
        case .liquid:
            return try parseLiquidTag()

        case .cycle:
            return try parseCycleTag()
        case .include:
            return try parseIncludeTag()
        case .render:
            return try parseRenderTag()


        case .identifier(let name):
            return try parseIdentifierTag(named: name)
        case .elsif, .endraw, .endcomment:
            let name: String
            switch tagToken.type {
            case .elsif: name = "elsif"
            case .endraw: name = "endraw"
            default: name = "endcomment"
            }
            throw LiquidError.syntax(message: "Unknown tag '\(name)'", line: tagToken.line + lineOffset, column: tagToken.column)
        default:
            throw ParserError.unexpectedToken(tagToken)
        }
    }

    @inline(__always)
    private func parseIdentifierTag(named name: InlineString) throws ->ASTNode {
        if name.equals("doc") {
            if syntaxMode == .strict2, currentToken.type != .tagEnd, let opening = originalBlockOpening() {
                throw ParserError.invalidBlockMarkup("doc", opening: opening)
            }
            try consumeTagEnd(presentComparison: false)
            guard currentTagMatchesIdentifier("enddoc") else { throw ParserError.unclosedTag("doc") }
            advance(); advance(); try consumeTagEnd()
            return .comment
        }
        if name.equals("ifchanged") {
            return try parseNestedBlocks(initial: .ifChanged)
        }

        if name.equals("if") {
            return try parseIfTag()
        }
        if name.equals("unless") {
            return try parseUnlessTag()
        }
        if name.equals("case") {
            return try parseCaseTag()
        }
        if name.equals("for") {
            return try parseForTag()
        }
        if name.equals("tablerow") {
            return try parseTableRowTag()
        }
        if name.equals("assign") {
            return try parseAssignTag()
        }
        if name.equals("capture") {
            return try parseCaptureTag()
        }







        if name.equals("increment") {
            return try parseIncrementTag()
        }
        if name.equals("decrement") {
            return try parseDecrementTag()
        }
        if name.equals("break") {
            return try parseBreakTag()
        }
        if name.equals("continue") {
            return try parseContinueTag()
        }
        if name.equals("echo") {
            return try parseEchoTag()
        }

        if name.equals("comment") {
            return try parseCommentTag()
        }
        if name.equals("raw") {
            return try parseRawTag()
        }
        if name.equals("liquid") {
            return try parseLiquidTag()
        }

        if name.equals("cycle") {
            return try parseCycleTag()
        }
        if name.equals("include") {
            return try parseIncludeTag()
        }
        if name.equals("render") {
            return try parseRenderTag()
        }




        throw ParserError.unknownTag(name.string)
    }


    
    // MARK: - Simple Tag Parsing
    
    private func parseAssignTag() throws ->ASTNode {
        let line = currentToken.line + lineOffset
        if liquidBody, currentToken.type == .tagEnd {
            throw LiquidError.syntax(message: "Syntax Error in 'assign' - Valid syntax: assign [var] = [source]", line: nil, column: nil)
        }
        if syntaxMode == .strict2 {
            if case .identifier(let name) = currentToken.type, name.string.first?.isNumber == true {
                if name.string.utf8.allSatisfy({ (48...57).contains($0) }) {
                    throw ParserError.expectedIdentifierBeforeNumber(currentToken)
                }
                throw ParserError.expectedIdentifier
            }
            if case .number = currentToken.type { throw identifierExpected(currentToken) }
            if currentToken.type == .equals { throw ParserError.invalidAssignmentTargetAt(currentToken) }
        }
        let variableName: InlineString
        if case .identifier(let name) = currentToken.type {
            // Trailing '?' is not allowed in assignment targets (Shopify behavior)
            if name.string.hasSuffix("?") {
                if syntaxMode == .strict2 && name.string == "?" {
                    throw ParserError.invalidAssignmentTargetAt(currentToken)
                }
                throw ParserError.unexpectedToken(currentToken)
            }
            variableName = name
        } else if case .number(let num, _) = currentToken.type {
            // Digit-only variable names: {% assign 123 = 'hello' %}
            variableName = InlineString(String(Int(num)))
        } else {
            throw ParserError.unexpectedToken(currentToken)
        }
        let admittedName = try admittedAssignmentTarget(variableName)
        advance()

        if syntaxMode == .strict2, currentToken.type == .equals, isOriginalComparison(currentToken),
           nextTokenStorage.type == .equals, !isOriginalComparison(nextTokenStorage) {
            throw LiquidError.syntax(message: "Unexpected character =", line: currentToken.line + lineOffset, column: currentToken.column)
        }
        guard currentToken.type == .equals else {
            if liquidBody, currentToken.type == .tagEnd {
                throw LiquidError.syntax(message: "Syntax Error in 'assign' - Valid syntax: assign [var] = [source]", line: nil, column: nil)
            }
            if syntaxMode == .strict2, case .number = currentToken.type {
                throw identifierExpected(currentToken)
            }
            if syntaxMode == .strict2, nextTokenStorage.type == .equals,
               !isOriginalComparison(nextTokenStorage) {
                switch currentToken.type {
                case .rightBracket, .leftBracket, .dash, .dot:
                    let kind: String
                    switch currentToken.type {
                    case .rightBracket: kind = "close_square"
                    case .leftBracket: kind = "open_square"
                    case .dash: kind = "dash"
                    default: kind = "dot"
                    }
                    throw LiquidError.syntax(message: "Expected id but found \(kind)", line: currentToken.line + lineOffset, column: currentToken.column)
                case .rightParen, .colon, .comma, .leftParen, .filter, .question, .string:
                    throw ParserError.invalidAssignmentTargetAt(currentToken)
                default: break
                }
            }
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        if syntaxMode == .strict2, currentToken.type == .equals,
           !isOriginalComparison(currentToken), nextTokenStorage.type == .tagEnd {
            throw LiquidError.syntax(message: "Unexpected character =", line: currentToken.line + lineOffset, column: currentToken.column)
        }
        
        let value = try parseExpression()
        let hasFilters: Bool
        if case .filtered = value { hasFilters = true } else { hasFilters = false }
        if syntaxMode == .lax, !hasFilters, nextTokenStorage.type == .tagEnd {
            switch currentToken.type {
            case .identifier, .number, .string, .equals, .lessThan, .greaterThan:
                advance()
            default: break
            }
        }
        try consumeTagEnd()
        
        return .assign(variable: admittedName, value: value, location: .init(line: line, suppressErrorText: syntaxMode != .strict2, hasOriginalSource: hasOriginalSource))
    }
    
    /// Pinned Assign::Syntax is unanchored: only its final matching signature
    /// before `=` becomes the target. Match that small precheck in linear time;
    /// do not rewrite source bytes or relax the expression parser.
    private func admittedAssignmentTarget(_ raw: InlineString) throws -> InlineString {
        let bytes = Array(raw.string.utf8)
        func signatureByte(_ byte: UInt8) -> Bool {
            (65...90).contains(byte) || (97...122).contains(byte) ||
                (48...57).contains(byte) || byte == 95 || byte == 45 ||
                byte == 46 || byte == 91 || byte == 93
        }
        // VariableSignature is \(?[\w\-\.\[\]]\)?; Ruby's \w is ASCII.
        // Reverse matching has no regex backtracking, even for hostile targets.
        var start = bytes.count
        var steps = 0
        while start > 0 {
            if steps & 255 == 0 { try Task.checkCancellation() }
            steps += 1
            var cursor = start
            if bytes[cursor - 1] == 41 { cursor -= 1 }
            guard cursor > 0, signatureByte(bytes[cursor - 1]) else { break }
            cursor -= 1
            if cursor > 0, bytes[cursor - 1] == 40 { cursor -= 1 }
            start = cursor
        }
        guard start < bytes.count else { throw ParserError.invalidAssignmentTarget }
        if syntaxMode == .strict2 {
            let first = bytes[start]
            guard (65...90).contains(first) || (97...122).contains(first) || first == 95 else {
                throw ParserError.expectedIdentifier
            }
            for index in start..<bytes.count {
                if index & 255 == 0 { try Task.checkCancellation() }
                let byte = bytes[index]
                guard signatureByte(byte), byte != 46, byte != 91, byte != 93 else {
                    throw ParserError.invalidAssignmentTarget
                }
            }
        }
        return InlineString(utf8: bytes[start...])
    }

    private func parseEchoTag() throws ->ASTNode {
        let line = currentToken.line + lineOffset
        // Empty echo: {% echo %} outputs nothing
        if currentToken.type == .tagEnd {
            try consumeTagEnd()
            return .echo(expression: .literal(.string(InlineString(""))))
        }
        let expression = try parseExpression()
        try consumeTagEnd()

        return .echo(expression: expression, location: .init(line: line, suppressErrorText: false, hasOriginalSource: hasOriginalSource))
    }
    
    // Called immediately after the parser consumes an original tag header.
    private func originalBlockOpening() -> Token? {
        guard case .original = sourceProvenance, current >= 2,
              tokens[current - 2].type == .tagStart else { return nil }
        return tokens[current - 2]
    }

    private func parseCommentTag() throws ->ASTNode {
        let opening = originalBlockOpening()
        while !isAtEnd && currentToken.type != .tagEnd { advance() }
        try consumeTagEnd()

        // Track nesting depth for nested comment blocks
        var depth = 1
        while !isAtEnd && depth > 0 {
            if currentTagMatches(.comment, identifier: "comment") {
                // Nested comment opening
                advance() // consume {%
                advance() // consume 'comment'
                if currentToken.type == .tagEnd { advance() } // consume %}
                depth += 1
            } else if currentTagMatches(.endcomment, identifier: "endcomment") {
                depth -= 1
                if depth == 0 {
                    break // Don't consume — let the code below do it
                }
                advance() // consume {%
                advance() // consume 'endcomment'
                if currentToken.type == .tagEnd { advance() } // consume %}
            } else {
                advance()
            }
        }

        // Consume final endcomment
        guard currentTagMatches(.endcomment, identifier: "endcomment") else {
            if syntaxMode == .strict2, let opening { throw ParserError.unclosedShopifyBlock("comment", opening: opening) }
            throw ParserError.unexpectedToken(currentToken)
        }
        advance() // consume {%
        try consumeTagKeyword(.endcomment, identifier: "endcomment")
        try consumeTagEnd()

        return .comment
    }














    
    // MARK: - Control Flow Tag Parsing
    
    private enum BlockStart { case conditional, unless, loop, table, capture, caseBlock, ifChanged }

    private func parseIfTag() throws ->ASTNode { try parseNestedBlocks(initial: .conditional) }
    private func parseUnlessTag() throws ->ASTNode { try parseNestedBlocks(initial: .unless) }

    private func parseNestedBlocks(initial: BlockStart) throws -> ASTNode {
        // Conditional and loop nesting is represented by explicit frames,
        // including mixed nesting, so source depth does not consume the native stack.
        struct Frame {
            let kind: BlockStart
            let opening: Token?
            var condition: LiquidExpression? = nil
            var location: RenderLocation? = nil
            var variable: InlineString? = nil
            var collection: LiquidExpression? = nil
            var params: ForParams? = nil
            var tableParams: TableRowParams? = nil
            var caseBranches: [CaseBranch] = []
            var caseValues: [LiquidExpression] = []
            var casePhase = 0 // 0: before a branch, 1: when, 2: else
            var thenNodes: [ASTNode] = []
            var elsifBranches: [(LiquidExpression, [ASTNode])] = []
            var elseNodes: [ASTNode]? = nil
            var activeElsif: LiquidExpression? = nil
            var activeElsifNodes: [ASTNode] = []
            var inDiscardedBranch = false
        }

        let entryDepth = parseDepth
        defer { parseDepth = entryDepth }
        func beginFrame(_ kind: BlockStart) throws -> Frame {
            let opening = originalBlockOpening()
            if case .loop = kind {
                let (variable, collection, params) = try parseForHeader()
                return Frame(kind: kind, opening: opening, variable: variable, collection: collection, params: params)
            }
            if case .table = kind {
                let (variable, collection, params) = try parseTableRowHeader()
                return Frame(kind: kind, opening: opening, variable: variable, collection: collection, tableParams: params)
            }
            if case .capture = kind {
                return Frame(kind: kind, opening: opening, variable: try parseCaptureHeader())
            }
            if case .ifChanged = kind {
                try consumeTagEnd()
                return Frame(kind: kind, opening: opening)
            }
            if case .caseBlock = kind {
                let expression = try parseCaseOperand()
                if syntaxMode != .strict2 {
                    while !isAtEnd && currentToken.type != .tagEnd {
                        try Task.checkCancellation()
                        advance()
                    }
                }
                try consumeTagEnd()
                return Frame(kind: kind, opening: opening, condition: expression)
            }
            let location = RenderLocation(line: tokens[current - 1].line + lineOffset, suppressErrorText: syntaxMode != .strict2, hasOriginalSource: hasOriginalSource)
            let condition = try parseComplexExpression()
            try consumeTagEnd()
            return Frame(kind: kind, opening: opening, condition: condition, location: location)
        }
        var frames = [try beginFrame(initial)]
        func finishElsif(_ index: Int) {
            if let condition = frames[index].activeElsif {
                frames[index].elsifBranches.append((condition, frames[index].activeElsifNodes))
                frames[index].activeElsif = nil
                frames[index].activeElsifNodes = []
            }
        }
        func append(_ node: ASTNode, to index: Int) {
            if frames[index].inDiscardedBranch { return }
            if frames[index].kind == .caseBlock {
                frames[index].thenNodes.append(node)
                return
            }
            if frames[index].elseNodes != nil { frames[index].elseNodes!.append(node) }
            else if frames[index].activeElsif != nil { frames[index].activeElsifNodes.append(node) }
            else { frames[index].thenNodes.append(node) }
        }
        func finishCaseBranch(_ index: Int) {
            if frames[index].casePhase == 1 {
                for value in frames[index].caseValues {
                    frames[index].caseBranches.append(.when(value, frames[index].thenNodes))
                }
            } else if frames[index].casePhase == 2 {
                frames[index].caseBranches.append(.otherwise(frames[index].thenNodes))
            }
            frames[index].thenNodes = []
            frames[index].caseValues = []
            frames[index].casePhase = 0
        }

        while !isAtEnd {
            try Task.checkCancellation()
            let index = frames.count - 1
            let nested: (BlockStart, TokenType, StaticString)?
            if frames[index].kind == .caseBlock && frames[index].casePhase == 0 { nested = nil }
            else if currentTagMatches(.if, identifier: "if") { nested = (.conditional, .if, "if") }
            else if currentTagMatches(.unless, identifier: "unless") { nested = (.unless, .unless, "unless") }
            else if currentTagMatches(.for, identifier: "for") { nested = (.loop, .for, "for") }
            else if currentTagMatches(.tablerow, identifier: "tablerow") { nested = (.table, .tablerow, "tablerow") }
            else if currentTagMatches(.capture, identifier: "capture") { nested = (.capture, .capture, "capture") }
            else if currentTagMatches(.case, identifier: "case") { nested = (.caseBlock, .case, "case") }
            else if currentTagMatchesIdentifier("ifchanged") { nested = (.ifChanged, .identifier(InlineString("ifchanged")), "ifchanged") }
            else { nested = nil }
            if let (kind, keyword, spelling) = nested {
                guard parseDepth < maxNestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
                parseDepth += 1
                advance()
                try consumeTagKeyword(keyword, identifier: spelling)
                frames.append(try beginFrame(kind))
                continue
            }
            if frames[index].kind == .caseBlock && currentTagMatches(.when, identifier: "when") {
                finishCaseBranch(index)
                frames[index].caseValues = try parseCaseWhenHeader()
                frames[index].casePhase = 1
            } else if frames[index].kind == .caseBlock && currentTagMatches(.else, identifier: "else") {
                finishCaseBranch(index)
                advance()
                try consumeTagKeyword(.else, identifier: "else")
                try consumeTagEnd()
                frames[index].casePhase = 2
            } else if currentTagMatches(.elsif, identifier: "elsif"),
               frames[index].kind == .conditional || frames[index].kind == .unless {
                advance()
                try consumeTagKeyword(.elsif, identifier: "elsif")
                if frames[index].elseNodes != nil || frames[index].inDiscardedBranch {
                    frames[index].inDiscardedBranch = true
                    while currentToken.type != .tagEnd && !isAtEnd { advance() }
                    try consumeTagEnd()
                } else {
                    finishElsif(index)
                    frames[index].activeElsif = try parseComplexExpression()
                    try consumeTagEnd()
                }
            } else if currentTagMatches(.else, identifier: "else"),
                      frames[index].kind == .conditional || frames[index].kind == .unless || frames[index].kind == .loop {
                if frames[index].kind == .loop && frames[index].elseNodes != nil {
                    _ = try parseNode() // Preserve the original unexpected-tag rejection.
                    continue
                }
                advance()
                try consumeTagKeyword(.else, identifier: "else")
                if frames[index].kind != .loop {
                    while currentToken.type != .tagEnd && !isAtEnd { advance() }
                }
                try consumeTagEnd()
                if frames[index].elseNodes != nil || frames[index].inDiscardedBranch {
                    frames[index].inDiscardedBranch = true
                } else {
                    finishElsif(index)
                    frames[index].elseNodes = []
                }
            } else {
                let end: (TokenType, StaticString)
                switch frames[index].kind {
                case .conditional: end = (.endif, "endif")
                case .unless: end = (.endunless, "endunless")
                case .loop: end = (.endfor, "endfor")
                case .table: end = (.endtablerow, "endtablerow")
                case .capture: end = (.endcapture, "endcapture")
                case .caseBlock: end = (.endcase, "endcase")
                case .ifChanged: end = (.identifier(InlineString("endifchanged")), "endifchanged")
                }
                if currentTagMatches(end.0, identifier: end.1) {
                    finishElsif(index)
                    if frames[index].kind == .caseBlock { finishCaseBranch(index) }
                    advance()
                    try consumeTagKeyword(end.0, identifier: end.1)
                    try consumeTagEnd()
                    let frame = frames.removeLast()
                    let node: ASTNode
                    switch frame.kind {
                    case .conditional:
                        node = .if(condition: frame.condition!, then: frame.thenNodes, elsif: frame.elsifBranches, else: frame.elseNodes, location: frame.location!)
                    case .unless:
                        if frame.elsifBranches.isEmpty {
                            node = .unless(condition: frame.condition!, then: frame.thenNodes, else: frame.elseNodes, location: frame.location!)
                        } else {
                            node = .if(condition: .unary(op: .not, expr: frame.condition!), then: frame.thenNodes, elsif: frame.elsifBranches, else: frame.elseNodes, location: frame.location!)
                        }
                    case .loop:
                        node = .for(variable: frame.variable!, in: frame.collection!, body: frame.thenNodes, empty: frame.elseNodes, params: frame.params!)
                    case .table:
                        node = .tablerow(variable: frame.variable!, in: frame.collection!, body: frame.thenNodes, params: frame.tableParams!)
                    case .capture:
                        node = .capture(variable: frame.variable!, body: frame.thenNodes)
                    case .caseBlock:
                        node = .case(value: frame.condition!, branches: frame.caseBranches)
                    case .ifChanged:
                        node = .ifchanged(frame.thenNodes)
                    }
                    if frames.isEmpty { return node }
                    parseDepth -= 1
                    append(node, to: frames.count - 1)
                } else {
                    if frames[index].kind == .caseBlock && frames[index].casePhase == 0 {
                        if currentTagMatches(.elsif, identifier: "elsif") {
                            throw LiquidError.syntax(message: "Unknown tag 'elsif'", line: nextTokenStorage.line + lineOffset, column: nextTokenStorage.column)
                        }
                        advance()
                        continue
                    }
                    let node = try parseNode()
                    append(node, to: index)
                }
            }
        }
        if let frame = frames.last, frame.opening != nil || liquidBody {
            let tag: String
            switch frame.kind {
            case .conditional: tag = "if"
            case .unless: tag = "unless"
            case .loop: tag = "for"
            case .table: tag = "tablerow"
            case .capture: tag = "capture"
            case .caseBlock: tag = "case"
            case .ifChanged: tag = "ifchanged"
            }
            if let opening = frame.opening { throw ParserError.unclosedShopifyBlock(tag, opening: opening) }
            throw LiquidError.syntax(message: "'\(tag)' tag was never closed", line: nil, column: nil)
        }
        if frames.last?.kind == .ifChanged { throw ParserError.unclosedTag("ifchanged") }
        throw ParserError.unexpectedToken(currentToken)
    }

    // MARK: - LiquidExpression Parsing
    
    private func parseConditionOperand() throws -> LiquidExpression {
        let value = try parsePrimaryExpression()
        if currentToken.type == .filter {
            if syntaxMode == .strict2 { throw ParserError.unexpectedTrailingToken(currentToken, kind: "pipe") }
            guard syntaxMode == .lax else { throw ParserError.unexpectedToken(currentToken) }
            while !isAtEnd && currentToken.type != .tagEnd { advance() }
        }
        return value
    }

    private func parseComplexExpression() throws ->LiquidExpression {
        var firstExpr = try parseConditionOperand()
        firstExpr = try parseComparisonContinuation(startingWith: firstExpr)

        // Collect all expressions and operators
        var expressions: [LiquidExpression] = [firstExpr]
        var operators: [BinaryOp] = []

        while currentToken.type == .and || currentToken.type == .or {
            let op: BinaryOp = currentToken.type == .and ? .and : .or
            advance()
            operators.append(op)

            var right = try parseConditionOperand()
            right = try parseComparisonContinuation(startingWith: right)
            expressions.append(right)
        }

        // Build tree right-to-left for right-associativity
        guard !operators.isEmpty else { return firstExpr }
        var result = expressions.last!
        for i in stride(from: operators.count - 1, through: 0, by: -1) {
            result = .binary(left: expressions[i], op: operators[i], right: result)
        }

        return result
    }

    @inline(__always)
    private func parseComparisonContinuation(startingWith left: LiquidExpression) throws ->LiquidExpression {
        if syntaxMode == .strict2, currentToken.type == .equals, nextTokenStorage.type == .equals,
           nextTokenStorage.position == currentToken.position + 2, case .original = sourceProvenance,
           let source, let start = stringIndex(in: source, utf8Offset: currentToken.position),
           source[start...].hasPrefix("==="), !source[start...].hasPrefix("====") {
            throw LiquidError.syntax(message: "Unexpected character =", line: nextTokenStorage.line + lineOffset, column: nextTokenStorage.column)
        }
        if syntaxMode == .lax {
            let unknown: InlineString?
            if currentToken.type == .equals && !isOriginalComparison(currentToken) {
                unknown = InlineString("=")
            } else if case .identifier(let name) = currentToken.type {
                unknown = name
            } else {
                unknown = nil
            }
            if let unknown {
                advance()
                let right: LiquidExpression
                if currentToken.type == .tagEnd || currentToken.type == .and || currentToken.type == .or {
                    right = .literal(.null)
                } else {
                    right = try parseConditionOperand()
                }
                return .unknownCondition(left: left, name: unknown, right: right)
            }
        }
        // Check for comparison operators
        let op: BinaryOp?
        switch currentToken.type {
        case .equals:
            op = .equals
        case .notEquals:
            op = .notEquals
        case .lessThan:
            op = .lessThan
        case .greaterThan:
            op = .greaterThan
        case .lessThanOrEqual:
            op = .lessThanOrEqual
        case .greaterThanOrEqual:
            op = .greaterThanOrEqual
        case .contains:
            op = .contains
        default:
            op = nil
        }
        
        if let op = op {
            advance() // consume operator
            let right = try parseConditionOperand()
            return .binary(left: left, op: op, right: right)
        }
        
        return left
    }
    
    @inline(__always)
    private func parseExpression() throws ->LiquidExpression {
        let expr = try parsePrimaryExpression()

        guard currentTokenStorage.type == .filter else {
            return expr
        }

        advance() // consume |

        // Ruby's lax scanner ignores empty filter segments. Strict modes
        // still reject the original pipe or end-of-string token.
        if syntaxMode == .lax {
            while currentTokenStorage.type == .filter { advance() }
            if currentTokenStorage.type == .variableEnd || currentTokenStorage.type == .tagEnd { return expr }
        }

        guard case .identifier(let firstFilterName) = currentTokenStorage.type else {
            throw identifierExpected(currentToken)
        }
        advance()

        var firstNamedArgs: [NamedFilterArgument] = []
        let firstArguments = try parseFilterArguments(namedArguments: &firstNamedArgs)
        let firstFilter = Filter(
            name: firstFilterName,
            arguments: firstArguments,
            namedArguments: firstNamedArgs
        )

        guard currentTokenStorage.type == .filter else {
            return .filtered(expr: expr, filters: [firstFilter])
        }

        var allFilters = makeFilterBuffer()
        allFilters.append(firstFilter)

        repeat {
            advance() // consume |

            if syntaxMode == .lax {
                while currentTokenStorage.type == .filter { advance() }
                if currentTokenStorage.type == .variableEnd || currentTokenStorage.type == .tagEnd { break }
            }

            guard case .identifier(let filterName) = currentTokenStorage.type else {
                throw identifierExpected(currentToken)
            }
            advance()

            var namedArgs: [NamedFilterArgument] = []
            let arguments = try parseFilterArguments(namedArguments: &namedArgs)
            allFilters.append(
                Filter(
                    name: filterName,
                    arguments: arguments,
                    namedArguments: namedArgs
                )
            )
        } while currentTokenStorage.type == .filter

        return .filtered(expr: expr, filters: allFilters)
    }

    @inline(__always)
    private func parseFilterArguments(namedArguments: inout [NamedFilterArgument]) throws -> [LiquidExpression] {
        guard currentToken.type == .colon else { return [] }
        advance()
        var arguments: [LiquidExpression] = []
        var positions: [ScalarKey: Int] = [:]
        func atFilterEnd() -> Bool {
            currentToken.type == .filter || currentToken.type == .variableEnd || currentToken.type == .tagEnd
        }
        if syntaxMode != .strict && atFilterEnd() { return arguments }
        repeat {
            if case .identifier(let name) = currentToken.type, nextTokenStorage.type == .colon {
                advance()
                advance()
                let value = try parsePrimaryExpression()
                let argument = NamedFilterArgument(name: name.string, value: value)
                if let index = positions[ScalarKey(name.string)] {
                    namedArguments[index] = argument
                } else {
                    positions[ScalarKey(name.string)] = namedArguments.count
                    namedArguments.append(argument)
                }
            } else {
                arguments.append(try parsePrimaryExpression())
            }
            guard currentToken.type == .comma else { break }
            advance()
            if syntaxMode != .strict && atFilterEnd() { break }
        } while true
        return arguments
    }

    @inline(__always)
    private func parsePrimaryExpression(allowBracketAccess: Bool = true) throws ->LiquidExpression {
        guard parseDepth < maxNestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
        parseDepth += 1
        defer { parseDepth -= 1 }
        switch currentToken.type {
        case .empty:
            return try parseNamedPrimary(InlineString("empty"), allowBracketAccess: allowBracketAccess)
        case .identifier(let name):
            return try parseNamedPrimary(name, allowBracketAccess: allowBracketAccess)

        case .string(let value):
            advance()
            return .literal(.string(value))
            
        case .number(let value, let isFloat):
            let literal = currentToken.exactInteger.map(Value.integer) ?? .number(value, isFloat: isFloat)
            advance()

            // Check for range operator
            if currentToken.type == .range {
                advance() // consume ..

                guard case .number(let endValue, let endIsFloat) = currentToken.type else {
                    throw ParserError.unexpectedToken(currentToken)
                }
                let endLiteral = currentToken.exactInteger.map(Value.integer) ?? .number(endValue, isFloat: endIsFloat)
                advance()

                return .range(start: .literal(literal), end: .literal(endLiteral))
            }

            return .literal(literal)
            
        case .leftParen:
            advance() // consume (

            // Parse range inside parentheses: (expr..expr)
            // Start can be a number, identifier, or negative number
            let startExpr: LiquidExpression
            if case .number(let startValue, let startIsFloat) = currentToken.type {
                startExpr = .literal(currentToken.exactInteger.map(Value.integer) ?? .number(startValue, isFloat: startIsFloat))
                advance()
            } else if case .identifier(let name) = currentToken.type {
                advance()
                var expr: LiquidExpression = .variable(name)
                // Handle dotted access like product.count
                while currentToken.type == .dot {
                    advance() // consume .
                    guard case .identifier(let prop) = currentToken.type else {
                        throw identifierExpected(currentToken)
                    }
                    advance()
                    expr = try propertyAccess(expr, property: prop)
                }
                startExpr = expr
            } else {
                throw ParserError.unexpectedToken(currentToken)
            }

            guard currentToken.type == .range else {
                if syntaxMode == .strict2, currentToken.type == .comma {
                    throw ParserError.expectedToken(.range, got: currentToken.type)
                }
                throw ParserError.unexpectedToken(currentToken)
            }
            advance() // consume ..

            // Shopify's lax range scanner tolerates a third dot.
            if syntaxMode == .lax, currentToken.type == .dot { advance() }

            let endExpr: LiquidExpression
            if case .number(let endValue, let endIsFloat) = currentToken.type {
                endExpr = .literal(currentToken.exactInteger.map(Value.integer) ?? .number(endValue, isFloat: endIsFloat))
                advance()
            } else if case .identifier(let name) = currentToken.type {
                advance()
                var expr: LiquidExpression = .variable(name)
                while currentToken.type == .dot {
                    advance()
                    guard case .identifier(let prop) = currentToken.type else {
                        throw identifierExpected(currentToken)
                    }
                    advance()
                    expr = try propertyAccess(expr, property: prop)
                }
                endExpr = expr
            } else {
                if syntaxMode == .strict2, currentToken.type == .rightParen {
                    throw ParserError.invalidCloseRoundExpression(currentToken)
                }
                throw ParserError.unexpectedToken(currentToken)
            }

            guard currentToken.type == .rightParen else {
                if syntaxMode == .strict2, currentToken.type == .tagEnd || currentToken.type == .variableEnd {
                    throw ParserError.expectedToken(.rightParen, got: currentToken.type)
                }
                throw ParserError.unexpectedToken(currentToken)
            }
            advance() // consume )

            return .range(start: startExpr, end: endExpr)
            
        case .leftBracket:
            if syntaxMode == .strict2 {
                throw LiquidError.syntax(message: "Bare bracket access is not allowed. Use self['...'] instead", line: currentToken.line + lineOffset, column: currentToken.column)
            }
            return try parseBracketChain(startingWith: .variable(InlineString("")))

        // Allow reserved words as variable names in expression context
        case .include, .for, .if, .elsif, .else, .unless, .case, .when,
             .comment, .raw, .capture, .tablerow, .cycle:
            let name = InlineString(currentToken.type.keywordString ?? "")
            advance()
            var expr: LiquidExpression = .variable(name)
            while currentTokenStorage.type == .dot {
                advance()
                guard case .identifier(let prop) = currentToken.type else { throw identifierExpected(currentToken) }
                advance()
                    expr = try propertyAccess(expr, property: prop)
            }
            while true {
                if currentTokenStorage.type == .dot, case .identifier(let property) = nextTokenStorage.type {
                    advance(); advance()
                    expr = try propertyAccess(expr, property: property)
                } else if allowBracketAccess, currentTokenStorage.type == .leftBracket {
                    expr = try parseBracketChain(startingWith: expr)
                } else { break }
            }
            return expr

        case .comma where syntaxMode == .strict2:
            throw ParserError.invalidCommaExpression(currentToken)
        case .rightParen where syntaxMode == .strict2:
            throw ParserError.invalidCloseRoundExpression(currentToken)
        case .tagEnd where syntaxMode == .strict2, .variableEnd where syntaxMode == .strict2:
            throw ParserError.invalidExpressionAtMarkupEnd(currentToken)
        default:
            if syntaxMode == .strict2 {
                let reason: (String, String)?
                switch currentToken.type {
                case .rightBracket: reason = ("close_square", "]")
                case .colon: reason = ("colon", ":")
                case .equals where isOriginalComparison(currentToken): reason = ("comparison", "==")
                case .notEquals: reason = ("comparison", "!=")
                case .lessThan: reason = ("comparison", "<")
                case .greaterThan: reason = ("comparison", ">")
                case .lessThanOrEqual: reason = ("comparison", "<=")
                case .greaterThanOrEqual: reason = ("comparison", ">=")
                case .contains: reason = ("comparison", "contains")
                case .dot: reason = ("dot", ".")
                case .range: reason = ("dotdot", "..")
                case .filter: reason = ("pipe", "|")
                case .question: reason = ("question", "?")
                case .dash: reason = ("dash", "-")
                default: reason = nil
                }
                if let (kind, spelling) = reason {
                    throw ParserError.invalidOperatorExpression(currentToken, kind: kind, spelling: spelling)
                }
            }
            throw ParserError.unexpectedToken(currentToken)
        }
    }

    private func parseBracketChain(startingWith initial: LiquidExpression) throws -> LiquidExpression {
        let entryDepth = parseDepth
        defer { parseDepth = entryDepth }
        var base = initial
        var parents: [LiquidExpression] = []
        while true {
            try Task.checkCancellation()
            advance() // [
            if currentToken.type == .leftBracket {
                if syntaxMode == .strict2 {
                    throw LiquidError.syntax(message: "Bare bracket access is not allowed. Use self['...'] instead", line: currentToken.line + lineOffset, column: currentToken.column)
                }
                guard parseDepth < maxNestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
                parseDepth += 1
                parents.append(base)
                base = .variable(InlineString(""))
                continue
            }
            var key = try parsePrimaryExpression(allowBracketAccess: false)
            if currentToken.type == .leftBracket {
                guard parseDepth < maxNestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
                parseDepth += 1
                parents.append(base)
                base = key
                continue
            }
            while true {
                let result: LiquidExpression
                if currentToken.type == .rightBracket {
                    advance()
                    var access: LiquidExpression = .access(expr: base, key: key)
                    while currentToken.type == .dot, case .identifier(let prop) = nextTokenStorage.type {
                        advance(); advance()
                        access = try propertyAccess(access, property: prop)
                    }
                    result = access
                } else if syntaxMode == .lax, currentToken.type == .variableEnd,
                          case .variable(let name) = base, name.string.isEmpty {
                    if case .literal(.string) = key { result = .access(expr: base, key: key) }
                    else { result = key }
                } else {
                    throw ParserError.expectedToken(.rightBracket, got: currentToken.type)
                }
                if currentToken.type == .leftBracket {
                    base = result
                    break
                }
                if let parent = parents.popLast() {
                    parseDepth -= 1
                    base = parent
                    key = result
                    continue
                }
                return result
            }
        }
    }

    private func collectQualifiedIdentifierComponents(
        startingWith first: InlineString
    ) throws ->[InlineString] {
        var components = [first]
        components.reserveCapacity(2)

        while currentTokenStorage.type == .dot {
            guard case .identifier(let property) = nextTokenStorage.type else {
                if syntaxMode != .strict2, current >= 2, tokens[current - 2].type == .variableStart,
                   nextTokenStorage.type == .variableEnd {
                    throw ParserError.unexpectedToken(nextTokenStorage)
                }
                throw identifierExpected(nextTokenStorage)
            }
            if property.string.utf8.first == 0x24 { break }
            advance()
            advance()
            components.append(property)
        }

        return components
    }

    private func parseQualifiedIdentifier() throws ->InlineString {
        guard case .identifier(let first) = currentToken.type else {
            throw ParserError.expectedIdentifier
        }
        advance()
        let components = try collectQualifiedIdentifierComponents(startingWith: first)
        return InlineString(components.map(\.string).joined(separator: "."))
    }

    @inline(__always)
    private func parseNamedPrimary(_ name: InlineString, allowBracketAccess: Bool = true) throws -> LiquidExpression {
            advance()

            if currentTokenStorage.type != .dot, currentTokenStorage.type != .leftBracket,
               let literal = literalExpression(for: name) {
                return literal
            }

            let components = try collectQualifiedIdentifierComponents(startingWith: name)

            if currentTokenStorage.type == .leftParen, syntaxMode != .strict2 {
                // Calls are outside the admitted Shopify language. Reject at
                // the boundary instead of recursively parsing an expression
                // that template validation would reject unconditionally.
                throw LiquidError.syntax(message: "Expression is outside standard Liquid", line: nil, column: nil)
            }

            var expr: LiquidExpression = .variable(name)
            for property in components.dropFirst() {
                expr = try propertyAccess(expr, property: property)
            }

            while true {
                if currentTokenStorage.type == .dot, case .identifier(let property) = nextTokenStorage.type {
                    advance(); advance()
                    expr = try propertyAccess(expr, property: property)
                } else if allowBracketAccess, currentTokenStorage.type == .leftBracket {
                    expr = try parseBracketChain(startingWith: expr)
                } else { break }
            }
            return expr
    }

    private func propertyAccess(_ expression: LiquidExpression, property: InlineString) throws -> LiquidExpression {
        let name = property.string
        guard name.utf8.first == 0x24 else {
            return .access(expr: expression, key: .literal(.string(property)), command: true)
        }
        guard extensionProfile == .closedSystemV1,
              let system = LiquidSystemProperty(rawValue: String(name.dropFirst())) else {
            throw ParserError.unsupportedFeature("Unknown system property")
        }
        return .systemAccess(expr: expression, property: system)
    }

    private func literalExpression(for identifier: InlineString) -> LiquidExpression? {
        if identifier.equals("blank") { return .literal(.special(.blank)) }
        switch identifier.utf8Count {
        case 3:
            if identifier.equals("nil") {
                return .literal(.null)
            }

        case 4:
            if identifier.equals("null") {
                return .literal(.null)
            }
            if identifier.equals("true") {
                return .literal(.boolean(true))
            }

        case 5:
            if identifier.equals("false") {
                return .literal(.boolean(false))
            }
            // Shopify Liquid: 'empty' evaluates to "" in expression context
            if identifier.equals("empty") {
                return .literal(.special(.empty))
            }

        default:
            break
        }

        return nil
    }
    
    // MARK: - Utility Methods
    
    @inline(__always)
    private var currentToken: Token {
        currentTokenStorage
    }
    
    @inline(__always)
    private var isAtEnd: Bool {
        return current >= tokens.count
    }
    
    @discardableResult
    @inline(__always)
    private func advance() -> Token {
        let previous = currentTokenStorage
        if !isAtEnd {
            current += 1
            refreshLookahead()
        }
        return previous
    }

    @inline(__always)
    private func makeNodeBuffer() -> [ASTNode] {
        var nodes: [ASTNode] = []
        nodes.reserveCapacity(min(max(4, max(1, tokens.count - current) / 4), 64))
        return nodes
    }

    @inline(__always)
    private func makeExpressionBuffer(initialCapacity: Int = 2) -> [LiquidExpression] {
        var expressions: [LiquidExpression] = []
        expressions.reserveCapacity(initialCapacity)
        return expressions
    }

    @inline(__always)
    private func makeFilterBuffer(initialCapacity: Int = 2) -> [Filter] {
        var filters: [Filter] = []
        filters.reserveCapacity(initialCapacity)
        return filters
    }

    @inline(__always)
    private func currentTagMatches(_ keyword: TokenType, identifier: StaticString) -> Bool {
        guard currentTokenStorage.type == .tagStart else { return false }
        return tagTokenMatches(nextTokenStorage.type, keyword: keyword, identifier: identifier)
    }

    @inline(__always)
    private func currentTagMatchesAny(
        _ first: (TokenType, StaticString),
        _ second: (TokenType, StaticString)
    ) -> Bool {
        guard currentTokenStorage.type == .tagStart else { return false }
        let tokenType = nextTokenStorage.type
        return tagTokenMatches(tokenType, keyword: first.0, identifier: first.1)
            || tagTokenMatches(tokenType, keyword: second.0, identifier: second.1)
    }

    @inline(__always)
    private func currentTagMatchesAny(
        _ first: (TokenType, StaticString),
        _ second: (TokenType, StaticString),
        _ third: (TokenType, StaticString)
    ) -> Bool {
        guard currentTokenStorage.type == .tagStart else { return false }
        let tokenType = nextTokenStorage.type
        return tagTokenMatches(tokenType, keyword: first.0, identifier: first.1)
            || tagTokenMatches(tokenType, keyword: second.0, identifier: second.1)
            || tagTokenMatches(tokenType, keyword: third.0, identifier: third.1)
    }

    @inline(__always)
    private func currentTagMatchesIdentifier(_ identifier: String) -> Bool {
        guard currentTokenStorage.type == .tagStart else { return false }
        guard case .identifier(let name) = nextTokenStorage.type else { return false }
        return name.string == identifier
    }

    @inline(__always)
    private func tagTokenMatches(_ tokenType: TokenType, keyword: TokenType, identifier: StaticString) -> Bool {
        if tokenType == keyword {
            return true
        }

        if case .identifier(let name) = tokenType {
            return name.equals(identifier)
        }

        return false
    }

    @inline(__always)
    private func consumeTagKeyword(_ keyword: TokenType, identifier: StaticString) throws {
        if currentToken.type == keyword {
            advance()
            return
        }

        if case .identifier(let name) = currentToken.type,
           name.equals(identifier) {
            advance()
            return
        }

        throw ParserError.unexpectedToken(currentToken)
    }

    private func consumeTagIdentifier(_ identifier: String) throws {
        guard case .identifier(let name) = currentToken.type,
              name.string == identifier else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
    }







    private func peekIdentifierName() -> InlineString? {
        guard case .identifier(let name) = currentTokenStorage.type else { return nil }
        return name
    }

    @inline(__always)
    private func refreshLookahead() {
        currentTokenStorage = current < tokens.count ? tokens[current] : Self.eofToken
        nextTokenStorage = (current + 1) < tokens.count ? tokens[current + 1] : Self.eofToken
    }
    
    private func identifierExpected(_ token: Token) -> ParserError {
        if syntaxMode == .strict2, case .number = token.type {
            return .expectedIdentifierBeforeNumber(token)
        }
        if syntaxMode == .strict2, case .string = token.type {
            return .expectedIdentifierBeforeString(token)
        }
        if syntaxMode == .strict2, token.type == .tagEnd || token.type == .variableEnd {
            return .expectedIdentifierAtMarkupEnd(token)
        }
        return .unexpectedToken(token)
    }

    // The lexer represents '=' and '==' with the same token. Only assign the
    // comparison reason after checking the original, immutable UTF-8 source.
    // Rewritten `liquid` bodies and ambiguous longer operators stay unmapped.
    private func isOriginalComparison(_ token: Token) -> Bool {
        guard token.type == .equals, case .original = sourceProvenance,
              let source, let start = stringIndex(in: source, utf8Offset: token.position) else { return false }
        let remaining = source[start...]
        return remaining.hasPrefix("==") && !remaining.hasPrefix("===")
    }

    private func trailingTokenError(_ token: Token) -> ParserError? {
        guard syntaxMode == .strict2 else { return nil }
        let kind: String
        switch token.type {
        case .identifier: return .unexpectedTrailingIdentifier(token)
        case .number: kind = "number"
        case .string: kind = "string"
        case .question: kind = "question"
        case .dash: kind = "dash"
        case .leftParen: kind = "open_round"
        case .rightParen: kind = "close_round"
        case .leftBracket: kind = "open_square"
        case .rightBracket: kind = "close_square"
        case .colon: kind = "colon"
        case .comma: kind = "comma"
        case .dot: kind = "dot"
        case .range: kind = "dotdot"
        case .filter: kind = "pipe"
        case .notEquals, .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual, .contains:
            kind = "comparison"
        case .equals where isOriginalComparison(token): kind = "comparison"
        // Single '=' and rewritten or otherwise unmapped tokens keep their
        // original rejection: their spelling has not been established.
        default: return nil
        }
        return .unexpectedTrailingToken(token, kind: kind)
    }

    @inline(__always)
    private func consumeTagEnd(presentComparison: Bool = true) throws {
        guard currentTokenStorage.type == .tagEnd else {
            if !presentComparison, currentToken.type == .equals {
                throw ParserError.unexpectedToken(currentToken)
            }
            if let error = trailingTokenError(currentToken) { throw error }
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
    }

    private func sourceString(forTokenRange range: Range<Int>) -> String {
        guard !range.isEmpty else {
            return ""
        }

        if let exactSource = exactSourceString(forTokenRange: range) {
            return exactSource
        }

        return reconstructSource(forTokenRange: range)
    }

    private func liquidBodySource(forTokenRange range: Range<Int>) -> String {
        guard !range.isEmpty else {
            return ""
        }

        if let exactSource = exactSourceString(forTokenRange: range) {
            return exactSource
        }

        var output = ""
        var previousToken: Token?

        for token in tokens[range] {
            if let previousToken {
                if token.line > previousToken.line {
                    output.append("\n")
                } else if shouldInsertSpace(between: previousToken.type, and: token.type) {
                    output.append(" ")
                }
            }

            output.append(tokenSourceLexeme(token))
            previousToken = token
        }

        return output
    }

    private func exactSourceString(forTokenRange range: Range<Int>) -> String? {
        guard let source,
              range.lowerBound >= 0,
              range.upperBound <= tokens.count,
              range.lowerBound < range.upperBound else {
            return nil
        }

        let startOffset = tokens[range.lowerBound].position
        let endOffset: Int
        if range.upperBound < tokens.count {
            endOffset = tokens[range.upperBound].position
        } else {
            endOffset = source.utf8.count
        }

        guard let startIndex = stringIndex(in: source, utf8Offset: startOffset),
              let endIndex = stringIndex(in: source, utf8Offset: endOffset),
              startIndex <= endIndex else {
            return nil
        }

        return String(source[startIndex..<endIndex])
    }

    private func stringIndex(in source: String, utf8Offset: Int) -> String.Index? {
        guard utf8Offset >= 0 else {
            return nil
        }

        let utf8View = source.utf8
        guard let utf8Index = utf8View.index(utf8View.startIndex, offsetBy: utf8Offset, limitedBy: utf8View.endIndex),
              let index = String.Index(utf8Index, within: source) else {
            return nil
        }

        return index
    }

    private func reconstructSource(forTokenRange range: Range<Int>) -> String {
        var output = ""
        var previous: TokenType?

        for token in tokens[range] {
            let tokenType = token.type
            let lexeme = tokenSourceLexeme(token)

            if !output.isEmpty && shouldInsertSpace(between: previous, and: tokenType) {
                output.append(" ")
            }

            output.append(lexeme)
            previous = tokenType
        }

        return output
    }

    private func tokenSourceLexeme(_ token: Token) -> String {
        switch token.type {
        case .tagStart:
            return token.trimLeft ? "{%-" : "{%"
        case .tagEnd:
            return token.trimRight ? "-%}" : "%}"
        case .variableStart:
            return token.trimLeft ? "{{-" : "{{"
        case .variableEnd:
            return token.trimRight ? "-}}" : "}}"
        default:
            return token.type.sourceLexeme
        }
    }

    private func shouldInsertSpace(between previous: TokenType?, and current: TokenType) -> Bool {
        guard let previous else {
            return false
        }

        if case .text = previous {
            return false
        }
        if case .text = current {
            return false
        }

        switch current {
        case .dot, .comma, .colon, .rightParen, .tagEnd, .variableEnd:
            return false
        default:
            break
        }

        switch previous {
        case .leftParen, .tagStart, .variableStart, .dot:
            return false
        default:
            return true
        }
    }
    
    // MARK: - Helper Methods for Control Flow
    
    @inline(__always)
    private func isElsifOrElseOrEndif() -> Bool {
        currentTagMatchesAny(
            (.elsif, "elsif"),
            (.else, "else"),
            (.endif, "endif")
        )
    }
    
    @inline(__always)
    private func isEndif() -> Bool {
        currentTagMatches(.endif, identifier: "endif")
    }
    
    @inline(__always)
    private func isElseOrEndunless() -> Bool {
        currentTagMatchesAny(
            (.elsif, "elsif"),
            (.else, "else"),
            (.endunless, "endunless")
        )
    }
    
    @inline(__always)
    private func isEndunless() -> Bool {
        currentTagMatches(.endunless, identifier: "endunless")
    }
    
    // MARK: - Complex Tag Parsing (Stubs)

    // Ruby's lax VariableLookup reads contiguous lookup fragments in case
    // operands even when '=' or '=>' separates their names. Restrict this
    // adaptation to original, byte-adjacent tokens; strict2 stays unchanged.
    private func parseCaseOperand() throws -> LiquidExpression {
        let first = try syntaxMode == .strict2 ? parsePrimaryExpression() : parseExpression()
        guard syntaxMode != .strict2, case .original = sourceProvenance,
              case .variable(let root) = first, current > 0,
              currentToken.type == .equals, !isOriginalComparison(currentToken),
              currentToken.position == tokens[current - 1].position + root.string.utf8.count else { return first }
        let equalsPosition = currentToken.position
        var propertyIndex = current + 1
        if propertyIndex < tokens.count, tokens[propertyIndex].type == .greaterThan,
           tokens[propertyIndex].position == equalsPosition + 1 {
            propertyIndex += 1
        }
        let expectedPosition = equalsPosition + (propertyIndex == current + 2 ? 2 : 1)
        guard propertyIndex < tokens.count,
              tokens[propertyIndex].position == expectedPosition,
              case .identifier(let property) = tokens[propertyIndex].type else { return first }
        while current <= propertyIndex { advance() }
        return .access(expr: first, key: .literal(.string(property)), command: true)
    }
    
    private func parseCaseTag() throws ->ASTNode {
        try parseNestedBlocks(initial: .caseBlock)
    }

    private func parseCaseWhenHeader() throws -> [LiquidExpression] {
        advance() // consume {%
        try consumeTagKeyword(.when, identifier: "when")

        var whenValues = makeExpressionBuffer()
        whenValues.append(try parseCaseOperand())

        // Parse comma/or/and separated values
        // 'and' in when expressions invalidates the entire when clause (Shopify behavior)
        var hasInvalidAnd = false
        while currentToken.type == .comma || currentToken.type == .or || currentToken.type == .and {
            if currentToken.type == .and { hasInvalidAnd = true }
            advance()
            whenValues.append(try parseCaseOperand())
        }
        if hasInvalidAnd {
            if syntaxMode == .strict2 { throw ParserError.invalidParameterValue("when", expected: "comma or or") }
            whenValues.removeAll()
        }

        if syntaxMode != .strict2 {
            while !isAtEnd && currentToken.type != .tagEnd {
                try Task.checkCancellation()
                advance()
            }
        }
        try consumeTagEnd()

        return whenValues
    }

    @inline(__always)
    private func isWhenOrElseOrEndcase() -> Bool {
        currentTagMatchesAny(
            (.when, "when"),
            (.else, "else"),
            (.endcase, "endcase")
        )
    }
    
    @inline(__always)
    private func isEndcase() -> Bool {
        currentTagMatches(.endcase, identifier: "endcase")
    }
    
    private func parseForHeader() throws -> (InlineString, LiquidExpression, ForParams) {
        let blockLocation = RenderLocation(line: tokens[current - 1].line + lineOffset, suppressErrorText: syntaxMode != .strict2, hasOriginalSource: hasOriginalSource)
        func isRuntimeLookup(_ expression: LiquidExpression) -> Bool {
            switch expression {
            case .variable, .access: return true
            default: return false
            }
        }
        guard case .identifier(let variable) = currentToken.type else {
            throw identifierExpected(currentToken)
        }
        advance()
        
        guard currentToken.type == .in else {
            if syntaxMode == .strict2 {
                throw LiquidError.syntax(message: "For loops require an 'in' clause", line: currentToken.line + lineOffset, column: currentToken.column)
            }
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        
        let collection = try syntaxMode == .strict2 ? parsePrimaryExpression() : parseExpression()
        
        // Parse optional parameters
        var limit: Int? = nil
        var offset: Int? = nil
        var offsetContinue = false
        var reversed = false
        var limitExpression: LiquidExpression? = nil
        var offsetExpression: LiquidExpression? = nil
        
        // `reversed` is a modifier immediately after the collection. Once
        // attribute parsing starts, strict modes accept only limit/offset.
        var reversedMayAppear = true
        func invalidAttribute() -> LiquidError {
            .syntax(message: "Invalid attribute in for loop. Valid attributes are limit and offset",
                    line: currentToken.line + lineOffset, column: currentToken.column)
        }
        if currentToken.type == .comma {
            reversedMayAppear = false
            advance()
            if syntaxMode != .lax && currentToken.type == .tagEnd { throw invalidAttribute() }
        }
        while let paramName = peekIdentifierName() {
            guard paramName.equals("limit")
                    || paramName.equals("offset")
                    || paramName.equals("reversed") else {
                if syntaxMode == .strict2 { throw invalidAttribute() }
                break
            }

            if paramName.equals("reversed") && !reversedMayAppear && syntaxMode != .lax {
                throw invalidAttribute()
            }
            advance() // consume parameter name
            
            if paramName.equals("reversed") {
                if reversedMayAppear {
                    reversed = true
                }
                // Ruby's lax parser ignores modifiers after the initial one.
                reversedMayAppear = false
                continue
            }
            reversedMayAppear = false

            guard currentToken.type == .colon else {
                throw ParserError.unexpectedToken(currentToken)
            }
            advance()

            // Each occurrence replaces the preceding attribute, regardless of
            // whether either value is a literal, lookup, or `continue`.
            if paramName.equals("limit") {
                limit = nil
                limitExpression = nil
            } else {
                offset = nil
                offsetExpression = nil
                offsetContinue = false
            }
            
            // Check for offset: continue (special keyword)
            if paramName.equals("offset"),
               (currentToken.type == .continue ||
                (currentToken.type == .identifier(InlineString("continue")))) {
                advance() // consume 'continue'
                offsetContinue = true
            } else {
                let value = try parsePrimaryExpression()

                if case .literal(let literal) = value, let num = literal.parameterInteger {
                    if paramName.equals("limit") {
                        limit = Int(num)
                    } else if paramName.equals("offset") {
                        offset = Int(num)
                    }
                } else if case .literal(.string(let str)) = value {
                    // String coercion: "2" → 2 (Shopify behavior)
                    if let intVal = Int(str.string) {
                        if paramName.equals("limit") { limit = intVal }
                        else if paramName.equals("offset") { offset = intVal }
                    } else {
                        // Non-numeric string like 'foo' → error
                        throw ParserError.unexpectedToken(currentToken)
                    }
                } else if isRuntimeLookup(value) {
                    // Retain variable/property/index expressions for runtime evaluation.
                    if paramName.equals("limit") { limitExpression = value }
                    else if paramName.equals("offset") { offsetExpression = value }
                } else {
                    // Boolean, nil, or other non-numeric type → error
                    throw ParserError.unexpectedToken(currentToken)
                }
            }
            // Commas separate attributes; they do not terminate the list in
            // strict modes. Lax retains its existing acceptance of a suffix.
            if currentToken.type == .comma {
                advance()
                if syntaxMode != .lax && currentToken.type == .tagEnd { throw invalidAttribute() }
            }
        }

        let params = ForParams(limit: limit, offset: offset, offsetContinue: offsetContinue, reversed: reversed, limitExpression: limitExpression, offsetExpression: offsetExpression, renderLocation: blockLocation)
        
        try consumeTagEnd()
        
        return (variable, collection, params)
    }

    private func parseForTag() throws ->ASTNode {
        try parseNestedBlocks(initial: .loop)
    }

    @inline(__always)
    private func isEmptyOrEndfor() -> Bool {
        currentTagMatches(.else, identifier: "else") || currentTagMatches(.endfor, identifier: "endfor")
    }
    
    @inline(__always)
    private func isElseOrEndfor() -> Bool {
        currentTagMatchesAny(
            (.else, "else"),
            (.endfor, "endfor")
        )
    }
    
    @inline(__always)
    private func isEndfor() -> Bool {
        currentTagMatches(.endfor, identifier: "endfor")
    }
    
    @inline(__always)
    private func isEndtablerow() -> Bool {
        currentTagMatches(.endtablerow, identifier: "endtablerow")
    }
    
    private func parseTableRowHeader() throws -> (InlineString, LiquidExpression, TableRowParams) {
        guard case .identifier(let variable) = currentToken.type else {
            throw identifierExpected(currentToken)
        }
        advance()
        
        guard currentToken.type == .in else {
            if syntaxMode == .strict2 {
                throw LiquidError.syntax(message: "For loops require an 'in' clause", line: currentToken.line + lineOffset, column: currentToken.column)
            }
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        
        let collection = try syntaxMode == .strict2 ? parsePrimaryExpression() : parseExpression()
        
        // Parse optional parameters
        var cols: LiquidExpression? = nil
        var limit: LiquidExpression? = nil
        var offset: LiquidExpression? = nil
        
        if currentToken.type == .comma { advance() }
        while currentToken.type != .tagEnd && !isAtEnd {
            guard let paramName = peekIdentifierName() else {
                if syntaxMode == .strict2 { break }
                advance()
                continue
            }
            guard paramName.equals("cols")
                    || paramName.equals("limit")
                    || paramName.equals("offset")
                    || paramName.equals("range") else {
                if syntaxMode == .strict2 {
                    throw LiquidError.syntax(
                        message: "Invalid attribute '\(paramName.string)' in tablerow loop. Valid attributes are cols, limit, offset, and range",
                        line: currentToken.line + lineOffset, column: currentToken.column
                    )
                }
                advance()
                continue
            }

            if syntaxMode != .strict2 && nextTokenStorage.type != .colon {
                advance()
                continue
            }

            advance() // consume parameter name
            
            guard currentToken.type == .colon else {
                throw ParserError.unexpectedToken(currentToken)
            }
            advance()
            
            let value = try parsePrimaryExpression()

            if paramName.equals("cols") { cols = value }
            else if paramName.equals("limit") { limit = value }
            else if paramName.equals("offset") { offset = value }
            // Ruby accepts `range` as an attribute but does not use it when rendering.
            if currentToken.type == .comma { advance() }
        }

        let params = TableRowParams(cols: cols, limit: limit, offset: offset)
        try consumeTagEnd()
        
        return (variable, collection, params)
    }

    private func parseTableRowTag() throws ->ASTNode {
        try parseNestedBlocks(initial: .table)
    }

    private func parseCaptureHeader() throws -> InlineString {
        let variable: InlineString
        if case .identifier(let name) = currentToken.type {
            variable = name
        } else if case .string(let name) = currentToken.type, syntaxMode != .strict2,
                  let range = name.string.range(of: #"[\w.\[\]-]+"#, options: .regularExpression) {
            variable = InlineString(String(name.string[range]))
        } else if case .number(let num, _) = currentToken.type {
            if syntaxMode == .strict2 { throw identifierExpected(currentToken) }
            // Digit-only variable names: {% capture 123 %}
            variable = InlineString(String(Int(num)))
        } else {
            throw identifierExpected(currentToken)
        }
        advance()
        try consumeTagEnd()
        
        return variable
    }

    private func parseCaptureTag() throws ->ASTNode {
        try parseNestedBlocks(initial: .capture)
    }

    private func parseIncrementTag() throws ->ASTNode {
        if syntaxMode != .strict2, currentToken.type == .tagEnd {
            advance()
            return .increment(name: InlineString(""))
        }
        guard case .identifier(let counter) = currentToken.type else {
            throw identifierExpected(currentToken)
        }
        advance()
        try consumeTagEnd()
        
        return .increment(name: counter)
    }
    
    private func parseDecrementTag() throws ->ASTNode {
        if syntaxMode != .strict2, currentToken.type == .tagEnd {
            advance()
            return .decrement(name: InlineString(""))
        }
        guard case .identifier(let counter) = currentToken.type else {
            throw identifierExpected(currentToken)
        }
        advance()
        try consumeTagEnd()
        
        return .decrement(name: counter)
    }

    private func parseBreakTag() throws ->ASTNode {
        try consumeTagEnd()
        return .break
    }

    private func parseContinueTag() throws ->ASTNode {
        try consumeTagEnd()
        return .continue
    }


    
    private func parseRawTag() throws ->ASTNode {
        // Record position right after {% raw %} tag end
        let tagEndToken = currentToken
        let opening = originalBlockOpening()
        if syntaxMode == .strict2, currentToken.type != .tagEnd, let opening {
            throw ParserError.invalidBlockMarkup("raw", opening: opening)
        }
        try consumeTagEnd(presentComparison: false)

        // If we have the original source, extract raw content verbatim
        if let source {
            let rawStartPosition = tagEndToken.position + 2 // after %} (position is already past any trim marker)

            // Skip tokens until we find {% endraw %}
            while !isAtEnd && !currentTagMatches(.endraw, identifier: "endraw") {
                advance()
            }

            guard currentTagMatches(.endraw, identifier: "endraw") else {
                if syntaxMode == .strict2, let opening { throw ParserError.unclosedShopifyBlock("raw", opening: opening) }
                throw ParserError.unexpectedToken(currentToken)
            }

            // The endraw tag start token position is the end of raw content
            let rawEndPosition = currentToken.position

            // Extract verbatim content from source
            let startIndex = source.utf8.index(source.startIndex, offsetBy: rawStartPosition, limitedBy: source.endIndex) ?? source.endIndex
            let endIndex = source.utf8.index(source.startIndex, offsetBy: rawEndPosition, limitedBy: source.endIndex) ?? source.endIndex
            let content = String(source[startIndex ..< endIndex])

            advance() // consume {%
            try consumeTagKeyword(.endraw, identifier: "endraw")
            try consumeTagEnd()

            return .raw(InlineString(content))
        }

        // Fallback: reconstruct from tokens (lossy)
        var content = ""
        while !isAtEnd && !currentTagMatches(.endraw, identifier: "endraw") {
            switch currentToken.type {
            case .text(let text):
                content.append(text.string)
            case .variableStart:
                content.append(currentToken.trimLeft ? "{{-" : "{{")
            case .variableEnd:
                content.append(currentToken.trimRight ? "-}}" : "}}")
            case .tagStart:
                content.append(currentToken.trimLeft ? "{%-" : "{%")
            case .tagEnd:
                content.append(currentToken.trimRight ? "-%}" : "%}")
            default:
                content.append(" ")
            }
            advance()
        }

        guard currentTagMatches(.endraw, identifier: "endraw") else {
            if syntaxMode == .strict2, let opening { throw ParserError.unclosedShopifyBlock("raw", opening: opening) }
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        try consumeTagKeyword(.endraw, identifier: "endraw")
        try consumeTagEnd()

        return .raw(InlineString(content))
    }
    
    private func parseLiquidTag() throws ->ASTNode {
        let markupStart = current
        let markupLine = currentToken.line
        while currentToken.type != .tagEnd && !isAtEnd {
            advance()
        }

        var bodySource = liquidBodySource(forTokenRange: markupStart..<current)
        // Strip trailing `-` that may be captured from `-%}` trim marker
        if bodySource.hasSuffix("-") {
            bodySource = String(bodySource.dropLast())
        }
        try consumeTagEnd()

        let rewrittenTemplate = rewriteLiquidBodyAsTemplate(bodySource)
        guard !rewrittenTemplate.isEmpty else {
            return .liquid(body: [])
        }

        let nestedTokens: [Token]
        do {
            nestedTokens = try Lexer(rewrittenTemplate, syntaxMode: syntaxMode, extensionProfile: extensionProfile).tokenize()
        } catch {
            throw ParserError.unsupportedFeature("Lexer error in liquid tag body: \(error)")
        }
        let nestedParser = Parser(
            consuming: nestedTokens,
            source: rewrittenTemplate,
            liquidBody: true,
            syntaxMode: syntaxMode,
            extensionProfile: extensionProfile,
            maxNestingDepth: maxNestingDepth,
            lineOffset: lineOffset + markupLine - 1
        )
        let nestedAST = try nestedParser.parse()

        guard case .template(let nodes) = nestedAST else {
            return .liquid(body: [])
        }

        return .liquid(body: try normalizeLiquidBodyNodes(nodes))
    }



    private func rewriteLiquidBodyAsTemplate(_ bodySource: String) -> String {
        // Shopify Liquid: only \n is a valid line separator in liquid tags, not \r
        if bodySource.contains("\r") && !bodySource.contains("\n") {
            // Pure \r line endings are not supported
            return "{% invalid_liquid_cr %}"
        }
        // Normalize \r\n to \n
        let normalizedSource = bodySource.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var result: [String] = []
        var inComment = false
        for line in lines {
            if line.isEmpty { result.append(""); continue }

            if inComment {
                // Inside comment block, check for endcomment
                if line == "endcomment" {
                    result.append("{% endcomment %}")
                    inComment = false
                }
                else { result.append("") }
                // Keep line positions while the comment lexer discards content.
                continue
            }

            if line.hasPrefix("comment") {
                result.append("{% comment %}")
                inComment = true
                continue
            }

            // Handle # inline comments — skip them
            if line.hasPrefix("#") {
                result.append("")
                continue
            }

            // Handle echo — convert to output: {% echo expr %} → {{ expr }}
            if line.hasPrefix("echo ") {
                let expr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append("{{ \(expr) }}")
                continue
            }

            result.append("{% \(line) %}")
        }

        return result.joined(separator: "\n")
    }

    private func normalizeLiquidBodyNodes(_ nodes: [ASTNode]) throws -> [ASTNode] {
        enum Work {
            case list([ASTNode])
            case node(ASTNode)
            case finishList(Int)
            case finishNode(ASTNode, Int)
        }
        var work: [Work] = [.list(nodes)]
        var results: [[ASTNode]] = []
        while let item = work.popLast() {
            try Task.checkCancellation()
            switch item {
            case .list(let children):
                work.append(.finishList(children.count))
                for child in children.reversed() { work.append(.node(child)) }
            case .finishList(let count):
                let start = results.count - count
                let merged = results[start...].flatMap { $0 }
                results.removeLast(count)
                results.append(merged)
            case .node(let node):
                if case .text(let text) = node {
                    results.append(text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [node])
                    continue
                }
                let groups: [[ASTNode]]
                switch node {
                case .template(let body), .ifchanged(let body), .capture(_, let body), .tablerow(_, _, let body, _):
                    groups = [body]
                case .if(_, let body, let branches, let fallback, _):
                    groups = [body] + branches.map { $0.1 } + (fallback.map { [$0] } ?? [])
                case .unless(_, let body, let fallback, _), .for(_, _, let body, let fallback, _):
                    groups = [body] + (fallback.map { [$0] } ?? [])
                case .case(_, let branches):
                    groups = branches.map(\.body)
                default:
                    results.append([node])
                    continue
                }
                work.append(.finishNode(node, groups.count))
                for group in groups.reversed() { work.append(.list(group)) }
            case .finishNode(let node, let count):
                let start = results.count - count
                let groups = Array(results[start...])
                results.removeLast(count)
                let rebuilt: ASTNode
                switch node {
                case .template: rebuilt = .template(groups[0])
                case .ifchanged: rebuilt = .ifchanged(groups[0])
                case .capture(let name, _): rebuilt = .capture(variable: name, body: groups[0])
                case .tablerow(let name, let collection, _, let params):
                    rebuilt = .tablerow(variable: name, in: collection, body: groups[0], params: params)
                case .if(let condition, _, let branches, let fallback, let location):
                    let mapped = branches.enumerated().map { ($0.element.0, groups[$0.offset + 1]) }
                    rebuilt = .if(condition: condition, then: groups[0], elsif: mapped,
                                  else: fallback == nil ? nil : groups[branches.count + 1], location: location)
                case .unless(let condition, _, let fallback, let location):
                    rebuilt = .unless(condition: condition, then: groups[0], else: fallback == nil ? nil : groups[1], location: location)
                case .for(let name, let collection, _, let fallback, let params):
                    rebuilt = .for(variable: name, in: collection, body: groups[0], empty: fallback == nil ? nil : groups[1], params: params)
                case .case(let value, let branches):
                    let mapped = branches.enumerated().map { index, branch -> CaseBranch in
                        switch branch {
                        case .when(let expression, _): return .when(expression, groups[index])
                        case .otherwise: return .otherwise(groups[index])
                        }
                    }
                    rebuilt = .case(value: value, branches: mapped)
                default: preconditionFailure("Unexpected liquid body normalization frame")
                }
                results.append([rebuilt])
            }
        }
        return results.first ?? []
    }

    private func parseCycleOperand() throws -> LiquidExpression {
        // Ruby's lax cycle parser treats a dot followed by digits as a
        // variable lookup. Preserve its exact original spelling, including
        // leading zeros, instead of converting it to a numeric literal.
        if syntaxMode != .strict2, case .original = sourceProvenance,
           currentToken.type == .dot, nextTokenStorage.position == currentToken.position + 1,
           case .number(_, let isFloat) = nextTokenStorage.type, !isFloat,
           let source, let start = stringIndex(in: source, utf8Offset: nextTokenStorage.position) {
            try Task.checkCancellation()
            let digits = source[start...].utf8.prefix { (48...57).contains($0) }
            if !digits.isEmpty {
                let name = InlineString(utf8: digits)
                advance()
                advance()
                return .variable(name)
            }
        }
        return try parsePrimaryExpression()
    }

    private func parseCycleTag() throws ->ASTNode {
        var values = makeExpressionBuffer(initialCapacity: 4)

        if currentToken.type == .tagEnd {
            throw LiquidError.syntax(message: "Syntax Error in 'cycle' - Valid syntax: cycle [name :] var [, var2, var3 ...]", line: currentToken.line + lineOffset, column: currentToken.column)
        }

        // Parse first value — might be a group name followed by ':'
        let firstExpr = try parseCycleOperand()

        // Check for named cycle: {% cycle name: val1, val2 %}
        var group: LiquidExpression? = nil
        if currentToken.type == .colon {
            advance() // consume ':'
            group = firstExpr
            // Parse actual cycle values
            values.append(try parseCycleOperand())
        } else {
            values.append(firstExpr)
        }

        // Ruby's lax cycle parser takes the first expression in each
        // comma-separated fragment and ignores a trailing fragment suffix.
        // Strict2 instead validates the full token stream.
        while true {
            if syntaxMode != .strict2 {
                while !isAtEnd && currentToken.type != .comma && currentToken.type != .tagEnd {
                    try Task.checkCancellation()
                    advance()
                }
            }
            guard currentToken.type == .comma else { break }
            advance()
            if currentToken.type == .tagEnd { break }
            values.append(try parseCycleOperand())
        }

        try consumeTagEnd()
        return .cycle(group: group, items: values, site: CycleSiteIdentity())
    }
    
    private func parseIncludeTag() throws ->ASTNode {
        let location = RenderLocation(line: tokens[current - 1].line + lineOffset, suppressErrorText: false, hasOriginalSource: hasOriginalSource)
        let templateName = try parsePrimaryExpression()
        let templateStr: InlineString
        if case .literal(.string(let name)) = templateName {
            templateStr = name
        } else if case .variable(let name) = templateName {
            // Support include with variable name: {% include my_template %}
            templateStr = name
        } else if case .access = templateName {
            // The runtime evaluates this newly admitted dynamic expression;
            // no literal candidate is implied by its source spelling.
            templateStr = InlineString("")
        } else {
            throw ParserError.expectedString
        }

        var variables: [String: LiquidExpression] = [:]
        variables.reserveCapacity(4)
        var alias: InlineString? = nil

        // Shopify's strict parser permits an alias even without `with` or `for`.
        if syntaxMode == .strict2, case .identifier(let keyword) = currentToken.type,
           keyword.equals("as") {
            advance()
            guard case .identifier(let aliasName) = currentToken.type else {
                throw identifierExpected(currentToken)
            }
            alias = aliasName
            advance()
        }

        // Skip optional comma after template name
        if currentToken.type == .comma { advance() }

        // Parse optional variable assignments
        while currentToken.type != .tagEnd {
            if currentToken.type == .for {
                // {% include 'template' for collection %} — iterate over collection
                advance() // consume 'for'
                let expr = try parseExpression()
                variables["_for"] = expr
                if case .identifier(let keyword) = currentToken.type, keyword.equals("as") {
                    advance()
                    guard case .identifier(let aliasName) = currentToken.type else {
                        throw identifierExpected(currentToken)
                    }
                    alias = aliasName
                    advance()
                }
                // Skip optional comma
                if currentToken.type == .comma { advance() }
            } else if case .identifier(let varName) = currentToken.type {
                advance()

                guard currentToken.type == .colon else {
                    if syntaxMode == .strict2, currentToken.type == .comma {
                        throw ParserError.missingAttributeColonBeforeComma(currentToken)
                    }
                    if syntaxMode == .strict2, currentToken.type == .tagEnd {
                        throw LiquidError.syntax(message: "Expected colon but found end_of_string", line: currentToken.line + lineOffset, column: currentToken.column)
                    }
                    throw ParserError.unexpectedToken(currentToken)
                }
                advance()

                let value = try parsePrimaryExpression()
                variables[varName.string] = value

                // Skip optional comma
                if currentToken.type == .comma {
                    advance()
                }
            } else if currentToken.type == .with {
                advance() // consume 'with'
                // Parse the object to merge
                let expr = try parsePrimaryExpression()
                variables["_with"] = expr
                if case .identifier(let keyword) = currentToken.type, keyword.equals("as") {
                    advance()
                    guard case .identifier(let aliasName) = currentToken.type else {
                        throw identifierExpected(currentToken)
                    }
                    alias = aliasName
                    advance()
                }
                if currentToken.type == .comma { advance() }
            } else {
                if let error = trailingTokenError(currentToken) { throw error }
                if syntaxMode == .strict2, isOriginalComparison(currentToken) {
                    throw ParserError.unexpectedTrailingToken(currentToken, kind: "comparison")
                }
                if syntaxMode == .strict2, currentToken.type == .filter {
                    throw ParserError.unexpectedTrailingToken(currentToken, kind: "pipe")
                }
                throw ParserError.unexpectedToken(currentToken)
            }
        }

        try consumeTagEnd()
        return .include(template: templateStr, reference: templateName, with: variables.isEmpty ? nil : variables, as: alias, location: location)
    }
    
    private func parseRenderTag() throws ->ASTNode {
        let location = RenderLocation(line: tokens[current - 1].line + lineOffset, suppressErrorText: false, hasOriginalSource: hasOriginalSource)
        // Similar to include but with isolated scope
        if syntaxMode == .strict2, currentToken.type == .tagEnd {
            throw LiquidError.syntax(message: "Expected string but found end_of_string", line: currentToken.line + lineOffset, column: currentToken.column)
        }
        if syntaxMode != .strict2, currentToken.type == .tagEnd {
            throw LiquidError.syntax(message: "Syntax error in tag 'render' - Template name must be a quoted string", line: nil, column: nil)
        }
        let templateName = try parsePrimaryExpression()
        let templateStr: InlineString
        if case .literal(.string(let name)) = templateName {
            templateStr = name
        } else {
            if syntaxMode != .strict2 {
                throw LiquidError.syntax(message: "Syntax error in tag 'render' - Template name must be a quoted string", line: nil, column: nil)
            }
            throw ParserError.expectedString
        }

        var variables: [String: LiquidExpression] = [:]
        variables.reserveCapacity(4)
        var alias: InlineString? = nil

        if syntaxMode == .strict2, case .identifier(let keyword) = currentToken.type,
           keyword.equals("as") {
            advance()
            guard case .identifier(let aliasName) = currentToken.type else {
                throw identifierExpected(currentToken)
            }
            alias = aliasName
            advance()
        }

        // Skip optional comma after template name
        if currentToken.type == .comma { advance() }

        // Parse optional variable assignments
        while currentToken.type != .tagEnd {
            if case .identifier(let varName) = currentToken.type {
                advance()
                
                guard currentToken.type == .colon else {
                    if syntaxMode == .strict2, currentToken.type == .comma {
                        throw ParserError.missingAttributeColonBeforeComma(currentToken)
                    }
                    if syntaxMode == .strict2, currentToken.type == .tagEnd {
                        throw LiquidError.syntax(message: "Expected colon but found end_of_string", line: currentToken.line + lineOffset, column: currentToken.column)
                    }
                    throw ParserError.unexpectedToken(currentToken)
                }
                advance()
                
                let value = try parsePrimaryExpression()
                variables[varName.string] = value
                
                // Skip optional comma
                if currentToken.type == .comma {
                    advance()
                }
            } else if currentToken.type == .with {
                advance()
                let expr = try parsePrimaryExpression()
                variables["_with"] = expr
                if case .identifier(let keyword) = currentToken.type, keyword.equals("as") {
                    advance()
                    guard case .identifier(let aliasName) = currentToken.type else {
                        throw identifierExpected(currentToken)
                    }
                    alias = aliasName
                    advance()
                }
                if currentToken.type == .comma { advance() }
            } else if currentToken.type == .for {
                advance()
                let expr = try parsePrimaryExpression()
                variables["_for"] = expr
                if case .identifier(let keyword) = currentToken.type, keyword.equals("as") {
                    advance()
                    guard case .identifier(let aliasName) = currentToken.type else {
                        throw identifierExpected(currentToken)
                    }
                    alias = aliasName
                    advance()
                }
                if currentToken.type == .comma { advance() }
            } else {
                if let error = trailingTokenError(currentToken) { throw error }
                if syntaxMode == .strict2, isOriginalComparison(currentToken) {
                    throw ParserError.unexpectedTrailingToken(currentToken, kind: "comparison")
                }
                if syntaxMode == .strict2, currentToken.type == .filter {
                    throw ParserError.unexpectedTrailingToken(currentToken, kind: "pipe")
                }
                throw ParserError.unexpectedToken(currentToken)
            }
        }
        
        try consumeTagEnd()
        return .include(template: templateStr, reference: templateName, with: variables.isEmpty ? nil : variables, as: alias, isRender: true, location: location)
    }
    

    

    

}
