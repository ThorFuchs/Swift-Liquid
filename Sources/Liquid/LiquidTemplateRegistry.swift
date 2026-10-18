// SPDX-License-Identifier: Apache-2.0

/// An immutable, ordered collection of byte-exact names and explicit template content.
///
/// Canonically equivalent Swift strings may name different entries. No name is
/// normalized, decoded, interpreted as a path, or used for implicit I/O. This
/// registry is an identity primitive, not an authorization check or a renderer.
/// Construction admits names only; it neither parses raw content nor qualifies
/// cumulative template source bytes for a later engine operation.
public struct LiquidTemplateRegistry: Sendable {
    /// Caller-owned source or an already parsed immutable template.
    public enum Content: Sendable {
        /// Original source, retained without parsing or source-capacity admission.
        case raw(String)
        /// A reusable template, retained without reparsing or changing parser mode.
        case parsed(LiquidTemplate)
    }

    /// One opaque name and its immutable content, in caller declaration order.
    public struct Entry: Sendable {
        /// Original spelling; identity compares its UTF-8 bytes, not String equality.
        public let name: String
        /// Explicit content, never loaded from a filesystem or network.
        public let content: Content

        /// Creates a declaration; registry construction performs name admission.
        /// - Parameters:
        ///   - name: Opaque name, including an empty string if capacities permit.
        ///   - content: Raw source or an immutable parsed template.
        public init(_ name: String, _ content: Content) {
            self.name = name
            self.content = content
        }
    }

    /// Finite name capacities. Zero permits only the corresponding empty use.
    /// Negative values are rejected when constructing a registry, after cancellation.
    public struct Limits: Sendable {
        /// Maximum registry entries; a later engine root is not an entry here.
        public let entryCount: Int
        /// Maximum sum of every original entry name's UTF-8 bytes.
        public let totalNameUTF8Bytes: Int
        /// Maximum UTF-8 bytes in each declared or requested name.
        public let nameUTF8Bytes: Int

        /// Creates a capacity profile, validated by registry construction.
        /// - Parameters:
        ///   - entryCount: Nonnegative maximum number of entries.
        ///   - totalNameUTF8Bytes: Nonnegative aggregate declared-name byte capacity.
        ///   - nameUTF8Bytes: Nonnegative per-name and lookup byte capacity.
        public init(entryCount: Int = 4_096, totalNameUTF8Bytes: Int = 262_144,
                    nameUTF8Bytes: Int = 1_024) {
            self.entryCount = entryCount
            self.totalNameUTF8Bytes = totalNameUTF8Bytes
            self.nameUTF8Bytes = nameUTF8Bytes
        }

        /// The default 4,096 entries, 262,144 total bytes and 1,024 bytes per name.
        public static let `default` = Self()
    }

    /// The specific logical name capacity that rejected an admission or lookup.
    public enum Capacity: String, Sendable {
        /// The number of registry entries exceeded its profile.
        case entryCount
        /// The aggregate declared-name bytes exceeded their profile.
        case totalNameUTF8Bytes
        /// A declared or requested name exceeded its per-name profile.
        case nameUTF8Bytes
    }

    /// Terminal registry admission failures, distinct from a missing lookup.
    /// Raw duplicate names may contain private caller data; hosts choose safe logging.
    public enum AdmissionError: Error, Sendable {
        /// At least one configured capacity was negative.
        case invalidLimits
        /// A second declaration had the same exact UTF-8 spelling.
        /// - Parameter name: The second declaration's unmodified name.
        case duplicateName(_ name: String)
        /// A configured name capacity was exceeded; this is never a missing result.
        /// - Parameter capacity: The capacity responsible for rejection.
        case limitExceeded(_ capacity: Capacity)
    }

    /// A successful selection from this registry snapshot.
    public struct Resolved: Sendable {
        /// Zero-based declaration index, meaningful only within this snapshot.
        public let entryIndex: Int
        /// Actual stored spelling, including a selected `.liquid` suffix.
        public let name: String
        /// The selected declaration's immutable raw or parsed content.
        public let content: Content
    }

    /// Original ordered declarations as a read-only copy-on-write value snapshot.
    public let entries: [Entry]
    /// Number of declarations, including unused entries and canonical siblings.
    public var count: Int { entries.count }
    private let index: [ScalarKey: Int]
    private let nameUTF8Bytes: Int

    /// Admits names in caller order without parsing any content.
    /// Cancellation precedes invalid limits, then count, then per-entry name bytes,
    /// aggregate bytes and exact duplicates. No partially admitted registry escapes.
    /// - Parameters:
    ///   - entries: Ordered declarations; only identical UTF-8 name bytes conflict.
    ///   - limits: Finite name/count capacities, separate from engine source limits.
    /// - Throws: `CancellationError` or a typed ``AdmissionError``.
    public init(_ entries: [Entry], limits: Limits = .default) throws {
        let index = try Self.admittedIndex(entries, limits: limits)
        self.entries = entries
        self.index = index
        self.nameUTF8Bytes = limits.nameUTF8Bytes
    }

    /// Selects an exact name, then only on miss appends literal ASCII `.liquid`.
    /// Returns the stored name/index/content or nil; canonical siblings never match.
    /// An impossible suffix is skipped before allocation. Byte scans poll cancellation;
    /// standard dictionary hashing/equality is synchronous, with checks around access.
    /// This performs no context lookup, parsing, I/O or authorization decision.
    /// - Parameter requestedName: Opaque requested spelling, bounded by this profile.
    /// - Returns: The selected stored entry, or nil if neither exact candidate exists.
    /// - Throws: `CancellationError`, or ``AdmissionError/limitExceeded(_:)`` for an
    ///   overlong request; terminal failures are never converted to nil.
    public func resolve(_ requestedName: String) throws -> Resolved? {
        let bytes = try Self.admittedNameBytes(requestedName.utf8, maximum: nameUTF8Bytes)
        if let entryIndex = index[ScalarKey(requestedName)] {
            return try resolved(entryIndex)
        }
        try Task.checkCancellation()
        // Admission proves bytes <= nameUTF8Bytes. Subtraction cannot overflow.
        guard nameUTF8Bytes - bytes >= 7 else { return nil }
        let candidate = requestedName + ".liquid"
        try Task.checkCancellation()
        let entryIndex = index[ScalarKey(candidate)]
        try Task.checkCancellation()
        return try entryIndex.map { try resolved($0) }
    }

    private func resolved(_ entryIndex: Int) throws -> Resolved {
        try Task.checkCancellation()
        let entry = entries[entryIndex]
        return Resolved(entryIndex: entryIndex, name: entry.name, content: entry.content)
    }

    // Collection/Sequence helpers keep the public array path auditable and allow
    // deterministic cancellation/bounded-iteration controls without runtime hooks.
    internal static func admittedIndex<Entries: Collection>(
        _ entries: Entries, limits: Limits
    ) throws -> [ScalarKey: Int] where Entries.Element == Entry {
        try Task.checkCancellation()
        guard limits.entryCount >= 0, limits.totalNameUTF8Bytes >= 0,
              limits.nameUTF8Bytes >= 0 else { throw AdmissionError.invalidLimits }
        guard entries.count <= limits.entryCount else {
            throw AdmissionError.limitExceeded(.entryCount)
        }
        var remaining = limits.totalNameUTF8Bytes
        var index: [ScalarKey: Int] = [:]
        index.reserveCapacity(entries.count)
        for (offset, entry) in entries.enumerated() {
            try Task.checkCancellation()
            let bytes = try admittedNameBytes(entry.name.utf8, maximum: limits.nameUTF8Bytes)
            guard bytes <= remaining else {
                throw AdmissionError.limitExceeded(.totalNameUTF8Bytes)
            }
            remaining -= bytes
            let previous = index.updateValue(offset, forKey: ScalarKey(entry.name))
            try Task.checkCancellation()
            if previous != nil {
                throw AdmissionError.duplicateName(entry.name)
            }
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
        return index
    }

    internal static func admittedNameBytes<Bytes: Sequence>(
        _ bytes: Bytes, maximum: Int
    ) throws -> Int where Bytes.Element == UInt8 {
        try Task.checkCancellation()
        var remaining = maximum
        var untilPoll = 0
        for _ in bytes {
            if untilPoll == 0 {
                try Task.checkCancellation()
                untilPoll = 64
            }
            guard remaining > 0 else {
                try Task.checkCancellation()
                throw AdmissionError.limitExceeded(.nameUTF8Bytes)
            }
            remaining -= 1
            untilPoll -= 1
        }
        try Task.checkCancellation()
        return maximum - remaining
    }
}
