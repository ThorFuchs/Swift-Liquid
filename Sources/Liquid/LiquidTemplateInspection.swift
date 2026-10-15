// SPDX-License-Identifier: Apache-2.0

/// Immutable syntactic references from one parsed template, without evaluating it.
/// Lists are unique by exact UTF-8 spelling and sorted in ascending UTF-8 order.
/// Inspection does not follow partials or determine which paths execute.
public struct LiquidTemplateInspection: Sendable, Equatable {
    /// Variable roots read by AST expressions, including local and dynamic lookup roots.
    /// Assignment targets, literal property names and counter names are not reads.
    public let variableRoots: [String]
    /// Filter names as written, including unknown or application-supplied filters.
    public let filterNames: [String]
    /// String-literal include/render names, without path or suffix normalization.
    public let literalPartialNames: [String]
    /// Whether any include uses a nonliteral template reference.
    public let hasDynamicPartials: Bool

    /// Compares exact spellings, without Unicode canonical-equivalence folding.
    /// - Parameters:
    ///   - lhs: Left value, compared using exact UTF-8 spellings.
    ///   - rhs: Right value, compared using exact UTF-8 spellings.
    /// - Returns: Whether all identity and retained-content fields are equal.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        func equal(_ left: [String], _ right: [String]) -> Bool {
            left.count == right.count && zip(left, right).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
        }
        return equal(lhs.variableRoots, rhs.variableRoots)
            && equal(lhs.filterNames, rhs.filterNames)
            && equal(lhs.literalPartialNames, rhs.literalPartialNames)
            && lhs.hasDynamicPartials == rhs.hasDynamicPartials
    }
}

internal func inspectTemplate(_ ast: ASTNode, limits: LiquidLimits) throws -> LiquidTemplateInspection {
    var variables: Set<ScalarKey> = []
    var filters: Set<ScalarKey> = []
    var partials: Set<ScalarKey> = []
    var dynamic = false
    var nodes = [(ast, 0)]
    var expressions: [(LiquidExpression, Int)] = []
    while let (node, depth) = nodes.popLast() {
        try Task.checkCancellation()
        guard depth < limits.nestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
        if case .include(_, let reference, _, _) = node {
            if case .literal(.string(let name)) = reference { partials.insert(ScalarKey(name.string)) }
            else { dynamic = true }
        }
        nodes.append(contentsOf: node.children.map { ($0, depth + 1) })
        expressions.append(contentsOf: node.expressions.map { ($0, 0) })
    }
    while let (expression, depth) = expressions.popLast() {
        try Task.checkCancellation()
        guard depth < limits.nestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
        let children: [LiquidExpression]
        switch expression {
        case .variable(let name): variables.insert(ScalarKey(name.string)); children = []
        case .literal: children = []
        case .binary(let left, _, let right): children = [left, right]
        case .unary(_, let value): children = [value]
        case .range(let start, let end): children = [start, end]
        case .access(let value, let key, _): children = [value, key]
        case .filtered(let value, let pipeline):
            for filter in pipeline { filters.insert(ScalarKey(filter.name.string)) }
            children = [value] + pipeline.flatMap { $0.arguments + $0.namedArguments.map(\.value) }
        case .call, .test:
            throw LiquidError.syntax(message: "Expression is outside standard Liquid", line: nil, column: nil)
        }
        expressions.append(contentsOf: children.map { ($0, depth + 1) })
    }
    func sorted(_ values: Set<ScalarKey>) -> [String] {
        values.map(\.string).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }
    try Task.checkCancellation()
    return LiquidTemplateInspection(variableRoots: sorted(variables), filterNames: sorted(filters),
        literalPartialNames: sorted(partials), hasDynamicPartials: dynamic)
}
