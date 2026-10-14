// SPDX-License-Identifier: Apache-2.0

internal func validateTemplate(_ ast: ASTNode, limits: LiquidLimits) throws {
    var nodes = [(ast, 0)]
    var expressions: [(LiquidExpression, Int)] = []
    while let (node, depth) = nodes.popLast() {
        try Task.checkCancellation()
        guard depth < limits.nestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
        nodes.append(contentsOf: node.children.map { ($0, depth + 1) })
        expressions.append(contentsOf: node.expressions.map { ($0, 0) })
    }
    while let (expression, depth) = expressions.popLast() {
        guard depth < limits.nestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
        let children: [LiquidExpression]
        switch expression {
        case .binary(let left, _, let right): children = [left, right]
        case .unary(_, let value): children = [value]
        case .range(let start, let end): children = [start, end]
        case .filtered(let value, let filters):
            children = [value] + filters.flatMap { $0.arguments + $0.namedArguments.map(\.value) }
        case .access(let value, let key): children = [value, key]
        case .literal, .variable: children = []
        case .call, .test: throw LiquidError.syntax(message: "Expression is outside standard Liquid", line: nil, column: nil)
        }
        expressions.append(contentsOf: children.map { ($0, depth + 1) })
    }
}
