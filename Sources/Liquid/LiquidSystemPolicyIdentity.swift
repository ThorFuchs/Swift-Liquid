// SPDX-License-Identifier: Apache-2.0

/// A finite, opaque identity for one supported system representation context.
///
/// Identity is compared using the exact admitted bytes. Construction validates
/// shape only: it does not certify Content issuance, policy completeness, HTML
/// safety or placement. Hosts retain those separate responsibilities.
public struct LiquidSystemPolicyIdentity: Sendable, Equatable {
    /// Context and version of the representation to which this identity applies.
    public enum Context: Sendable, Equatable {
        /// An `html-text-v1` payload for a reviewed HTML text-node site.
        case htmlTextV1
        /// A `fragment-v1` DIV-flow payload for a reviewed compatible site.
        case htmlFlowFragmentV1
    }

    /// A failure to admit a finite identity.
    public enum AdmissionError: Error, Sendable, Equatable {
        /// The role is empty, too long, or contains non-ASCII identifier bytes.
        case invalidRole
        /// The opaque identity exceeds its finite byte capacity.
        case identityTooLong
    }

    /// Immutable ASCII role namespace, compared by its exact UTF-8 bytes.
    public let role: String
    /// Opaque bytes; no encoding, normalization or interpretation is performed.
    public let bytes: [UInt8]
    /// The representation context and version.
    public let context: Context

    /// Maximum admitted role length in UTF-8 bytes.
    public static let maximumRoleBytes = 64
    /// Maximum admitted opaque identity length in bytes.
    public static let maximumIdentityBytes = 256

    /// Admits a role, opaque bytes and closed representation context.
    ///
    /// Role bytes are ASCII letters, digits, underscore, hyphen or period.
    /// Empty opaque bytes are permitted; the host decides whether they identify
    /// a meaningful policy. The capacities are Liquid admission limits, not a
    /// Content issuance rule or an aggregate invocation budget.
    /// - Throws: `CancellationError` or ``AdmissionError``.
    public init(role: String, bytes: [UInt8], context: Context) throws {
        try Task.checkCancellation()
        let roleBytes = role.utf8
        guard !roleBytes.isEmpty, roleBytes.count <= Self.maximumRoleBytes,
              roleBytes.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte) ||
                  (48...57).contains(byte) || byte == 95 || byte == 45 || byte == 46
              }) else { throw AdmissionError.invalidRole }
        guard bytes.count <= Self.maximumIdentityBytes else { throw AdmissionError.identityTooLong }
        try Task.checkCancellation()
        self.role = role
        self.bytes = bytes
        self.context = context
    }
}
