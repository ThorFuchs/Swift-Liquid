// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A parsed, immutable template that can be reused by concurrent render operations.
public struct LiquidTemplate: Sendable {
    internal let ast: ASTNode
    /// The original Liquid source.
    public let source: String
    /// Parses standard Liquid source.
    /// - Parameters:
    ///   - source: Liquid source retained exactly as supplied.
    ///   - syntaxMode: Parser policy retained by the parsed AST.
    ///   - limits: Source and syntax-depth capacities; rendering applies its own current profile.
    /// - Throws: Syntax, invalid-limit, source/depth capacity or cancellation errors.
    public init(_ source: String, syntaxMode: LiquidSyntaxMode = .lax, limits: LiquidLimits = .default) throws {
        try limits.validate()
        try Task.checkCancellation()
        guard source.utf8.count <= limits.sourceBytes else { throw LiquidError.limitExceeded("sourceBytes") }
        self.source = source
        do {
            let tokens = try Lexer(source).tokenize()
            self.ast = try Parser(consuming: tokens, source: source, syntaxMode: syntaxMode, maxNestingDepth: limits.nestingDepth).parse()
            try validateTemplate(ast, limits: limits)
        } catch { throw publicError(error) }
    }
}
