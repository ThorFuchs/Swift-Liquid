// SPDX-License-Identifier: Apache-2.0

/// A terminal failure of the closed system-value extension.
public enum LiquidSystemError: Error, Sendable, Equatable {
    /// The property was known, but its resident product was not available.
    case unavailable(property: LiquidSystemProperty, state: Availability)
    /// Parsed and requested syntax profiles were incompatible.
    case incompatibleProfile

    /// Why an explicitly selected system property is unavailable.
    public enum Availability: Sendable, Equatable {
        /// No descriptor or decorated value was admitted.
        case notAdmitted
        /// The known representation was not requested.
        case notRequested
        /// The known representation was unavailable, with an admitted bounded reason.
        case unavailable(String)
        /// Optional representation preparation failed with an admitted bounded reason.
        case optionalFailure(String)
    }
}
