// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A failure exposed by the Liquid library. Cancellation remains `CancellationError`.
public enum LiquidError: Error, Sendable, CustomStringConvertible {
    /// Invalid template syntax with an available source location.
    case syntax(message: String, line: Int?, column: Int?)
    /// A completed parse encountered an invalid runtime operation.
    case rendering(String)
    /// A configured operation limit was exceeded.
    case limitExceeded(String)
    /// A context or numeric value is outside the supported value domain.
    case invalidValue(String)
    /// A human-readable diagnostic.
    public var description: String {
        switch self {
        case .syntax(let message, let line, let column):
            if let line, let column { return "Liquid syntax at \(line):\(column): \(message)" }
            return "Liquid syntax: \(message)"
        case .rendering(let message): return "Liquid render: \(message)"
        case .limitExceeded(let name): return "Liquid limit exceeded: \(name)"
        case .invalidValue(let message): return "Invalid Liquid value: \(message)"
        }
    }
}

internal func publicError(_ error: Error) -> Error {
    if let error = error as? LexerError {
        return LiquidError.syntax(message: error.message, line: nil, column: nil)
    }
    if let error = error as? ParserError {
        return LiquidError.syntax(message: error.message, line: error.sourceLocation?.line, column: error.sourceLocation?.column)
    }
    if let error = error as? RenderError { return LiquidError.rendering(error.message) }
    return error
}
