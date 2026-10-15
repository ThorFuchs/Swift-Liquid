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
    private let syntaxMode: LiquidSyntaxMode
    private let lineOffset: Int
    private let maxNestingDepth: Int
    private var parseDepth = 0

    
    private var current: Int = 0

    private var currentTokenStorage: Token

    private var nextTokenStorage: Token




    
    // MARK: - Initialization
    
    internal init(
        consuming tokens: [Token],
        source: String? = nil,
        syntaxMode: LiquidSyntaxMode = .lax,
        maxNestingDepth: Int = 64,
        lineOffset: Int = 0
    ) {
        self.tokens = tokens
        self.source = source
        self.syntaxMode = syntaxMode
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
        
        while !isAtEnd {
            let node = try parseNode()
            nodes.append(node)
        }
        
        return .template(nodes)
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
        
        let expression = try parseExpression()
        
        guard currentTokenStorage.type == .variableEnd else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance() // consume }}
        
        return .output(expression, location: .init(line: line, suppressErrorText: false))
    }
    
    @inline(__always)
    private func parseTag() throws ->ASTNode {
        advance() // consume {%

        let tagToken = currentTokenStorage
        advance()

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
        default:
            throw ParserError.unexpectedToken(tagToken)
        }
    }

    @inline(__always)
    private func parseIdentifierTag(named name: InlineString) throws ->ASTNode {
        if name.equals("doc") {
            try consumeTagEnd()
            guard currentTagMatchesIdentifier("enddoc") else { throw ParserError.unclosedTag("doc") }
            advance(); advance(); try consumeTagEnd()
            return .comment
        }
        if name.equals("ifchanged") {
            try consumeTagEnd()
            var nodes: [ASTNode] = []
            while !isAtEnd && !currentTagMatchesIdentifier("endifchanged") { nodes.append(try parseNode()) }
            guard !isAtEnd else { throw ParserError.unclosedTag("ifchanged") }
            advance(); advance(); try consumeTagEnd()
            return .ifchanged(nodes)
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
        if syntaxMode == .strict2 {
            if case .identifier(let name) = currentToken.type, name.string.first?.isNumber == true { throw ParserError.expectedIdentifier }
            if case .number = currentToken.type { throw ParserError.expectedIdentifier }
        }
        let variableName: InlineString
        if case .identifier(let name) = currentToken.type {
            // Trailing '?' is not allowed in assignment targets (Shopify behavior)
            if name.string.hasSuffix("?") {
                throw ParserError.unexpectedToken(currentToken)
            }
            variableName = name
        } else if case .number(let num, _) = currentToken.type {
            // Digit-only variable names: {% assign 123 = 'hello' %}
            variableName = InlineString(String(Int(num)))
        } else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        
        guard currentToken.type == .equals else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        
        let value = try parseExpression()
        try consumeTagEnd()
        
        return .assign(variable: variableName, value: value, location: .init(line: line, suppressErrorText: syntaxMode != .strict2))
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

        return .echo(expression: expression, location: .init(line: line, suppressErrorText: false))
    }
    
    private func parseCommentTag() throws ->ASTNode {
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
            throw ParserError.unexpectedToken(currentToken)
        }
        advance() // consume {%
        try consumeTagKeyword(.endcomment, identifier: "endcomment")
        try consumeTagEnd()

        return .comment
    }














    
    // MARK: - Control Flow Tag Parsing
    
    private func parseIfTag() throws ->ASTNode {
        let condition = try parseComplexExpression()
        try consumeTagEnd()
        
        var thenNodes = makeNodeBuffer()
        var elsifBranches: [(LiquidExpression, [ASTNode])] = []
        var elseNodes: [ASTNode]? = nil
        
        // Parse then branch
        while !isAtEnd && !isElsifOrElseOrEndif() {
            thenNodes.append(try parseNode())
        }
        
        // Parse elsif branches
        while !isAtEnd && currentTagMatches(.elsif, identifier: "elsif") {
            advance() // consume {%
            try consumeTagKeyword(.elsif, identifier: "elsif")
            
            let elsifCondition = try parseComplexExpression()
            try consumeTagEnd()
            
            var elsifNodes = makeNodeBuffer()
            while !isAtEnd && !isElsifOrElseOrEndif() {
                elsifNodes.append(try parseNode())
            }
            
            elsifBranches.append((elsifCondition, elsifNodes))
        }
        
        // Parse else branch if present
        if !isAtEnd && currentTagMatches(.else, identifier: "else") {
            advance() // consume {%
            try consumeTagKeyword(.else, identifier: "else")
            // Shopify Liquid ignores expressions on else tags (e.g., {% else nonsense %})
            while currentToken.type != .tagEnd && !isAtEnd { advance() }
            try consumeTagEnd()

            var elseNodesList = makeNodeBuffer()
            while !isAtEnd && !isElsifOrElseOrEndif() {
                elseNodesList.append(try parseNode())
            }
            elseNodes = elseNodesList
        }

        // Shopify Liquid silently ignores extra elsif/else blocks after the first else
        while !isAtEnd && (currentTagMatches(.elsif, identifier: "elsif") || currentTagMatches(.else, identifier: "else")) {
            advance() // consume {%
            advance() // consume elsif/else keyword
            while currentToken.type != .tagEnd && !isAtEnd { advance() }
            try consumeTagEnd()
            // Skip body nodes until next elsif/else/endif
            while !isAtEnd && !isElsifOrElseOrEndif() {
                _ = try parseNode()
            }
        }

        // Consume endif
        guard currentTagMatches(.endif, identifier: "endif") else {
            throw ParserError.unexpectedToken(currentToken) // Missing endif
        }
        advance() // consume {%
        try consumeTagKeyword(.endif, identifier: "endif")
        try consumeTagEnd()
        
        return .if(
            condition: condition,
            then: thenNodes,
            elsif: elsifBranches,
            else: elseNodes
        )
    }
    
    private func parseUnlessTag() throws ->ASTNode {
        let condition = try parseComplexExpression()
        try consumeTagEnd()

        var thenNodes = makeNodeBuffer()
        var elsifBranches: [(LiquidExpression, [ASTNode])] = []
        var elseNodes: [ASTNode]? = nil

        // Parse then branch (unless body)
        while !isAtEnd && !isElseOrEndunless() {
            thenNodes.append(try parseNode())
        }

        // Parse elsif branches
        while !isAtEnd && currentTagMatches(.elsif, identifier: "elsif") {
            advance() // consume {%
            try consumeTagKeyword(.elsif, identifier: "elsif")
            let elsifCondition = try parseComplexExpression()
            try consumeTagEnd()

            var elsifNodes = makeNodeBuffer()
            while !isAtEnd && !isElseOrEndunless() {
                elsifNodes.append(try parseNode())
            }
            elsifBranches.append((elsifCondition, elsifNodes))
        }

        // Parse else branch if present
        if !isAtEnd && currentTagMatches(.else, identifier: "else") {
            advance() // consume {%
            try consumeTagKeyword(.else, identifier: "else")
            while currentToken.type != .tagEnd && !isAtEnd { advance() }
            try consumeTagEnd()

            var elseNodesList = makeNodeBuffer()
            while !isAtEnd && !isElseOrEndunless() {
                elseNodesList.append(try parseNode())
            }
            elseNodes = elseNodesList
        }

        // Silently ignore extra elsif/else blocks after the first else
        while !isAtEnd && (currentTagMatches(.elsif, identifier: "elsif") || currentTagMatches(.else, identifier: "else")) {
            advance()
            advance()
            while currentToken.type != .tagEnd && !isAtEnd { advance() }
            try consumeTagEnd()
            while !isAtEnd && !isElseOrEndunless() {
                _ = try parseNode()
            }
        }

        // Consume endunless
        guard currentTagMatches(.endunless, identifier: "endunless") else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        try consumeTagKeyword(.endunless, identifier: "endunless")
        try consumeTagEnd()

        // If there are elsif branches, convert to if(NOT condition) structure
        if !elsifBranches.isEmpty {
            return .if(
                condition: .unary(op: .not, expr: condition),
                then: thenNodes,
                elsif: elsifBranches,
                else: elseNodes
            )
        }

        return .unless(
            condition: condition,
            then: thenNodes,
            else: elseNodes
        )
    }
    
    // MARK: - LiquidExpression Parsing
    
    private func parseConditionOperand() throws -> LiquidExpression {
        let value = try parsePrimaryExpression()
        if currentToken.type == .filter {
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

        guard case .identifier(let firstFilterName) = currentTokenStorage.type else {
            throw ParserError.unexpectedToken(currentToken)
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

            guard case .identifier(let filterName) = currentTokenStorage.type else {
                throw ParserError.unexpectedToken(currentToken)
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
        } while true
        return arguments
    }

    @inline(__always)
    private func parsePrimaryExpression() throws ->LiquidExpression {
        guard parseDepth < maxNestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
        parseDepth += 1
        defer { parseDepth -= 1 }
        switch currentToken.type {
        case .empty:
            return try parseNamedPrimary(InlineString("empty"))
        case .identifier(let name):
            return try parseNamedPrimary(name)

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
                        throw ParserError.unexpectedToken(currentToken)
                    }
                    advance()
                    expr = .access(expr: expr, key: .literal(.string(prop)))
                }
                startExpr = expr
            } else {
                throw ParserError.unexpectedToken(currentToken)
            }

            guard currentToken.type == .range else {
                throw ParserError.unexpectedToken(currentToken)
            }
            advance() // consume ..

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
                        throw ParserError.unexpectedToken(currentToken)
                    }
                    advance()
                    expr = .access(expr: expr, key: .literal(.string(prop)))
                }
                endExpr = expr
            } else {
                throw ParserError.unexpectedToken(currentToken)
            }

            guard currentToken.type == .rightParen else {
                throw ParserError.unexpectedToken(currentToken)
            }
            advance() // consume )

            return .range(start: startExpr, end: endExpr)
            
        case .leftBracket:
            // Shopify strict2 requires an explicit receiver for bracket access.
            // Older parser modes retain their indirect root lookup semantics.
            if syntaxMode == .strict2 {
                throw LiquidError.syntax(
                    message: "Bare bracket access is not allowed. Use self['...'] instead",
                    line: currentToken.line + lineOffset,
                    column: currentToken.column
                )
            }
            // Top-level bracket access: {{ [something] }} or {{ ["key"] }}
            // This is an indirect variable lookup: look up the bracket contents,
            // then use the result to look up in the root context
            advance() // consume [
            let keyExpr = try parsePrimaryExpression()
            guard currentToken.type == .rightBracket else {
                throw ParserError.expectedToken(.rightBracket, got: currentToken.type)
            }
            advance() // consume ]

            // Build as access on a special "root" sentinel,
            // but since Liquid treats [x] as context[context[x]],
            // we model it as a variable access with the key expression
            var expr: LiquidExpression = .access(expr: .variable(InlineString("")), key: keyExpr)

            // Handle chained bracket/dot access after: [x][0], [x].prop
            while currentTokenStorage.type == .leftBracket {
                advance()
                let nextKey = try parsePrimaryExpression()
                guard currentToken.type == .rightBracket else {
                    throw ParserError.expectedToken(.rightBracket, got: currentToken.type)
                }
                advance()
                expr = .access(expr: expr, key: nextKey)
            }
            while currentTokenStorage.type == .dot {
                advance()
                guard case .identifier(let prop) = currentToken.type else {
                    throw ParserError.unexpectedToken(currentToken)
                }
                advance()
                expr = .access(expr: expr, key: .literal(.string(prop)))
            }
            return expr

        // Allow reserved words as variable names in expression context
        case .include, .for, .if, .elsif, .else, .unless, .case, .when,
             .comment, .raw, .capture, .tablerow, .cycle:
            let name = InlineString(currentToken.type.keywordString ?? "")
            advance()
            var expr: LiquidExpression = .variable(name)
            // Handle dot access chains: include.menu
            var hasMoreAccess = true
            while hasMoreAccess {
                hasMoreAccess = false
                while currentTokenStorage.type == .leftBracket {
                    advance()
                    let keyExpr = try parsePrimaryExpression()
                    guard currentToken.type == .rightBracket else {
                        throw ParserError.expectedToken(.rightBracket, got: currentToken.type)
                    }
                    advance()
                    expr = .access(expr: expr, key: keyExpr)
                    hasMoreAccess = true
                }
                while currentTokenStorage.type == .dot {
                    advance()
                    guard case .identifier(let prop) = currentToken.type else {
                        throw ParserError.unexpectedToken(currentToken)
                    }
                    advance()
                    expr = .access(expr: expr, key: .literal(.string(prop)))
                    hasMoreAccess = true
                }
            }
            return expr

        default:
            throw ParserError.unexpectedToken(currentToken)
        }
    }

    private func collectQualifiedIdentifierComponents(
        startingWith first: InlineString
    ) throws ->[InlineString] {
        var components = [first]
        components.reserveCapacity(2)

        while currentTokenStorage.type == .dot {
            guard case .identifier(let property) = nextTokenStorage.type else {
                throw ParserError.unexpectedToken(nextTokenStorage)
            }
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

    private func parseCallArguments() throws ->[CallArgument] {
        guard currentToken.type != .rightParen else {
            return []
        }

        var arguments: [CallArgument] = []
        arguments.reserveCapacity(2)
        var seenLabels = Set<String>()

        while currentToken.type != .rightParen {
            if case .identifier(let label) = currentToken.type,
               nextTokenStorage.type == .colon {
                if !seenLabels.insert(label.string).inserted {
                    throw ParserError.duplicateParameter(label.string)
                }
                advance()
                advance()
                arguments.append(CallArgument(label: label, value: try parseExpression()))
            } else {
                arguments.append(CallArgument(value: try parseExpression()))
            }

            guard currentToken.type == .comma || currentToken.type == .rightParen else {
                throw ParserError.unexpectedToken(currentToken)
            }

            if currentToken.type == .comma {
                advance()
            }
        }

        return arguments
    }







    @inline(__always)
    private func parseNamedPrimary(_ name: InlineString) throws -> LiquidExpression {
            advance()

            if currentTokenStorage.type != .dot, currentTokenStorage.type != .leftBracket,
               let literal = literalExpression(for: name) {
                return literal
            }

            let components = try collectQualifiedIdentifierComponents(startingWith: name)

            if currentTokenStorage.type == .leftParen {
                advance()
                let arguments = try parseCallArguments()
                guard currentToken.type == .rightParen else {
                    throw ParserError.expectedToken(.rightParen, got: currentToken.type)
                }
                advance()
                return .call(
                    name: InlineString(components.map(\.string).joined(separator: ".")),
                    arguments: arguments
                )
            }

            var expr: LiquidExpression = .variable(name)
            for property in components.dropFirst() {
                expr = .access(expr: expr, key: .literal(.string(property)))
            }

            // Handle bracket and dot access chains: items[0], items["key"].prop, items[0][1]
            var hasMoreAccess = true
            while hasMoreAccess {
                hasMoreAccess = false
                while currentTokenStorage.type == .leftBracket {
                    advance() // consume [
                    let keyExpr = try parsePrimaryExpression()
                    guard currentToken.type == .rightBracket else {
                        throw ParserError.expectedToken(.rightBracket, got: currentToken.type)
                    }
                    advance() // consume ]
                    expr = .access(expr: expr, key: keyExpr)
                    hasMoreAccess = true
                }
                // Handle dot access after brackets: items[0].title
                while currentTokenStorage.type == .dot {
                    guard case .identifier(let prop) = nextTokenStorage.type else { break }
                    advance() // consume .
                    advance() // consume identifier
                    expr = .access(expr: expr, key: .literal(.string(prop)))
                    hasMoreAccess = true
                }
            }

            return expr
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
    
    @inline(__always)
    private func consumeTagEnd() throws {
        guard currentTokenStorage.type == .tagEnd else {
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
    
    private func parseCaseTag() throws ->ASTNode {
        let expression = try parseExpression()
        try consumeTagEnd()
        
        var branches: [(LiquidExpression?, [ASTNode])] = []
        branches.reserveCapacity(4)
        var defaultBranch: [ASTNode]? = nil
        
        // Parse all branches: when, else, and mixed when/else blocks
        // Skip whitespace before first branch
        while !isAtEnd && currentToken.type != .tagStart {
            advance()
        }

        while !isAtEnd && !currentTagMatches(.endcase, identifier: "endcase") {
            if currentTagMatches(.when, identifier: "when") {
                try parseCaseWhenBranch(into: &branches)
            } else if currentTagMatches(.else, identifier: "else") {
                advance() // consume {%
                try consumeTagKeyword(.else, identifier: "else")
                try consumeTagEnd()

                var elseNodes = makeNodeBuffer()
                while !isAtEnd && !isWhenOrElseOrEndcase() {
                    elseNodes.append(try parseNode())
                }
                // Store else as nil-expression branch
                branches.append((nil, elseNodes))
                if defaultBranch == nil {
                    defaultBranch = elseNodes
                }
            } else {
                // Skip whitespace/text between branches
                advance()
            }
        }

        guard currentTagMatches(.endcase, identifier: "endcase") else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance() // consume {%
        try consumeTagKeyword(.endcase, identifier: "endcase")
        try consumeTagEnd()

        // Convert branches to AST format
        // Else branches use .literal(.null) as sentinel expression
        let allBranches: [(LiquidExpression, [ASTNode])] = branches.map { (value, nodes) in
            if let value { return (value, nodes) }
            return (.literal(.null), nodes) // sentinel for else
        }

        // If we have sentinel else branches in allBranches, don't also pass defaultBranch
        // to avoid double-rendering
        let hasSentinelElse = branches.contains { $0.0 == nil }
        return .case(value: expression, whens: allBranches, else: hasSentinelElse ? nil : defaultBranch)
    }
    
    private func parseCaseWhenBranch(into branches: inout [(LiquidExpression?, [ASTNode])]) throws {
        advance() // consume {%
        try consumeTagKeyword(.when, identifier: "when")

        var whenValues = makeExpressionBuffer()
        whenValues.append(try parseExpression())

        // Parse comma/or/and separated values
        // 'and' in when expressions invalidates the entire when clause (Shopify behavior)
        var hasInvalidAnd = false
        while currentToken.type == .comma || currentToken.type == .or || currentToken.type == .and {
            if currentToken.type == .and { hasInvalidAnd = true }
            advance()
            whenValues.append(try parseExpression())
        }
        if hasInvalidAnd {
            if syntaxMode == .strict2 { throw ParserError.invalidParameterValue("when", expected: "comma or or") }
            whenValues.removeAll()
        }

        try consumeTagEnd()

        var whenNodes = makeNodeBuffer()
        while !isAtEnd && !isWhenOrElseOrEndcase() {
            whenNodes.append(try parseNode())
        }
        for value in whenValues {
            branches.append((value, whenNodes))
        }
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
    
    private func parseForTag() throws ->ASTNode {
        guard case .identifier(let variable) = currentToken.type else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        
        guard currentToken.type == .in else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        
        let collection = try parseExpression()
        
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
                } else if case .variable = value {
                    // Variable reference — store expression for runtime evaluation
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

        let params = ForParams(limit: limit, offset: offset, offsetContinue: offsetContinue, reversed: reversed, limitExpression: limitExpression, offsetExpression: offsetExpression)
        
        try consumeTagEnd()
        
        // Parse loop body
        var body = makeNodeBuffer()
        
        while !isAtEnd && !isEmptyOrEndfor() {
            body.append(try parseNode())
        }
        
        // Parse empty/else branch if present (for empty collections)
        // Supports both {% empty %} and {% else %} (Shopify-compatible)
        var emptyBranch: [ASTNode]? = nil
        if !isAtEnd && currentTagMatches(.else, identifier: "else") {
            let isElseForm = currentTagMatches(.else, identifier: "else")
            advance() // consume {%
            if isElseForm {
                try consumeTagKeyword(.else, identifier: "else")
            } else {
                try consumeTagKeyword(.empty, identifier: "empty")
            }
            try consumeTagEnd()
            
            var emptyNodes = makeNodeBuffer()
            while !isAtEnd && !isEndfor() {
                emptyNodes.append(try parseNode())
            }
            emptyBranch = emptyNodes
        }
        
        // Consume endfor
        guard currentTagMatches(.endfor, identifier: "endfor") else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance() // consume {%
        try consumeTagKeyword(.endfor, identifier: "endfor")
        try consumeTagEnd()
        
        return .for(variable: variable, in: collection, body: body, empty: emptyBranch, params: params)
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
    
    private func parseTableRowTag() throws ->ASTNode {
        guard case .identifier(let variable) = currentToken.type else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        
        guard currentToken.type == .in else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        
        let collection = try parseExpression()
        
        // Parse optional parameters
        var cols: Int? = nil
        var limit: Int? = nil
        var offset: Int? = nil
        
        while let paramName = peekIdentifierName() {
            guard paramName.equals("cols")
                    || paramName.equals("limit")
                    || paramName.equals("offset") else {
                break
            }

            advance() // consume parameter name
            
            guard currentToken.type == .colon else {
                throw ParserError.unexpectedToken(currentToken)
            }
            advance()
            
            let value = try parsePrimaryExpression()

            if case .literal(let literal) = value, let num = literal.parameterInteger {
                if paramName.equals("cols") {
                    cols = Int(num)
                } else if paramName.equals("limit") {
                    limit = Int(num)
                } else if paramName.equals("offset") {
                    offset = Int(num)
                }
            } else if case .literal(.string(let str)) = value {
                if let intVal = Int(str.string) {
                    if paramName.equals("cols") { cols = intVal }
                    else if paramName.equals("limit") { limit = intVal }
                    else if paramName.equals("offset") { offset = intVal }
                }
            }
        }

        let params = TableRowParams(cols: cols, limit: limit, offset: offset)
        try consumeTagEnd()
        
        // Parse tablerow body
        var body = makeNodeBuffer()
        while !isAtEnd && !isEndtablerow() {
            body.append(try parseNode())
        }
        
        // Consume endtablerow
        guard currentTagMatches(.endtablerow, identifier: "endtablerow") else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance() // consume {%
        try consumeTagKeyword(.endtablerow, identifier: "endtablerow")
        try consumeTagEnd()
        
        return .tablerow(variable: variable, in: collection, body: body, params: params)
    }
    
    private func parseCaptureTag() throws ->ASTNode {
        let variable: InlineString
        if case .identifier(let name) = currentToken.type {
            variable = name
        } else if case .number(let num, _) = currentToken.type {
            // Digit-only variable names: {% capture 123 %}
            variable = InlineString(String(Int(num)))
        } else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        try consumeTagEnd()
        
        var body = makeNodeBuffer()
        while !isAtEnd && !currentTagMatches(.endcapture, identifier: "endcapture") {
            body.append(try parseNode())
        }
        
        // Consume endcapture
        guard currentTagMatches(.endcapture, identifier: "endcapture") else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance() // consume {%
        try consumeTagKeyword(.endcapture, identifier: "endcapture")
        try consumeTagEnd()
        
        return .capture(variable: variable, body: body)
    }
    
    private func parseIncrementTag() throws ->ASTNode {
        guard case .identifier(let counter) = currentToken.type else {
            throw ParserError.unexpectedToken(currentToken)
        }
        advance()
        try consumeTagEnd()
        
        return .increment(name: counter)
    }
    
    private func parseDecrementTag() throws ->ASTNode {
        guard case .identifier(let counter) = currentToken.type else {
            throw ParserError.unexpectedToken(currentToken)
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
        try consumeTagEnd()

        // If we have the original source, extract raw content verbatim
        if let source {
            let rawStartPosition = tagEndToken.position + 2 // after %} (position is already past any trim marker)

            // Skip tokens until we find {% endraw %}
            while !isAtEnd && !currentTagMatches(.endraw, identifier: "endraw") {
                advance()
            }

            guard currentTagMatches(.endraw, identifier: "endraw") else {
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
            nestedTokens = try Lexer(rewrittenTemplate).tokenize()
        } catch {
            throw ParserError.unsupportedFeature("Lexer error in liquid tag body: \(error)")
        }
        let nestedParser = Parser(
            consuming: nestedTokens,
            source: rewrittenTemplate,
            syntaxMode: syntaxMode,
            maxNestingDepth: maxNestingDepth,
            lineOffset: lineOffset + markupLine - 1
        )
        let nestedAST = try nestedParser.parse()

        guard case .template(let nodes) = nestedAST else {
            return .liquid(body: [])
        }

        return .liquid(body: normalizeLiquidBodyNodes(nodes))
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

    private func normalizeLiquidBodyNodes(_ nodes: [ASTNode]) -> [ASTNode] {
        nodes.compactMap(normalizeLiquidBodyNode)
    }

    private func normalizeLiquidBodyNode(_ node: ASTNode) -> ASTNode? {
        switch node {
        case .text(let text):
            let trimmed = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : node
        case .template(let nodes):
            return .template(normalizeLiquidBodyNodes(nodes))
        case .if(let condition, let thenNodes, let elsifBranches, let elseNodes):
            return .if(
                condition: condition,
                then: normalizeLiquidBodyNodes(thenNodes),
                elsif: elsifBranches.map { condition, branch in
                    (condition, normalizeLiquidBodyNodes(branch))
                },
                else: elseNodes.map(normalizeLiquidBodyNodes)
            )
        case .unless(let condition, let thenNodes, let elseNodes):
            return .unless(
                condition: condition,
                then: normalizeLiquidBodyNodes(thenNodes),
                else: elseNodes.map(normalizeLiquidBodyNodes)
            )
        case .case(let value, let whens, let elseBranch):
            return .case(
                value: value,
                whens: whens.map { value, branch in
                    (value, normalizeLiquidBodyNodes(branch))
                },
                else: elseBranch.map(normalizeLiquidBodyNodes)
            )
        case .for(let variable, let collection, let body, let empty, let params):
            return .for(
                variable: variable,
                in: collection,
                body: normalizeLiquidBodyNodes(body),
                empty: empty.map(normalizeLiquidBodyNodes),
                params: params
            )
        case .tablerow(let variable, let collection, let body, let params):
            return .tablerow(
                variable: variable,
                in: collection,
                body: normalizeLiquidBodyNodes(body),
                params: params
            )
        case .capture(let variable, let body):
            return .capture(variable: variable, body: normalizeLiquidBodyNodes(body))
        case .ifchanged(let body):
            return .ifchanged(normalizeLiquidBodyNodes(body))
        default:
            return node
        }
    }
    
    private func parseCycleTag() throws ->ASTNode {
        var values = makeExpressionBuffer(initialCapacity: 4)

        // Parse first value — might be a group name followed by ':'
        let firstExpr = try parsePrimaryExpression()

        // Check for named cycle: {% cycle name: val1, val2 %}
        var group: LiquidExpression? = nil
        if currentToken.type == .colon {
            advance() // consume ':'
            group = firstExpr
            // Parse actual cycle values
            values.append(try parsePrimaryExpression())
        } else {
            values.append(firstExpr)
        }

        // Parse remaining values
        while currentToken.type == .comma {
            advance() // consume comma
            values.append(try parsePrimaryExpression())
        }

        try consumeTagEnd()
        return .cycle(group: group, items: values)
    }
    
    private func parseIncludeTag() throws ->ASTNode {
        let templateName = try parsePrimaryExpression()
        let templateStr: InlineString
        if case .literal(.string(let name)) = templateName {
            templateStr = name
        } else if case .variable(let name) = templateName {
            // Support include with variable name: {% include my_template %}
            templateStr = name
        } else {
            throw ParserError.expectedString
        }

        var variables: [String: LiquidExpression] = [:]
        variables.reserveCapacity(4)
        var alias: InlineString? = nil

        // Skip optional comma after template name
        if currentToken.type == .comma { advance() }

        // Parse optional variable assignments
        while currentToken.type != .tagEnd {
            if currentToken.type == .for {
                // {% include 'template' for collection %} — iterate over collection
                advance() // consume 'for'
                let expr = try parseExpression()
                variables["_for"] = expr
                // Skip optional comma
                if currentToken.type == .comma { advance() }
            } else if case .identifier(let varName) = currentToken.type {
                advance()

                guard currentToken.type == .colon else {
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
                        throw ParserError.unexpectedToken(currentToken)
                    }
                    alias = aliasName
                    advance()
                }
            } else {
                throw ParserError.unexpectedToken(currentToken)
            }
        }

        try consumeTagEnd()
        return .include(template: templateStr, reference: templateName, with: variables.isEmpty ? nil : variables, as: alias)
    }
    
    private func parseRenderTag() throws ->ASTNode {
        // Similar to include but with isolated scope
        let templateName = try parsePrimaryExpression()
        let templateStr: InlineString
        if case .literal(.string(let name)) = templateName {
            templateStr = name
        } else {
            throw ParserError.expectedString
        }

        var variables: [String: LiquidExpression] = [:]
        variables.reserveCapacity(4)
        var alias: InlineString? = nil

        // Skip optional comma after template name
        if currentToken.type == .comma { advance() }

        // Parse optional variable assignments
        while currentToken.type != .tagEnd {
            if case .identifier(let varName) = currentToken.type {
                advance()
                
                guard currentToken.type == .colon else {
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
                        throw ParserError.unexpectedToken(currentToken)
                    }
                    alias = aliasName
                    advance()
                }
            } else if currentToken.type == .for {
                advance()
                let expr = try parsePrimaryExpression()
                variables["_for"] = expr
                if case .identifier(let keyword) = currentToken.type, keyword.equals("as") {
                    advance()
                    guard case .identifier(let aliasName) = currentToken.type else {
                        throw ParserError.unexpectedToken(currentToken)
                    }
                    alias = aliasName
                    advance()
                }
            } else {
                throw ParserError.unexpectedToken(currentToken)
            }
        }
        
        try consumeTagEnd()
        // The render tag doesn't exist in the current AST, use include with isolated scope marker.
        var renderVars = variables
        renderVars["__render_isolated__"] = .literal(.boolean(true))
        
        return .include(template: templateStr, reference: templateName, with: renderVars, as: alias)
    }
    

    

    

}
