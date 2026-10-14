// SPDX-License-Identifier: Apache-2.0

/// An application-defined filter supplied explicitly to an engine.
///
/// The callback receives admitted values and evaluated arguments. It may suspend;
/// its captures must be Sendable. Callbacks are trusted application code and may
/// run concurrently when the engine is shared across rendering tasks.
public struct LiquidFilter: Sendable {
    /// The exact, case-sensitive name used in a template's filter pipeline.
    public let name: String
    internal let body: @Sendable (LiquidValue, [LiquidValue], LiquidObject) async throws -> LiquidValue

    /// Creates a filter. Names and collisions are validated by the engine initializer.
    /// - Parameters:
    ///   - name: One filter identifier; standard names and aliases are protected.
    ///   - body: Input, positional arguments, and named arguments in source order.
    ///     Throw `LiquidFilterFailure` for an explicitly recoverable filter failure.
    public init(_ name: String,
                body: @escaping @Sendable (LiquidValue, [LiquidValue], LiquidObject) async throws -> LiquidValue) {
        self.name = name
        self.body = body
    }

    internal static func validated(_ filters: [LiquidFilter]) throws -> [ScalarKey: LiquidFilter] {
        var result: [ScalarKey: LiquidFilter] = [:]
        for filter in filters {
            let name = filter.name
            guard let tokens = try? Lexer("{{ '' | \(name) }}").tokenize(), tokens.count == 5,
                  tokens[0].type == .variableStart, tokens[2].type == .filter,
                  tokens[4].type == .variableEnd,
                  case .identifier(let parsed) = tokens[3].type,
                  parsed.string.utf8.elementsEqual(name.utf8) else {
                throw LiquidError.invalidValue("Invalid custom filter name '\(name)'")
            }
            guard !standardFilterNames.contains(name) else {
                throw LiquidError.invalidValue("Custom filter '\(name)' conflicts with a standard filter or alias")
            }
            let key = ScalarKey(name)
            guard result[key] == nil else {
                throw LiquidError.invalidValue("Duplicate custom filter '\(name)'")
            }
            result[key] = filter
        }
        return result
    }
}

/// An application filter failure that explicit diagnostic rendering may recover.
///
/// Other callback errors propagate unchanged. Cancellation, invalid values and
/// exhausted limits never become recovered filter failures.
public struct LiquidFilterFailure: Error, Sendable, Equatable, CustomStringConvertible {
    /// The explanation included in the rendering error or recovered diagnostic.
    public let message: String
    /// Creates an explicitly recoverable filter failure.
    public init(_ message: String) { self.message = message }
    /// The filter's explanation.
    public var description: String { message }
}
