// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  Renderer+ControlFlow.swift
//  LiquidRenderer
//
//

import Foundation

extension Renderer {
    // MARK: - Control Flow Rendering

    internal func renderIf(condition: LiquidExpression, then thenNodes: [ASTNode], elsif elsifBranches: [(LiquidExpression, [ASTNode])], else elseNodes: [ASTNode]?) async throws -> String {
        if elsifBranches.isEmpty {
            let conditionValue = try await evaluateExpression(condition)
            if isTruthy(conditionValue) {
                let result = try await renderNodeListFast(thenNodes)
                if result.allSatisfy(\.isWhitespace), RenderingContext.isStaticallyBlankBlock(thenNodes),
                   (elseNodes == nil || RenderingContext.isStaticallyBlankBlock(elseNodes!)) {
                    return ""
                }
                return result
            }

            if let elseNodes = elseNodes {
                let result = try await renderNodeListFast(elseNodes)
                if result.allSatisfy(\.isWhitespace), RenderingContext.isStaticallyBlankBlock(elseNodes),
                   RenderingContext.isStaticallyBlankBlock(thenNodes) {
                    return ""
                }
                return result
            }

            return ""
        }

        let conditionValue = try await evaluateExpression(condition)
        if isTruthy(conditionValue) {
            let result = try await renderNodeListFast(thenNodes)
            if result.allSatisfy(\.isWhitespace), RenderingContext.isStaticallyBlankBlock(thenNodes),
               (elseNodes == nil || RenderingContext.isStaticallyBlankBlock(elseNodes!)),
               elsifBranches.allSatisfy({ RenderingContext.isStaticallyBlankBlock($0.1) }) {
                return ""
            }
            return result
        }

        // Check elsif branches
        for (elsifCondition, elsifNodes) in elsifBranches {
            let elsifValue = try await evaluateExpression(elsifCondition)
            if isTruthy(elsifValue) {
                let result = try await renderNodeListFast(elsifNodes)
                if result.allSatisfy(\.isWhitespace), RenderingContext.isStaticallyBlankBlock(elsifNodes),
                   RenderingContext.isStaticallyBlankBlock(thenNodes),
                   (elseNodes == nil || RenderingContext.isStaticallyBlankBlock(elseNodes!)),
                   elsifBranches.allSatisfy({ RenderingContext.isStaticallyBlankBlock($0.1) }) {
                    return ""
                }
                return result
            }
        }

        // Render else branch if present
        if let elseNodes = elseNodes {
            let result = try await renderNodeListFast(elseNodes)
            if result.allSatisfy(\.isWhitespace), RenderingContext.isStaticallyBlankBlock(elseNodes),
               RenderingContext.isStaticallyBlankBlock(thenNodes),
               elsifBranches.allSatisfy({ RenderingContext.isStaticallyBlankBlock($0.1) }) {
                return ""
            }
            return result
        }

        return ""
    }

    internal func renderUnless(condition: LiquidExpression, then thenNodes: [ASTNode], else elseNodes: [ASTNode]?) async throws -> String {
        let conditionValue = try await evaluateExpression(condition)

        if !isTruthy(conditionValue) {
            let result = try await renderNodeListFast(thenNodes)
            if result.allSatisfy(\.isWhitespace), RenderingContext.isStaticallyBlankBlock(thenNodes),
               (elseNodes == nil || RenderingContext.isStaticallyBlankBlock(elseNodes!)) {
                return ""
            }
            return result
        }

        if let elseNodes = elseNodes {
            let result = try await renderNodeListFast(elseNodes)
            if result.allSatisfy(\.isWhitespace), RenderingContext.isStaticallyBlankBlock(elseNodes),
               RenderingContext.isStaticallyBlankBlock(thenNodes) {
                return ""
            }
            return result
        }

        return ""
    }

    // MARK: - Forloop Object Builder

    @inline(__always)
    internal func buildForloopObject(
        index: Int, lastIndex: Int, itemCount: Int,
        name: String, parentForloop: Any?
    ) -> [String: Any] {
        var forloop: [String: Any] = [
            "index": index + 1,
            "index0": index,
            "first": index == 0,
            "last": index == lastIndex,
            "length": itemCount,
            "rindex": itemCount - index,
            "rindex0": lastIndex - index,
            "name": name,
        ]
        if let parentForloop {
            forloop["parentloop"] = parentForloop
        }
        return forloop
    }

    @inline(__always)
    internal func captureParentForloop(needsForloopObject: Bool) -> Any? {
        guard needsForloopObject else { return nil }
        if context.getVariable("__render_forloop__") != nil { return nil }
        return context.getVariable("forloop")
    }

    @inline(__always)
    internal func buildTablerowloopObject(
        index: Int, lastIndex: Int, itemCount: Int,
        colIndex: Int, columnCount: Int, rowIndex: Int
    ) -> [String: Any] {
        [
            "col": colIndex + 1,
            "col0": colIndex,
            "col_first": colIndex == 0,
            "col_last": colIndex == columnCount - 1 || index == lastIndex,
            "first": index == 0,
            "last": index == lastIndex,
            "index": index + 1,
            "index0": index,
            "length": itemCount,
            "rindex": itemCount - index,
            "rindex0": lastIndex - index,
            "row": rowIndex + 1,
        ]
    }

    // MARK: - For Loop Rendering

    internal func renderFor(variable: InlineString, collection: LiquidExpression, body: [ASTNode], empty: [ASTNode]?, params: ForParams) async throws -> String {
        let collectionValue = try await evaluateExpression(collection)
        let forloopName = "\(variable.string)-\(expressionToPath(collection))"

        // Build collection key for offset:continue tracking
        // Include variable name so different loop vars have separate counters
        let collectionKey = "__for_continue_\(variable.string)_\(String(describing: collection))"

        // Convert collection to array (full, unsliced)
        var fullItems: [Any] = []
        if let range = collectionValue as? RuntimeRange {
            fullItems = range.values
        } else if let array = collectionValue as? [Any] {
            fullItems = array
        } else if let pairs = orderedDictPairs(collectionValue) {
            fullItems = pairs.map { [$0.key, $0.value] as [Any] }
        } else if let str = collectionValue as? String {
            // Shopify Liquid: non-empty strings iterate as a single item
            fullItems = str.isEmpty ? [] : [str]
        } else {
            // Not iterable - treat as empty collection
            fullItems = []
        }

        // Determine offset
        var offset = 0
        if params.offsetContinue {
            offset = context.getCounter(collectionKey) ?? 0
        } else if let paramOffset = params.offset {
            offset = paramOffset
        } else if let offsetExpr = params.offsetExpression {
            // Runtime evaluation of offset expression (e.g., limit: my_var)
            let offsetValue = try await evaluateExpression(offsetExpr)
            if let intVal = offsetValue as? Int { offset = intVal }
            else if let dblVal = offsetValue as? Double { offset = try checkedInteger(dblVal) }
            else if let strVal = offsetValue as? String, let intVal = Int(strVal) { offset = intVal }
            else if !(offsetValue is NSNull) {
                throw RenderError.typeError(expected: "integer", actual: "\(type(of: offsetValue))", operation: "for offset")
            }
        }

        // Apply offset
        var items = offset > 0 ? Array(fullItems.dropFirst(offset)) : fullItems

        // Determine limit (static or from expression)
        var resolvedLimit = params.limit
        if resolvedLimit == nil, let limitExpr = params.limitExpression {
            let limitValue = try await evaluateExpression(limitExpr)
            if let intVal = limitValue as? Int { resolvedLimit = intVal }
            else if let dblVal = limitValue as? Double { resolvedLimit = try checkedInteger(dblVal) }
            else if let strVal = limitValue as? String, let intVal = Int(strVal) { resolvedLimit = intVal }
            else if !(limitValue is NSNull) {
                throw RenderError.typeError(expected: "integer", actual: "\(type(of: limitValue))", operation: "for limit")
            }
        }

        // Apply limit
        if let limit = resolvedLimit {
            let count = limit <= 0 ? 0 : max(0, limit + min(offset, 0))
            items = Array(items.prefix(count))
        }

        // Store the continue offset for future loops (offset + items actually iterated)
        context.setCounter(collectionKey, value: offset + items.count)

        // Apply reversed
        if params.reversed {
            items = items.reversed()
        }
        
        // Check if collection is empty and render empty clause if present
        if items.isEmpty {
            if let emptyNodes = empty {
                context.pushScope()
                let emptyOutput = try await renderNodeListFast(
                    emptyNodes,
                    staticCapacityHint: estimatedStaticCapacity(for: emptyNodes)
                )
                context.popScope()
                return emptyOutput
            } else {
                return ""
            }
        }

        let itemCount = items.count
        let lastIndex = itemCount - 1
        let itemCountInt = itemCount

        if let staticBodySegment = params.staticBodySegment {
            let segment = staticBodySegment.string
            guard !segment.isEmpty else {
                return ""
            }

            var output = String()
            output.reserveCapacity(try budget.capacity(staticBodySegment.utf8Count, count: items.count))

            for _ in items {
                try budget.iterate()
                try budget.output(output)
                output.append(segment)
            }

            return output
        }

        if !recoveryEnabled, let renderPlan = params.renderPlan {
            var output = String()
            let staticPlanCapacity = renderPlan.staticUTF8Count
            if staticPlanCapacity > 0 {
                output.reserveCapacity(try budget.capacity(staticPlanCapacity, count: items.count))
            }

            let needsForloopObject = bodyNeedsImplicitLoopObject(named: "forloop", nodes: body)
            let variableName = variable.string

            // Capture parent forloop before pushing scope (for nested loop parentloop access)
            // Don't use render-for's forloop as parentloop (Shopify: render is isolated)
            let parentForloop = captureParentForloop(needsForloopObject: needsForloopObject)

            context.pushScope()
            context.enterLoop()
            defer {
                context.popScope()
                context.leaveLoop()
            }

            forLoop: for (index, item) in items.enumerated() {
                try budget.iterate()
                try budget.output(output)
                try Task.checkCancellation()
                context.setVariable(variableName, value: item)

                if needsForloopObject {
                    let forloop = buildForloopObject(
                        index: index, lastIndex: lastIndex, itemCount: itemCountInt,
                        name: forloopName, parentForloop: parentForloop
                    )
                    context.setVariable("forloop", value: forloop)
                }

                do {
                    try await appendLoopBodyRenderPlanFast(renderPlan, to: &output)
                } catch let signal as LoopControlSignal {
                    output += signal.partialOutput
                    switch signal {
                    case .continueLoop, .continueLoopWithOutput:
                        continue forLoop
                    case .breakLoop, .breakLoopWithOutput:
                        break forLoop
                    }
                }
            }

            return output
        }

        // Render loop
        var output = ""
        let bodyStaticCapacity = estimatedStaticCapacity(for: body)
        if bodyStaticCapacity > 0 {
            output.reserveCapacity(try budget.capacity(bodyStaticCapacity, count: itemCount))
        }
        let needsForloopObject = bodyNeedsImplicitLoopObject(named: "forloop", nodes: body)
        let variableName = variable.string

        // Capture parent forloop before pushing scope (for nested loop parentloop access)
        // Don't use render-for's forloop as parentloop (Shopify: render is isolated)
        let parentForloop = captureParentForloop(needsForloopObject: needsForloopObject)

        context.pushScope()
        context.enterLoop()
        defer {
            context.popScope()
            context.leaveLoop()
        }

        forLoop: for (index, item) in items.enumerated() {
                try budget.iterate()
                try budget.output(output)
            try Task.checkCancellation()
            context.setVariable(variableName, value: item)

            if needsForloopObject {
                let forloop = buildForloopObject(
                    index: index, lastIndex: lastIndex, itemCount: itemCountInt,
                    name: forloopName, parentForloop: parentForloop
                )
                context.setVariable("forloop", value: forloop)
            }

            // Render body
            do {
                try await appendRenderedSimpleNodeListFast(body, to: &output)
            } catch let signal as LoopControlSignal {
                output += signal.partialOutput
                switch signal {
                case .continueLoop, .continueLoopWithOutput:
                    continue forLoop
                case .breakLoop, .breakLoopWithOutput:
                    break forLoop
                }
            }
        }

        // Blank suppression for for loops
        if output.allSatisfy(\.isWhitespace), RenderingContext.isStaticallyBlankBlock(body) {
            return ""
        }

        return output
    }

    internal func renderTableRow(variable: InlineString, collection: LiquidExpression, body: [ASTNode], params: TableRowParams) async throws -> String {
        let collectionValue = try await evaluateExpression(collection)
        
        // Convert collection to array
        var items: [Any] = []
        if let range = collectionValue as? RuntimeRange {
            items = range.values
        } else if let array = collectionValue as? [Any] {
            items = array
        } else if let pairs = orderedDictPairs(collectionValue) {
            items = pairs.map { [$0.key, $0.value] as [Any] }
        } else if let str = collectionValue as? String {
            // Shopify Liquid: non-empty strings iterate as a single item
            items = str.isEmpty ? [] : [str]
        } else {
            // Empty collection
            return ""
        }
        
        // Apply offset
        if let offset = params.offset, offset > 0 {
            items = Array(items.dropFirst(offset))
        }
        
        // Apply limit
        if let limit = params.limit, limit > 0 {
            items = Array(items.prefix(limit))
        }
        
        // Get column count (default to items.count if not specified)
        let columnCount = params.cols ?? items.count
        let itemCount = items.count
        let lastIndex = itemCount - 1

        if let staticBodySegment = params.staticBodySegment {
            let segment = staticBodySegment.string
            var output = String()
            output.reserveCapacity(try budget.capacity((staticBodySegment.utf8Count + 32), count: itemCount))

            for index in items.indices {
                let rowIndex = index / columnCount
                let colIndex = index % columnCount

                if colIndex == 0 {
                    output.append("<tr class=\"row\(rowIndex + 1)\">"  + (rowIndex == 0 ? "\n" : ""))
                }

                output.append("<td class=\"col\(colIndex + 1)\">")
                output.append(segment)
                output.append("</td>")

                if colIndex == columnCount - 1 || index == lastIndex {
                    output.append("</tr>\n")
                }
            }

            return output
        }

        if !recoveryEnabled, let renderPlan = params.renderPlan {
            var output = String()
            output.reserveCapacity(try budget.capacity((renderPlan.staticUTF8Count + 32), count: itemCount))

            let needsTableRowLoopObject = bodyNeedsImplicitLoopObject(named: "tablerowloop", nodes: body)
            let itemCountInt = itemCount
            let variableName = variable.string

            context.pushScope()
            context.enterLoop()
            defer {
                context.popScope()
                context.leaveLoop()
            }

            for (index, item) in items.enumerated() {
                try budget.iterate()
                try budget.output(output)
                let rowIndex = index / columnCount
                let colIndex = index % columnCount

                if colIndex == 0 {
                    output.append("<tr class=\"row\(rowIndex + 1)\">"  + (rowIndex == 0 ? "\n" : ""))
                }

                context.setVariable(variableName, value: item)

                if needsTableRowLoopObject {
                    let tablerowloop = buildTablerowloopObject(
                        index: index, lastIndex: lastIndex, itemCount: itemCountInt,
                        colIndex: colIndex, columnCount: columnCount, rowIndex: rowIndex
                    )
                    context.setVariable("tablerowloop", value: tablerowloop)
                }

                output.append("<td class=\"col\(colIndex + 1)\">")
                do {
                    try await appendLoopBodyRenderPlanFast(renderPlan, to: &output)
                } catch let signal as LoopControlSignal {
                    output += signal.partialOutput
                    output.append("</td>")

                    switch signal {
                    case .continueLoop, .continueLoopWithOutput:
                        if colIndex == columnCount - 1 || index == lastIndex {
                            output.append("</tr>\n")
                        }
                        continue
                    case .breakLoop, .breakLoopWithOutput:
                        output.append("</tr>\n")
                        return output
                    }
                }
                output.append("</td>")

                if colIndex == columnCount - 1 || index == lastIndex {
                    output.append("</tr>\n")
                }
            }

            return output
        }

        let itemCountInt = itemCount
        
        var output = ""
        let bodyStaticCapacity = estimatedStaticCapacity(for: body)
        if bodyStaticCapacity > 0 {
            output.reserveCapacity(try budget.capacity((bodyStaticCapacity + 32), count: itemCount))
        }
        let needsTableRowLoopObject = bodyNeedsImplicitLoopObject(named: "tablerowloop", nodes: body)
        let variableName = variable.string
        context.pushScope()
        context.enterLoop()
        defer {
            context.popScope()
            context.leaveLoop()
        }
        
        // Generate table rows
        for (index, item) in items.enumerated() {
                try budget.iterate()
                try budget.output(output)
            let rowIndex = index / columnCount
            let colIndex = index % columnCount
            
            // Start new row
            if colIndex == 0 {
                output.append("<tr class=\"row\(rowIndex + 1)\">"  + (rowIndex == 0 ? "\n" : ""))
            }

            // Set loop variable
            context.setVariable(variableName, value: item)

            // Set tablerowloop object
            if needsTableRowLoopObject {
                let tablerowloop = buildTablerowloopObject(
                    index: index, lastIndex: lastIndex, itemCount: itemCountInt,
                    colIndex: colIndex, columnCount: columnCount, rowIndex: rowIndex
                )
                context.setVariable("tablerowloop", value: tablerowloop)
            }

            // Render cell content
            let cellClass = "col\(colIndex + 1)"
            output.append("<td class=\"\(cellClass)\">")
            do {
                try await appendRenderedSimpleNodeListFast(body, to: &output)
            } catch let signal as LoopControlSignal {
                output += signal.partialOutput
                output.append("</td>")

                switch signal {
                case .continueLoop, .continueLoopWithOutput:
                    if colIndex == columnCount - 1 || index == lastIndex {
                        output.append("</tr>\n")
                    }
                    continue
                case .breakLoop, .breakLoopWithOutput:
                    output.append("</tr>\n")
                    return output
                }
            }
            output.append("</td>")

            // End row
            if colIndex == columnCount - 1 || index == lastIndex {
                output.append("</tr>\n")
            }
        }

        return output
    }
    
    internal func renderCapture(variable: InlineString, body: [ASTNode]) async throws -> String {
        let capturedOutput = try await renderNodeListFast(body)
        context.setVariable(variable.string, value: capturedOutput)
        return "" // Capture produces no output
    }
    
    internal func renderIncrement(name: InlineString) async throws -> String {
        // Increment/decrement use a separate counter namespace (Shopify behavior)
        // They do NOT interfere with assigned variables
        let currentValue = context.getCounter(name.string) ?? 0
        context.setCounter(name.string, value: currentValue + 1)
        return String(currentValue) // Return current value before increment
    }

    internal func renderDecrement(name: InlineString) async throws -> String {
        // Increment/decrement use a separate counter namespace (Shopify behavior)
        let currentValue = context.getCounter(name.string) ?? 0
        let newValue = currentValue - 1
        context.setCounter(name.string, value: newValue)
        return String(newValue) // Return decremented value
    }


    
    internal func renderCycle(group: LiquidExpression?, items: [LiquidExpression], site: CycleSiteIdentity) async throws -> String {
        guard !items.isEmpty else { return "" }

        // Pinned Ruby duplicates top-level VariableLookup values before deriving
        // an unnamed key. Each parsed variable-cycle site therefore owns a counter.
        // Literal and named cycles keep their existing grouping semantics.
        let usesSiteCounter = group == nil && items.contains { item in
            switch item {
            case .variable, .access: return true
            default: return false
            }
        }
        let cycleKey: String
        if let group {
            let groupValue = try await evaluateExpression(group)
            cycleKey = stringify(groupValue)
        } else {
            // No group name: use items as the key (Shopify behavior: different items = different cycle)
            cycleKey = items.map { String(describing: $0) }.joined(separator: ",")
        }

        let counterKey = "__cycle_\(cycleKey)"
        let currentIndex = usesSiteCounter
            ? context.getCycleCounter(site) ?? 0
            : context.getCounter(counterKey) ?? 0

        // Ruby Liquid behavior: use counter as direct index into CURRENT items array
        // If out of bounds → output nothing. Reset to 0 when counter >= items.count.
        let result: String
        if currentIndex < items.count {
            let value = try await evaluateExpression(items[currentIndex])
            result = stringify(value)
        } else {
            result = ""  // Out of bounds → no output
        }

        // Advance counter, reset to 0 when it reaches current items count
        var nextIndex = currentIndex + 1
        if nextIndex >= items.count {
            nextIndex = 0
        }
        if usesSiteCounter {
            context.setCycleCounter(site, value: nextIndex)
        } else {
            context.setCounter(counterKey, value: nextIndex)
        }

        return result
    }
    
    internal func renderInclude(template: InlineString, with withVars: [String: LiquidExpression]?, as asVar: InlineString?) async throws -> String {
        guard let templateLoader else {
            throw RenderError.includeError(
                template.string,
                reason: "No TemplateLoader configured for include/render operations"
            )
        }

        let isRender = withVars?["__render_isolated__"] != nil
        let hasForIteration = withVars?["_for"] != nil
        let evaluatedVariables = try await evaluateIncludeBindings(
            template: template,
            with: withVars,
            as: asVar
        )

        var templateName = template.string

        var resolvedPath: String
        var ast: ASTNode

        do {
            // Try literal template name first
            resolvedPath = try templateLoader.resolvedTemplatePath(
                for: templateName,
                relativeTo: currentTemplatePath
            )
            ast = try templateLoader.loadTemplateAST(
                templateName,
                relativeTo: currentTemplatePath
            )
        } catch {
            // If literal name fails, try resolving as a variable reference
            if let variableValue = context.getVariable(templateName) as? String {
                templateName = variableValue
                do {
                    resolvedPath = try templateLoader.resolvedTemplatePath(
                        for: templateName,
                        relativeTo: currentTemplatePath
                    )
                    ast = try templateLoader.loadTemplateAST(
                        templateName,
                        relativeTo: currentTemplatePath
                    )
                } catch let innerError as TemplateLoaderError {
                    throw mapTemplateLoaderError(innerError, template: templateName)
                } catch {
                    throw RenderError.includeError(templateName, reason: error.localizedDescription)
                }
            } else if let loadError = error as? TemplateLoaderError {
                throw mapTemplateLoaderError(loadError, template: templateName)
            } else {
                throw RenderError.includeError(templateName, reason: error.localizedDescription)
            }
        }

        // Handle {% render "template" for collection %} — iterate and render for each item
        if isRender, hasForIteration, let forExpr = withVars?["_for"] {
            let collection = try await evaluateExpression(forExpr)
            guard let items = collection as? [Any] else {
                return ""
            }
            let alias = asVar?.string ?? defaultTemplateAlias(for: template.string)
            let itemCount = items.count
            let lastIndex = itemCount - 1
            let forloopName = "\(alias)-\(template.string)"
            var output = ""
            output.reserveCapacity(items.count * 64)
            for (index, item) in items.enumerated() {
                try budget.iterate()
                try budget.output(output)
                var itemVars = evaluatedVariables
                itemVars[alias] = item
                let forloop = buildForloopObject(
                    index: index, lastIndex: lastIndex, itemCount: itemCount,
                    name: forloopName, parentForloop: nil
                )
                // Use saveState/isolateScope/restoreState for render isolation
                // Set forloop in isolated scope. Mark it as render-forloop so nested loops
                // don't use it as parentloop.
                itemVars["forloop"] = forloop
                itemVars["__render_forloop__"] = true  // Flag for parentloop suppression
                let savedState = context.saveState()
                context.isolateScope(with: itemVars)
                templatePathStack.append(resolvedPath)
                defer {
                    _ = templatePathStack.popLast()
                    context.restoreState(savedState)
                }
                let preparedAST = try await prepareASTForRendering(ast)
                output += try await withAuthoringScope(for: preparedAST, templatePath: resolvedPath) {
                    try await renderNode(preparedAST)
                }
            }
            return output
        }

        // Handle {% include "template" for collection %} (non-render mode)
        if !isRender, hasForIteration, let forExpr = withVars?["_for"] {
            let collection = try await evaluateExpression(forExpr)
            guard let items = collection as? [Any] else {
                return ""
            }
            let alias = asVar?.string ?? defaultTemplateAlias(for: templateName)
            var output = ""
            output.reserveCapacity(items.count * 64)
            for item in items {
                try budget.iterate()
                try budget.output(output)
                let snapshots = context.snapshotVariables(named: [alias])
                context.setVariable(alias, value: item)
                templatePathStack.append(resolvedPath)
                let preparedAST = try await prepareASTForRendering(ast)
                output += try await withAuthoringScope(for: preparedAST, templatePath: resolvedPath) {
                    try await renderNode(preparedAST)
                }
                _ = templatePathStack.popLast()
                context.restoreVariables(snapshots)
            }
            return output
        }

        if isRender {
            let savedState = context.saveState()
            context.isolateScope(with: evaluatedVariables)
            templatePathStack.append(resolvedPath)
            defer {
                _ = templatePathStack.popLast()
                context.restoreState(savedState)
            }
            let preparedAST = try await prepareASTForRendering(ast)
            return try await withAuthoringScope(for: preparedAST, templatePath: resolvedPath) {
                try await renderNode(preparedAST)
            }
        } else {
            // Push keyword args in a scope so they're protected from assigns
            // (assigns use setRootVariable which writes to root, keyword args shadow them)
            if !evaluatedVariables.isEmpty {
                context.pushScope(evaluatedVariables)
            }

            templatePathStack.append(resolvedPath)
            defer {
                _ = templatePathStack.popLast()
                if !evaluatedVariables.isEmpty {
                    context.popScope()
                }
            }

            let preparedAST = try await prepareASTForRendering(ast)
            // Set up authoring scope manually (instead of withAuthoringScope closure)

            // Render node-by-node so break inside include preserves partial output
            var includeOutput = ""
            do {
                switch preparedAST {
                case .template(let nodes):
                    try await appendRenderedSimpleNodeListFast(nodes, to: &includeOutput)
                default:
                    includeOutput = try await renderNode(preparedAST)
                }
            } catch let signal as LoopControlSignal {
                // Re-throw with COMBINED partial output (our output + nested include's output)
                throw signal.carrying(includeOutput + signal.partialOutput)
            }

            return includeOutput
        }
    }

    internal func evaluateIncludeBindings(
        template: InlineString,
        with withVars: [String: LiquidExpression]?,
        as asVar: InlineString?
    ) async throws -> RuntimeVariables {
        guard let withVars else {
            return [:]
        }

        var evaluatedVariables: RuntimeVariables = [:]
        evaluatedVariables.reserveCapacity(withVars.count)

        for (key, expression) in withVars {
            switch key {
            case "__render_isolated__", "_with", "_for":
                continue
            default:
                evaluatedVariables[key] = try await evaluateExpression(expression)
            }
        }

        if let withExpression = withVars["_with"] {
            let alias = asVar?.string ?? defaultTemplateAlias(for: template.string)
            evaluatedVariables[alias] = try await evaluateExpression(withExpression)
        }

        return evaluatedVariables
    }

    internal func defaultTemplateAlias(for templatePath: String) -> String {
        let candidate = URL(fileURLWithPath: templatePath)
            .deletingPathExtension()
            .lastPathComponent
        return candidate.isEmpty ? "item" : candidate
    }














    
    internal func renderCase(value: LiquidExpression, whens: [(LiquidExpression, [ASTNode])], else elseBranch: [ASTNode]?) async throws -> String {
        let caseValue = try await evaluateExpression(value)

        // Process sequentially. Else branches (sentinel .literal(.null)) render when
        // no PRECEDING when matched. Regular when branches match against case value.
        var output = ""
        var anyPrecedingWhenMatched = false

        for (whenExpr, whenNodes) in whens {
            // Sentinel .literal(.null) means else branch
            if case .literal(.null) = whenExpr {
                // Else renders when no preceding when matched
                if !anyPrecedingWhenMatched {
                    output += try await renderNodeListFast(whenNodes)
                }
                continue
            }

            let whenValue = try await evaluateExpression(whenExpr)
            if isEqual(caseValue, whenValue) {
                anyPrecedingWhenMatched = true
                output += try await renderNodeListFast(whenNodes)
            }
        }

        // If no when matched at all, render the legacy else branch
        if !anyPrecedingWhenMatched, let elseBranch = elseBranch {
            output += try await renderNodeListFast(elseBranch)
        }

        // Blank suppression: if output is whitespace-only and all branches are statically blank, suppress
        if output.allSatisfy(\.isWhitespace),
           whens.allSatisfy({ RenderingContext.isStaticallyBlankBlock($0.1) }),
           (elseBranch == nil || RenderingContext.isStaticallyBlankBlock(elseBranch!)) {
            return ""
        }

        return output
    }


    

    





}
