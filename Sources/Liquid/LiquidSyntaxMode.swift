// SPDX-License-Identifier: Apache-2.0

/// Controls compatibility with Shopify's parser modes.
public enum LiquidSyntaxMode: String, Sendable {
    /// Accepts the permissive syntax used by the golden fixtures.
    case lax
    /// Rejects malformed standard Liquid expressions.
    case strict
    /// Also rejects malformed assignment names and case clauses.
    case strict2
}
