// SPDX-License-Identifier: Apache-2.0

/// Explicit Liquid grammar extensions, independent of Shopify parser mode.
public enum LiquidExtensionProfile: Sendable, Equatable {
    /// Open-source Shopify Liquid syntax.
    case standard
    /// The closed, versioned resident-system property syntax.
    case closedSystemV1
}

/// The closed system-property vocabulary for the first extension profile.
public enum LiquidSystemProperty: String, Sendable, CaseIterable {
    /// Ordinary recursive primary projection with all decorations removed.
    case value
    /// Admitted closed descriptor view.
    case descriptor
    /// Resident plain-text representation.
    case plain
    /// Resident HTML text-node representation.
    case htmlText
    /// Resident DIV-flow HTML representation.
    case html
}
