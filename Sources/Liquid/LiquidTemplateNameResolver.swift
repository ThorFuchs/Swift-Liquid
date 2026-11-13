// SPDX-License-Identifier: Apache-2.0

/// A host's policy for selecting a name from an explicitly supplied partial map.
///
/// The callback is trusted application code and can run concurrently across
/// independent render invocations. It maps a requested Liquid name to a stored
/// source name; it cannot supply a new source or bypass source admission.
public struct LiquidTemplateNameResolver: Sendable {
    internal let select: @Sendable (String) -> String?
    internal let missing: @Sendable (String) -> String

    /// Creates an immutable name policy.
    /// - Parameters:
    ///   - select: Maps a requested name to an existing supplied source name.
    ///   - missing: Produces the recoverable Liquid error for an absent name.
    public init(select: @escaping @Sendable (String) -> String?,
                missing: @escaping @Sendable (String) -> String) {
        self.select = select
        self.missing = missing
    }
}
