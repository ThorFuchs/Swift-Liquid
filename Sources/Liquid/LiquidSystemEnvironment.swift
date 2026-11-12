// SPDX-License-Identifier: Apache-2.0

/// A resident system value declaration. Construction alone is not admission.
public indirect enum LiquidSystemValue: Sendable {
    /// An ordinary Liquid value, including an ordinary recursive container.
    case ordinary(LiquidValue)
    /// An array whose selected children may retain their own declarations.
    case array([LiquidSystemValue])
    /// An ordered object whose selected children may retain their declarations.
    case object([Entry])
    /// A primary value accompanied by resident optional products.
    case decorated(Decoration)

    /// An exact-name member and its explicitly supplied value.
    public struct Entry: Sendable {
        /// Exact UTF-8 spelling of the member name.
        public let name: String
        /// Resident value declared under this name.
        public let value: LiquidSystemValue
        /// Creates a declaration; environment admission checks its name and value.
        /// - Parameters:
        ///   - name: Exact UTF-8 member name.
        ///   - value: Resident value declaration.
        public init(_ name: String, _ value: LiquidSystemValue) {
            self.name = name; self.value = value
        }
    }

    /// A resident plain-text representation or its explicit unavailable state.
    public enum Plain: Sendable {
        /// Resident plain text; this does not carry HTML trust.
        case qualified(String)
        /// The representation was not requested.
        case notRequested
        /// The representation is unavailable, with a bounded caller-supplied reason.
        case unavailable(String)
        /// An optional preparation failed, with a bounded caller-supplied reason.
        case optionalFailure(String)
    }

    /// A resident qualified HTML payload or its explicit unavailable state.
    public enum HTML: Sendable {
        /// Resident HTML payload with an explicit context and policy identity.
        case qualified(String, LiquidSystemPolicyIdentity)
        /// The representation was not requested.
        case notRequested
        /// The representation is unavailable, with a bounded caller-supplied reason.
        case unavailable(String)
        /// An optional preparation failed, with a bounded caller-supplied reason.
        case optionalFailure(String)
    }

    /// Products are caller assertions, not Content issuance certificates.
    public struct Decoration: Sendable {
        /// The primary value used by ordinary Liquid operations.
        public let primary: LiquidSystemValue
        /// An admitted view, or nil when no descriptor was admitted.
        public let descriptor: LiquidSystemDescriptor?
        /// Resident plain-text state.
        public let plain: Plain
        /// Resident HTML text-node representation state.
        public let htmlText: HTML
        /// Resident DIV-flow HTML representation state.
        public let html: HTML
        /// Creates a declaration; environment admission validates the entire tree.
        /// - Parameters:
        ///   - primary: The ordinary primary value or container.
        ///   - descriptor: Optional admitted descriptor view.
        ///   - plain: Plain-text representation state.
        ///   - htmlText: HTML text-node representation state.
        ///   - html: HTML flow-fragment representation state.
        public init(primary: LiquidSystemValue, descriptor: LiquidSystemDescriptor? = nil,
                    plain: Plain = .notRequested, htmlText: HTML = .notRequested,
                    html: HTML = .notRequested) {
            self.primary = primary; self.descriptor = descriptor; self.plain = plain
            self.htmlText = htmlText; self.html = html
        }
    }
}

/// An immutable, finite admitted tree of named resident values.
///
/// Admission validates structure and quotas; it does not confer Content
/// provenance, authorize a host placement, or establish a shared Content ledger.
public struct LiquidSystemEnvironment: Sendable {
    /// Independent, inclusive construction capacities. Zero permits empty use.
    public struct Limits: Sendable {
        /// Maximum value-node occurrences, including wrappers and their primaries.
        public let nodes: Int
        /// Maximum root-relative value depth, at most 128.
        public let depth: Int
        /// Maximum aggregate UTF-8 bytes for primary strings and member names.
        public let textBytes: Int
        /// Maximum descriptor-field occurrences.
        public let descriptorFields: Int
        /// Maximum UTF-8 bytes in descriptor fields and values.
        public let descriptorBytes: Int
        /// Maximum requested or unavailable representation slots.
        public let representationSlots: Int
        /// Maximum representation and diagnostic-reason UTF-8 bytes.
        public let representationBytes: Int
        /// Maximum role and opaque identity bytes across qualified slots.
        public let identityBytes: Int
        /// Maximum UTF-8 bytes in one unavailability reason.
        public let reasonBytes: Int
        /// Maximum documented logical retained weight, not an RSS measurement.
        public let retainedBytes: Int
        /// Maximum construction steps, independent of elapsed time.
        public let work: Int
        /// Creates inclusive construction capacities; all accept zero.
        /// - Parameters:
        ///   - nodes: Maximum value occurrences.
        ///   - depth: Maximum root-relative value depth, at most 128.
        ///   - textBytes: Aggregate primary text and member-name bytes.
        ///   - descriptorFields: Maximum descriptor-field occurrences.
        ///   - descriptorBytes: Aggregate descriptor UTF-8 bytes.
        ///   - representationSlots: Maximum requested or unavailable slots.
        ///   - representationBytes: Aggregate representation and reason bytes.
        ///   - identityBytes: Aggregate policy identity bytes.
        ///   - reasonBytes: Maximum bytes in one reason.
        ///   - retainedBytes: Maximum logical retained weight.
        ///   - work: Maximum construction steps.
        public init(nodes: Int = 100_000, depth: Int = 64, textBytes: Int = 8_388_608,
                    descriptorFields: Int = 10_000, descriptorBytes: Int = 1_048_576,
                    representationSlots: Int = 10_000, representationBytes: Int = 8_388_608,
                    identityBytes: Int = 1_048_576, reasonBytes: Int = 1_024,
                    retainedBytes: Int = 67_108_864, work: Int = 1_000_000) {
            self.nodes = nodes; self.depth = depth; self.textBytes = textBytes
            self.descriptorFields = descriptorFields; self.descriptorBytes = descriptorBytes
            self.representationSlots = representationSlots; self.representationBytes = representationBytes
            self.identityBytes = identityBytes; self.reasonBytes = reasonBytes
            self.retainedBytes = retainedBytes; self.work = work
        }
        /// The documented default construction capacities.
        public static let `default` = Self()
    }

    /// Finite admission and structural errors; cancellation remains separate.
    public enum AdmissionError: Error, Sendable, Equatable {
        /// Negative limits or a depth beyond 128 were supplied.
        case invalidLimits
        /// An object or root contains an identical UTF-8 member name twice.
        case duplicateName
        /// A non-finite ordinary number was supplied.
        case invalidNumber
        /// A decoration directly wraps another decoration.
        case nestedDecoration
        /// A qualified payload identity targets a different HTML context.
        case invalidRepresentationContext
        /// The named finite construction capacity was exceeded.
        case limitExceeded(String)
    }

    /// Admitted roots in caller order with exact, non-normalized names.
    public let entries: [LiquidSystemValue.Entry]

    /// Admits every reachable occurrence, including repeated aliases.
    /// - Parameters:
    ///   - entries: Ordered named resident value declarations.
    ///   - limits: Independent finite construction capacities.
    /// - Throws: `CancellationError` or ``AdmissionError``.
    public init(_ entries: [LiquidSystemValue.Entry], limits: Limits = .default) throws {
        try Task.checkCancellation()
        guard [limits.nodes, limits.depth, limits.textBytes, limits.descriptorFields,
               limits.descriptorBytes, limits.representationSlots, limits.representationBytes,
               limits.identityBytes, limits.reasonBytes, limits.retainedBytes, limits.work].allSatisfy({ $0 >= 0 }), limits.depth <= 128 else {
            throw AdmissionError.invalidLimits
        }
        var admission = SystemEnvironmentAdmission(limits: limits)
        try admission.entries(entries, depth: 1)
        try Task.checkCancellation()
        self.entries = entries
    }
}

private struct SystemEnvironmentAdmission {
    let limits: LiquidSystemEnvironment.Limits
    var nodes = 0, textBytes = 0, fields = 0, descriptorBytes = 0
    var slots = 0, representationBytes = 0, identityBytes = 0, retainedBytes = 0, work = 0

    static func charge(_ amount: Int, into value: inout Int, maximum: Int, label: String) throws {
        let (next, overflow) = value.addingReportingOverflow(amount)
        guard !overflow, next <= maximum else { throw LiquidSystemEnvironment.AdmissionError.limitExceeded(label) }
        value = next
    }

    mutating func step() throws {
        try Task.checkCancellation()
        try Self.charge(1, into: &work, maximum: limits.work, label: "systemWork")
    }

    mutating func retain(_ amount: Int) throws {
        try Self.charge(amount, into: &retainedBytes, maximum: limits.retainedBytes, label: "systemRetainedBytes")
    }

    mutating func entries(_ members: [LiquidSystemValue.Entry], depth: Int) throws {
        var names = Set<ScalarKey>()
        for entry in members {
            try step()
            try Self.charge(entry.name.utf8.count, into: &textBytes, maximum: limits.textBytes, label: "systemTextBytes")
            try retain(32)
            try retain(entry.name.utf8.count)
            guard names.insert(ScalarKey(entry.name)).inserted else { throw LiquidSystemEnvironment.AdmissionError.duplicateName }
            try value(entry.value, depth: depth)
        }
    }

    mutating func value(_ item: LiquidSystemValue, depth: Int) throws {
        try step()
        guard depth <= limits.depth else { throw LiquidSystemEnvironment.AdmissionError.limitExceeded("systemDepth") }
        try Self.charge(1, into: &nodes, maximum: limits.nodes, label: "systemNodes")
        try retain(64)
        switch item {
        case .ordinary(let ordinary): try ordinaryValue(ordinary, depth: depth, count: false)
        case .array(let children):
            for child in children { try value(child, depth: depth + 1) }
        case .object(let members): try entries(members, depth: depth + 1)
        case .decorated(let decoration):
            if case .decorated = decoration.primary { throw LiquidSystemEnvironment.AdmissionError.nestedDecoration }
            if let descriptor = decoration.descriptor {
                for entry in descriptor.entries {
                    try step()
                    try Self.charge(1, into: &fields, maximum: limits.descriptorFields, label: "systemDescriptorFields")
                    try Self.charge(entry.name.utf8.count, into: &descriptorBytes, maximum: limits.descriptorBytes, label: "systemDescriptorBytes")
                    try retain(64)
                    try retain(entry.name.utf8.count)
                    switch entry.value {
                    case .text(let text): try descriptorText(text)
                    case .boolean: break
                    case .typeNames(let values): for text in values { try descriptorText(text) }
                    }
                }
            }
            try plain(decoration.plain)
            try html(decoration.htmlText, context: .htmlTextV1)
            try html(decoration.html, context: .htmlFlowFragmentV1)
            try value(decoration.primary, depth: depth + 1)
        }
    }

    mutating func descriptorText(_ text: String) throws {
        try step()
        try Self.charge(text.utf8.count, into: &descriptorBytes, maximum: limits.descriptorBytes, label: "systemDescriptorBytes")
        try retain(text.utf8.count)
    }

    mutating func slot() throws {
        try step()
        try Self.charge(1, into: &slots, maximum: limits.representationSlots, label: "systemRepresentationSlots")
        try retain(128)
    }

    mutating func payload(_ text: String) throws {
        try Self.charge(text.utf8.count, into: &representationBytes, maximum: limits.representationBytes, label: "systemRepresentationBytes")
        try retain(text.utf8.count)
    }

    mutating func plain(_ value: LiquidSystemValue.Plain) throws {
        switch value {
        case .qualified(let text): try slot(); try payload(text)
        case .unavailable(let text), .optionalFailure(let text): try slot(); try reason(text)
        case .notRequested: break
        }
    }

    mutating func html(_ value: LiquidSystemValue.HTML, context: LiquidSystemPolicyIdentity.Context) throws {
        switch value {
        case .qualified(let text, let identity):
            try slot()
            guard identity.context == context else { throw LiquidSystemEnvironment.AdmissionError.invalidRepresentationContext }
            try payload(text)
            let (count, overflow) = identity.role.utf8.count.addingReportingOverflow(identity.bytes.count)
            guard !overflow else { throw LiquidSystemEnvironment.AdmissionError.limitExceeded("systemIdentityBytes") }
            try Self.charge(count, into: &identityBytes, maximum: limits.identityBytes, label: "systemIdentityBytes")
            try retain(count)
        case .unavailable(let text), .optionalFailure(let text): try slot(); try reason(text)
        case .notRequested: break
        }
    }

    mutating func reason(_ text: String) throws {
        try step()
        guard text.utf8.count <= limits.reasonBytes else { throw LiquidSystemEnvironment.AdmissionError.limitExceeded("systemReasonBytes") }
        try payload(text)
    }

    mutating func ordinaryValue(_ item: LiquidValue, depth: Int, count: Bool = true) throws {
        try step()
        guard depth <= limits.depth else { throw LiquidSystemEnvironment.AdmissionError.limitExceeded("systemDepth") }
        if count {
            try Self.charge(1, into: &nodes, maximum: limits.nodes, label: "systemNodes")
            try retain(64)
        }
        switch item {
        case .null, .bool, .integer: break
        case .number(let number): guard number.isFinite else { throw LiquidSystemEnvironment.AdmissionError.invalidNumber }
        case .string(let text):
            try Self.charge(text.utf8.count, into: &textBytes, maximum: limits.textBytes, label: "systemTextBytes")
            try retain(text.utf8.count)
        case .array(let children): for child in children { try ordinaryValue(child, depth: depth + 1) }
        case .object(let object):
            for entry in object.entries {
                try step()
                try Self.charge(entry.key.utf8.count, into: &textBytes, maximum: limits.textBytes, label: "systemTextBytes")
                try retain(32)
                try retain(entry.key.utf8.count)
                try ordinaryValue(entry.value, depth: depth + 1)
            }
        }
    }
}
