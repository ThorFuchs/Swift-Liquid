// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: standard syntax only; authoring and legacy nodes removed.

// An immutable parsed-site identity. Counters live in RenderingContext, never here.
internal final class CycleSiteIdentity: Sendable {}

internal indirect enum ASTNode: Sendable {
    case template([ASTNode])
    case text(InlineString)
    case output(LiquidExpression, location: RenderLocation? = nil)
    case `if`(condition: LiquidExpression, then: [ASTNode], elsif: [(LiquidExpression, [ASTNode])], else: [ASTNode]?)
    case unless(condition: LiquidExpression, then: [ASTNode], else: [ASTNode]?)
    case `case`(value: LiquidExpression, branches: [CaseBranch])
    case `for`(variable: InlineString, in: LiquidExpression, body: [ASTNode], empty: [ASTNode]?, params: ForParams)
    case tablerow(variable: InlineString, in: LiquidExpression, body: [ASTNode], params: TableRowParams)
    case cycle(group: LiquidExpression?, items: [LiquidExpression], site: CycleSiteIdentity)
    case assign(variable: InlineString, value: LiquidExpression, location: RenderLocation? = nil)
    case capture(variable: InlineString, body: [ASTNode])
    case increment(name: InlineString)
    case decrement(name: InlineString)
    case include(template: InlineString, reference: LiquidExpression, with: [String: LiquidExpression]?, as: InlineString?)
    case comment
    case raw(InlineString)
    case liquid(body: [ASTNode])
    case echo(expression: LiquidExpression, location: RenderLocation? = nil)
    case `break`
    case `continue`
    case ifchanged([ASTNode])

    var children: [ASTNode] {
        switch self {
        case .template(let nodes), .liquid(let nodes), .ifchanged(let nodes): return nodes
        case .if(_, let body, let branches, let fallback): return body + branches.flatMap { $0.1 } + (fallback ?? [])
        case .unless(_, let body, let fallback): return body + (fallback ?? [])
        case .case(_, let branches): return branches.flatMap(\.body)
        case .for(_, _, let body, let fallback, _): return body + (fallback ?? [])
        case .tablerow(_, _, let body, _), .capture(_, let body): return body
        default: return []
        }
    }

    var expressions: [LiquidExpression] {
        switch self {
        case .output(let value, _), .echo(let value, _), .assign(_, let value, _): return [value]
        case .if(let condition, _, let branches, _): return [condition] + branches.map { $0.0 }
        case .unless(let condition, _, _): return [condition]
        case .case(let value, let branches): return [value] + branches.compactMap(\.expression)
        case .for(_, let value, _, _, let params): return [value] + [params.limitExpression, params.offsetExpression].compactMap { $0 }
        case .tablerow(_, let value, _, _): return [value]
        case .cycle(let group, let values, _): return values + (group.map { [$0] } ?? [])
        case .include(_, let reference, let values, _): return [reference] + (values.map { Array($0.values) } ?? [])
        default: return []
        }
    }
}

// Control-flow identity cannot collide with any legal when expression value.
internal enum CaseBranch: Sendable {
    case when(LiquidExpression, [ASTNode])
    case otherwise([ASTNode])

    var body: [ASTNode] {
        switch self {
        case .when(_, let nodes), .otherwise(let nodes): return nodes
        }
    }

    var expression: LiquidExpression? {
        if case .when(let expression, _) = self { return expression }
        return nil
    }
}

internal struct ForParams: Sendable, Equatable {
    internal let limit: Int?

    internal let offset: Int?

    internal let offsetContinue: Bool

    internal let reversed: Bool

    internal let condition: LiquidExpression?

    internal let recursive: Bool

    internal let limitExpression: LiquidExpression?

    internal let offsetExpression: LiquidExpression?

    internal let staticBodySegment: InlineString?

    internal let renderPlan: LoopBodyRenderPlan?

    internal init(
        limit: Int? = nil,
        offset: Int? = nil,
        offsetContinue: Bool = false,
        reversed: Bool = false,
        condition: LiquidExpression? = nil,
        recursive: Bool = false,
        limitExpression: LiquidExpression? = nil,
        offsetExpression: LiquidExpression? = nil
    ) {
        self.limit = limit
        self.offset = offset
        self.offsetContinue = offsetContinue
        self.reversed = reversed
        self.condition = condition
        self.recursive = recursive
        self.limitExpression = limitExpression
        self.offsetExpression = offsetExpression
        self.staticBodySegment = nil
        self.renderPlan = nil
    }

    internal init(
        limit: Int? = nil,
        offset: Int? = nil,
        offsetContinue: Bool = false,
        reversed: Bool = false,
        condition: LiquidExpression? = nil,
        recursive: Bool = false,
        limitExpression: LiquidExpression? = nil,
        offsetExpression: LiquidExpression? = nil,
        staticBodySegment: InlineString? = nil,
        renderPlan: LoopBodyRenderPlan? = nil
    ) {
        self.limit = limit
        self.offset = offset
        self.offsetContinue = offsetContinue
        self.reversed = reversed
        self.condition = condition
        self.recursive = recursive
        self.limitExpression = limitExpression
        self.offsetExpression = offsetExpression
        self.staticBodySegment = staticBodySegment
        self.renderPlan = renderPlan
    }
}

internal struct TableRowParams: Sendable, Equatable {
    internal let cols: Int?
    
    internal let limit: Int?
    
    internal let offset: Int?

    internal let staticBodySegment: InlineString?

    internal let renderPlan: LoopBodyRenderPlan?

    internal init(cols: Int? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.cols = cols
        self.limit = limit
        self.offset = offset
        self.staticBodySegment = nil
        self.renderPlan = nil
    }

    internal init(
        cols: Int? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        staticBodySegment: InlineString? = nil,
        renderPlan: LoopBodyRenderPlan? = nil
    ) {
        self.cols = cols
        self.limit = limit
        self.offset = offset
        self.staticBodySegment = staticBodySegment
        self.renderPlan = renderPlan
    }
}

internal enum LoopBodyRenderPlan: Sendable, Equatable {
    case single(
        prefix: InlineString,
        expression: LiquidExpression,
        suffix: InlineString
    )
    case double(
        prefix: InlineString,
        first: LiquidExpression,
        middle: InlineString,
        second: LiquidExpression,
        suffix: InlineString
    )

    internal var staticUTF8Count: Int {
        switch self {
        case .single(let prefix, _, let suffix):
            return prefix.utf8Count + suffix.utf8Count
        case .double(let prefix, _, let middle, _, let suffix):
            return prefix.utf8Count + middle.utf8Count + suffix.utf8Count
        }
    }
}


internal struct RenderLocation: Sendable {
    let line: Int
    let suppressErrorText: Bool
}

extension ASTNode {
    var renderLocation: RenderLocation? {
        switch self {
        case .output(_, let location), .echo(_, let location), .assign(_, _, let location): return location
        default: return nil
        }
    }
}
