// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  RuntimeLiquidError.swift
//  LiquidCore
//
//

import Foundation

internal protocol RuntimeLiquidError: Error, Sendable, CustomStringConvertible {
    var category: LiquidErrorCategory { get }
    
    var message: String { get }
    
    var sourceLocation: LiquidSourceLocation? { get }
    
    var suggestion: String? { get }
    
    var severity: LiquidErrorSeverity { get }
    
    func withContext(_ context: ErrorContext) -> Self
}

internal enum LiquidErrorCategory: String, Sendable, CaseIterable {
    case lexing = "Lexing"
    case parsing = "Parsing"
    case rendering = "Rendering"
    case semantic = "Semantic"
    case runtime = "Runtime"
    case template = "Template"
}

internal enum LiquidErrorSeverity: String, Sendable, CaseIterable {
    case error = "Error"
    case warning = "Warning"
    case info = "Info"
    
    internal var shouldStop: Bool {
        switch self {
        case .error:
            return true
        case .warning, .info:
            return false
        }
    }
}

internal struct ErrorContext: Sendable {
    internal let sourceLocation: LiquidSourceLocation
    
    internal let templateName: String?
    
    internal let callStack: [String]
    
    internal let metadata: [String: String]
    
    internal init(
        sourceLocation: LiquidSourceLocation,
        templateName: String? = nil,
        callStack: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.sourceLocation = sourceLocation
        self.templateName = templateName
        self.callStack = callStack
        self.metadata = metadata
    }
    
    internal init(from token: Token) {
        self.sourceLocation = LiquidSourceLocation(from: token)
        self.templateName = nil
        self.callStack = []
        self.metadata = [:]
    }
}

// MARK: - Default Implementation

extension RuntimeLiquidError {
    internal var description: String {
        var result = "[\(category.rawValue)] \(message)"
        
        if let location = sourceLocation {
            result = "\(location): \(result)"
        }
        
        if let suggestion = suggestion {
            result += "\n  Suggestion: \(suggestion)"
        }
        
        return result
    }
    
    internal var suggestion: String? {
        return nil
    }
    
    internal var severity: LiquidErrorSeverity {
        return .error
    }
}

// MARK: - Error Collection

internal struct ErrorCollection: Error, Sendable {
    internal let errors: [any RuntimeLiquidError]
    
    internal init(errors: [any RuntimeLiquidError]) {
        self.errors = errors
    }
    
    internal var hasStoppingErrors: Bool {
        return errors.contains { $0.severity.shouldStop }
    }
    
    internal var errorsByCategory: [LiquidErrorCategory: [any RuntimeLiquidError]] {
        return Dictionary(grouping: errors) { $0.category }
    }
}

// MARK: - Error Handler

internal struct ErrorHandler {
    internal static func handle<T>(
        _ operation: () throws -> T,
        context: ErrorContext
    ) throws -> T {
        do {
            return try operation()
        } catch let error as RuntimeLiquidError {
            throw error.withContext(context)
        } catch {
            // Wrap unknown errors
            throw UnknownError(
                underlyingError: error,
                sourceLocation: context.sourceLocation
            )
        }
    }
    
    internal static func handleAsync<T>(
        _ operation: () async throws -> T,
        context: ErrorContext
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as RuntimeLiquidError {
            throw error.withContext(context)
        } catch {
            // Wrap unknown errors
            throw UnknownError(
                underlyingError: error,
                sourceLocation: context.sourceLocation
            )
        }
    }
}

// MARK: - Unknown Error Wrapper

internal struct UnknownError: RuntimeLiquidError {
    internal let underlyingError: Error
    
    internal let sourceLocation: LiquidSourceLocation?
    
    internal init(underlyingError: Error, sourceLocation: LiquidSourceLocation? = nil) {
        self.underlyingError = underlyingError
        self.sourceLocation = sourceLocation
    }
    
    // MARK: - RuntimeLiquidError Implementation
    
    internal var category: LiquidErrorCategory {
        return .runtime
    }
    
    internal var message: String {
        return "Unknown error: \(underlyingError.localizedDescription)"
    }
    
    internal var suggestion: String? {
        return "This is an unexpected error. Please report it as a bug."
    }
    
    internal func withContext(_ context: ErrorContext) -> UnknownError {
        return UnknownError(
            underlyingError: underlyingError,
            sourceLocation: context.sourceLocation
        )
    }
}
