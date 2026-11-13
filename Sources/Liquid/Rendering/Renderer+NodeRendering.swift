// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  Renderer+NodeRendering.swift
//  LiquidRenderer
//
//

import Foundation

extension Renderer {
    // MARK: - Node Rendering
    
    internal func renderNode(_ node: ASTNode) async throws -> String {
        try budget.enter()
        defer { budget.activeDepth -= 1 }
        do {
            let output = try await executeNode(node)
            try budget.output(output)
            return output
        } catch let error as RenderError {
            if locateFailures {
                let location: RenderLocation?
                if case .include(_, _, _, _, _, let includeLocation) = node,
               error == .includeDisabled() || error == .illegalIncludeName() {
                    location = includeLocation
                } else {
                    location = node.renderLocation
                }
                recordLocatedFailure(error, location: location)
            }
            guard recoveryEnabled, error.renderErrorCategory != .resource,
                  error.renderErrorCategory != .security else { throw error }
            let location: RenderLocation?
            let diagnosticName: String?
            if case .include(_, _, _, _, _, let includeLocation) = node,
               error == .includeDisabled() || error == .illegalIncludeName() {
                location = includeLocation
                diagnosticName = diagnosticTemplateNameStack.last ?? currentTemplatePath
            } else {
                location = node.renderLocation
                diagnosticName = currentTemplatePath
            }
            let message = error.message
            diagnostics.append(.init(message: message, line: location?.line, templateName: diagnosticName))
            if location?.suppressErrorText == true {
                switch node {
                case .if, .unless, .for:
                    if RenderingContext.isStaticallyBlankBlock([node]) { return "" }
                default:
                    return ""
                }
            }
            if case .undefinedFilter = error { return "" }
            let prefix = location.map { "Liquid error (\(diagnosticName.map { $0 + " " } ?? "")line \($0.line)): " } ?? "Liquid error: "
            let output = prefix + message
            try budget.output(output)
            return output
        }
    }

    internal func executeNode(_ node: ASTNode) async throws -> String {
        switch node {
        case .template(let nodes):
            return try await renderTemplate(nodes)

        case .text(let content):
            return content.string

        case .output(let expression, _):
            return try await renderExpression(expression)

        case .assign(let variable, let value, _):
            return try await renderAssign(variable: variable, value: value)

        case .echo(let expression, _):
            return try await renderExpression(expression)


        case .ifchanged(let nodes):
            let output = try await renderTemplate(nodes)
            if output == lastIfChanged { return "" }
            lastIfChanged = output
            return output
        case .comment:
            return ""

        case .if(let condition, let thenNodes, let elsifBranches, let elseNodes, _):
            return try await renderIf(condition: condition, then: thenNodes, elsif: elsifBranches, else: elseNodes)

        case .unless(let condition, let thenNodes, let elseNodes, _):
            return try await renderUnless(condition: condition, then: thenNodes, else: elseNodes)

        case .case(let value, let branches):
            return try await renderCase(value: value, branches: branches)

        case .for(let variable, let collection, let body, let empty, let params):
            return try await renderFor(variable: variable, collection: collection, body: body, empty: empty, params: params)

        case .tablerow(let variable, let collection, let body, let params):
            return try await renderTableRow(variable: variable, collection: collection, body: body, params: params)

        case .capture(let variable, let body):
            return try await renderCapture(variable: variable, body: body)

        case .increment(let name):
            return try await renderIncrement(name: name)

        case .decrement(let name):
            return try await renderDecrement(name: name)

        case .break:
            throw LoopControlSignal.breakLoop

        case .continue:
            throw LoopControlSignal.continueLoop

        case .cycle(let group, let items, let site):
            return try await renderCycle(group: group, items: items, site: site)

        case .raw(let content):
            return content.string

        case .liquid(let nodes):
            return try await renderTemplate(nodes)

        case .include(let template, let reference, let withVars, let asVar, let isRender, _):
            if isolatedRenderDepth > 0, !isRender {
                throw RenderError.includeDisabled()
            }
            if !isRender, case .legacy = templateLoader {
                let value = systemPrimary(try await evaluateExpression(reference))
                guard let name = value as? String else { throw RenderError.illegalIncludeName() }
                return try await renderInclude(template: InlineString(name), with: withVars, as: asVar, isRender: false, allowContextFallback: false)
            }
            if case .access = reference {
                let value = try await evaluateExpression(reference)
                guard let name = systemPrimary(value) as? String else { throw RenderError.illegalIncludeName() }
                return try await renderInclude(template: InlineString(name), with: withVars, as: asVar, isRender: isRender, allowContextFallback: false)
            }
            if case .literal(.string) = reference {} else if case .variable = reference {} else {
                throw RenderError.illegalIncludeName()
            }
            return try await renderInclude(template: template, with: withVars, as: asVar, isRender: isRender)

        }
    }
    
    internal func renderTemplate(_ nodes: [ASTNode], staticCapacityHint: Int? = nil) async throws -> String {
        switch nodes.count {
        case 0:
            return ""
        case 1:
            return try await renderNode(nodes[0])
        default:
            break
        }

        var output = String()
        let staticCapacity = staticCapacityHint ?? estimatedStaticCapacity(for: nodes)
        if staticCapacity > 0 {
            output.reserveCapacity(staticCapacity)
        }

        for node in nodes {
            try Task.checkCancellation()
            do { output.append(try await renderNode(node)) }
            catch let signal as LoopControlSignal {
                output.append(signal.partialOutput)
                // The root renderer or an isolated render boundary consumes
                // this signal; intermediate blocks must preserve it.
                throw signal.carrying(output)
            }
        }

        return output
    }

    internal func renderSimpleNodeListFast(_ nodes: [ASTNode], staticCapacityHint: Int) async throws -> String {
        if recoveryEnabled { return try await renderTemplate(nodes, staticCapacityHint: staticCapacityHint) }


        switch nodes.count {
        case 0:
            return ""
        case 1:
            switch nodes[0] {
            case .text(let content), .raw(let content):
                return content.string
            case .output(let expression, let location), .echo(let expression, let location):
                do { return try await renderExpressionFast(expression) }
                catch let error as RenderError { recordLocatedFailure(error, location: location); throw error }
            default:
                return try await renderNode(nodes[0])
            }
        case 2:
            var output = String()
            if staticCapacityHint > 0 {
                output.reserveCapacity(staticCapacityHint)
            }
            do { try await appendRenderedSimpleNodePairFast(nodes[0], nodes[1], to: &output) }
            catch let signal as LoopControlSignal { throw signal.carrying(output + signal.partialOutput) }
            return output
        case 3:
            var output = String()
            if staticCapacityHint > 0 {
                output.reserveCapacity(staticCapacityHint)
            }
            do { try await appendRenderedSimpleNodeTripleFast(nodes[0], nodes[1], nodes[2], to: &output) }
            catch let signal as LoopControlSignal { throw signal.carrying(output + signal.partialOutput) }
            return output
        default:
            break
        }

        var output = String()
        if staticCapacityHint > 0 {
            output.reserveCapacity(staticCapacityHint)
        }

        do { try await appendRenderedSimpleNodeListFast(nodes, to: &output) }
        catch let signal as LoopControlSignal { throw signal.carrying(output + signal.partialOutput) }
        return output
    }

    internal func appendRenderedSimpleNodeListFast(_ nodes: [ASTNode], to output: inout String) async throws {
        if recoveryEnabled { output.append(try await renderTemplate(nodes)); return }


        switch nodes.count {
        case 0:
            return
        case 1:
            try await appendRenderedSimpleNodeFast(nodes[0], to: &output)
            return
        case 2:
            try await appendRenderedSimpleNodePairFast(nodes[0], nodes[1], to: &output)
            return
        case 3:
            try await appendRenderedSimpleNodeTripleFast(nodes[0], nodes[1], nodes[2], to: &output)
            return
        default:
            break
        }

        for node in nodes {
            try Task.checkCancellation()
            try await appendRenderedSimpleNodeFast(node, to: &output)
        }
    }

    @inline(__always)
    internal func appendRenderedSimpleNodeFast(_ node: ASTNode, to output: inout String) async throws {
        if recoveryEnabled { output.append(try await renderNode(node)); return }
        switch node {
        case .text(let content), .raw(let content):
            output.append(content.string)
        case .output(let expression, let location), .echo(let expression, let location):
            try await appendLocatedExpressionFast(expression, location: location, to: &output)
        default:
            output.append(try await renderNode(node))
        }
    }

    @inline(__always)
    internal func appendRenderedSimpleNodePairFast(
        _ first: ASTNode,
        _ second: ASTNode,
        to output: inout String
    ) async throws {
        if locateFailures {
            try await appendRenderedSimpleNodeFast(first, to: &output)
            try await appendRenderedSimpleNodeFast(second, to: &output)
            return
        }
        switch (first, second) {
        case (.text(let leading), .text(let trailing)),
             (.text(let leading), .raw(let trailing)),
             (.raw(let leading), .text(let trailing)),
             (.raw(let leading), .raw(let trailing)):
            output.append(leading.string)
            output.append(trailing.string)
            return

        case (.text(let leading), .output(let expression, _)),
             (.text(let leading), .echo(let expression, _)),
             (.raw(let leading), .output(let expression, _)),
             (.raw(let leading), .echo(let expression, _)):
            output.append(leading.string)
            try await appendRenderedExpressionFast(expression, to: &output)
            return

        case (.output(let expression, _), .text(let trailing)),
             (.output(let expression, _), .raw(let trailing)),
             (.echo(let expression, _), .text(let trailing)),
             (.echo(let expression, _), .raw(let trailing)):
            try await appendRenderedExpressionFast(expression, to: &output)
            output.append(trailing.string)
            return

        default:
            break
        }

        try await appendRenderedSimpleNodeFast(first, to: &output)
        try await appendRenderedSimpleNodeFast(second, to: &output)
    }

    @inline(__always)
    internal func appendRenderedSimpleNodeTripleFast(
        _ first: ASTNode,
        _ second: ASTNode,
        _ third: ASTNode,
        to output: inout String
    ) async throws {
        if locateFailures {
            try await appendRenderedSimpleNodeFast(first, to: &output)
            try await appendRenderedSimpleNodeFast(second, to: &output)
            try await appendRenderedSimpleNodeFast(third, to: &output)
            return
        }
        switch (first, second, third) {
        case (.text(let leading), .output(let expression, _), .text(let trailing)),
             (.text(let leading), .output(let expression, _), .raw(let trailing)),
             (.text(let leading), .echo(let expression, _), .text(let trailing)),
             (.text(let leading), .echo(let expression, _), .raw(let trailing)),
             (.raw(let leading), .output(let expression, _), .text(let trailing)),
             (.raw(let leading), .output(let expression, _), .raw(let trailing)),
             (.raw(let leading), .echo(let expression, _), .text(let trailing)),
             (.raw(let leading), .echo(let expression, _), .raw(let trailing)):
            output.append(leading.string)
            try await appendRenderedExpressionFast(expression, to: &output)
            output.append(trailing.string)
            return

        default:
            break
        }

        try await appendRenderedSimpleNodeFast(first, to: &output)
        try await appendRenderedSimpleNodeFast(second, to: &output)
        try await appendRenderedSimpleNodeFast(third, to: &output)
    }

    @inline(__always)
    internal func appendLoopBodyRenderPlanFast(
        _ plan: LoopBodyRenderPlan,
        locations: [RenderLocation?]? = nil,
        to output: inout String
    ) async throws {
        switch plan {
        case .single(let prefix, let expression, let suffix):
            output.append(prefix.string)
            try await appendLocatedExpressionFast(expression, location: locations?.first ?? nil, to: &output)
            output.append(suffix.string)

        case .double(let prefix, let first, let middle, let second, let suffix):
            output.append(prefix.string)
            try await appendLocatedExpressionFast(first, location: locations?.first ?? nil, to: &output)
            output.append(middle.string)
            try await appendLocatedExpressionFast(second, location: (locations?.count ?? 0) > 1 ? locations?[1] : nil, to: &output)
            output.append(suffix.string)
        }
    }

    internal func recordLocatedFailure(_ error: RenderError, location: RenderLocation?) {
        guard locateFailures, !observedFailure, error.renderErrorCategory != .resource,
              error.renderErrorCategory != .security else { return }
        observedFailure = true
        firstFailure = .init(message: error.message, line: location?.hasOriginalSource == true ? location?.line : nil,
                             templateName: diagnosticTemplateNameStack.last ?? currentTemplatePath)
    }

    internal func outputLocations(in nodes: [ASTNode]) -> [RenderLocation?] {
        var result: [RenderLocation?] = []
        for node in nodes {
            switch node {
            case .output(_, let location), .echo(_, let location): result.append(location)
            default: break
            }
        }
        return result
    }

    @inline(__always)
    internal func appendLocatedExpressionFast(_ expression: LiquidExpression, location: RenderLocation?, to output: inout String) async throws {
        guard locateFailures else { try await appendRenderedExpressionFast(expression, to: &output); return }
        do { try await appendRenderedExpressionFast(expression, to: &output) }
        catch let error as RenderError { recordLocatedFailure(error, location: location); throw error }
    }

    @inline(__always)
    internal func appendRenderedExpressionFast(
        _ expression: LiquidExpression,
        to output: inout String
    ) async throws {
        guard !autoEscapeEnabled else {
            output.append(try await renderExpressionFast(expression))
            return
        }

        switch expression {
        case .literal(let value):
            try appendStringifiedUnescapedValueFast(try evaluateValue(value), to: &output)

        case .variable(let name):
            try appendStringifiedUnescapedValueFast(context.getVariable(name.string) ?? NSNull(), to: &output)

        case .access:
            if !systemContextEnabled, let path = expression.staticVariablePath {
                try appendStringifiedUnescapedValueFast(context.getVariable(path) ?? NSNull(), to: &output)
            } else {
                output.append(try await renderExpressionFast(expression))
            }

        case .filtered:
            output.append(try await renderExpressionFast(expression))

        default:
            output.append(try await renderExpressionFast(expression))
        }
    }

    @inline(__always)
    internal func appendStringifiedUnescapedValueFast(_ value: Any, to output: inout String) throws {
        let value = systemPrimary(value)
        switch value {
        case let str as String:
            output.append(str)
        case let inline as InlineString:
            output.append(inline.string)
        case let safeHTML as SafeHTML:
            output.append(safeHTML.value)
        case let num as Double:
            output.append(formatDouble(num))
        case let num as Int:
            output.append(String(num))
        case let bool as Bool:
            output.append(bool ? "true" : "false")
        case let number as NSNumber:
            output.append(
                number.doubleValue == floor(number.doubleValue)
                    ? String(number.intValue)
                    : String(number.doubleValue)
            )
        case is NSNull:
            return
        case is [Any], is RuntimeObject, is [String: Any]:
            output.append(try renderStringify(value))
        default:
            output.append(String(describing: value))
        }
    }

    @inline(__always)
    internal func renderNodeListFast(_ nodes: [ASTNode], staticCapacityHint: Int? = nil) async throws -> String {
        let staticCapacity = staticCapacityHint ?? estimatedStaticCapacity(for: nodes)
        return try await renderSimpleNodeListFast(nodes, staticCapacityHint: staticCapacity)
    }

    @inline(__always)
    internal func estimatedStaticCapacity(for nodes: [ASTNode]) -> Int {
        var total = 0
        for node in nodes {
            switch node {
            case .text(let content), .raw(let content):
                total += content.utf8Count
            default:
                continue
            }
        }
        return total
    }

    internal func bodyNeedsImplicitLoopObject(named variableName: String, nodes: [ASTNode]) -> Bool {
        var stack = nodes

        while let node = stack.popLast() {
            switch node {
            case .include:
                return true

            default:
                break
            }

            for expression in node.expressions {
                if expressionReferencesVariable(expression, named: variableName) {
                    return true
                }
            }

            stack.append(contentsOf: node.children)
        }

        return false
    }

    internal func expressionReferencesVariable(_ expression: LiquidExpression, named variableName: String) -> Bool {
        switch expression {
        case .literal:
            return false

        case .variable(let name):
            let nameString = name.string
            return nameString == variableName || nameString.hasPrefix(variableName + ".")

        case .binary(let left, _, let right):
            return expressionReferencesVariable(left, named: variableName)
                || expressionReferencesVariable(right, named: variableName)

        case .unknownCondition(let left, _, let right):
            return expressionReferencesVariable(left, named: variableName)
                || expressionReferencesVariable(right, named: variableName)

        case .unary(_, let expr):
            return expressionReferencesVariable(expr, named: variableName)

        case .range(let start, let end):
            return expressionReferencesVariable(start, named: variableName)
                || expressionReferencesVariable(end, named: variableName)

        case .filtered(let expr, let filters):
            if expressionReferencesVariable(expr, named: variableName) {
                return true
            }
            for filter in filters {
                for argument in filter.arguments where expressionReferencesVariable(argument, named: variableName) {
                    return true
                }
                for argument in filter.namedArguments where expressionReferencesVariable(argument.value, named: variableName) {
                    return true
                }
            }
            return false

        case .test(let expr, _):
            return expressionReferencesVariable(expr, named: variableName)

        case .access(let expr, let key, _):
            return expressionReferencesVariable(expr, named: variableName)
                || expressionReferencesVariable(key, named: variableName)

        case .systemAccess(let expr, _):
            return expressionReferencesVariable(expr, named: variableName)

        case .call(_, let arguments):
            for argument in arguments where expressionReferencesVariable(argument.value, named: variableName) {
                return true
            }
            return false
        }
    }

    internal func expressionToPath(_ expression: LiquidExpression) -> String {
        switch expression {
        case .variable(let name):
            return name.string
        case .access(let base, let key, _):
            let basePath = expressionToPath(base)
            switch key {
            case .literal(.string(let keyName)):
                return basePath.isEmpty ? keyName.string : "\(basePath).\(keyName.string)"
            case .literal(.number(let num, _)):
                return "\(basePath)[\(integerValue(num).map(String.init) ?? String(num))]"
            default:
                return basePath
            }
        case .range(let start, let end):
            let startStr = expressionToPathForRange(start)
            let endStr = expressionToPathForRange(end)
            return "(\(startStr)..\(endStr))"
        case .literal(.integer(let number)): return String(number)
        case .literal(.number(let num, _)):
            return integerValue(num).map(String.init) ?? String(num)
        case .literal(.string(let s)):
            return s.string
        default:
            return String(describing: expression)
        }
    }

    internal func expressionToPathForRange(_ expression: LiquidExpression) -> String {
        if case .literal(.number(let num, _)) = expression {
            return integerValue(num).map(String.init) ?? String(num)
        }
        return expressionToPath(expression)
    }

    @inline(__always)


    internal func prepareASTForRendering(_ node: ASTNode) async throws -> ASTNode {
        return node
    }

    internal var currentTemplatePath: String? {
        templatePathStack.last
    }

    internal func resetTemplatePathStack() {
        diagnosticTemplateNameStack.removeAll(keepingCapacity: true)
        if !templatePathStack.isEmpty {
            templatePathStack.removeAll(keepingCapacity: true)
        }

        if let rootTemplatePath {
            templatePathStack.append(rootTemplatePath)
        }
    }



    internal func mapTemplateLoaderError(_ error: TemplateLoaderError, template: String) -> RenderError {
        switch error {
        case .templateNotFound(let path):
            return .templateNotFound(path)
        case .pathTraversal(let detail), .absolutePathNotAllowed(let detail):
            return .accessDenied(detail)
        case .invalidPath(let detail), .invalidExtension(let detail), .ioError(let detail):
            return .includeError(template, reason: detail)
        }
    }

    internal func withAuthoringScope<T>(
        for node: ASTNode,
        templatePath: String?,
        operation: () async throws -> T
    ) async throws -> T {
        return try await operation()
    }










    
    internal func renderAssign(variable: InlineString, value: LiquidExpression) async throws -> String {
        let evaluatedValue = try await evaluateExpression(value)
        // Shopify Liquid: assign always sets at root scope so variables persist after loops/blocks
        context.setRootVariable(variable.string, value: evaluatedValue)
        return "" // Assign produces no output
    }
}
