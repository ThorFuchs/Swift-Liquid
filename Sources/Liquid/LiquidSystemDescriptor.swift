// SPDX-License-Identifier: Apache-2.0

/// A bounded, immutable view of explicitly supplied descriptor fields.
///
/// This carrier does not establish Content provenance or determine whether an
/// absent descriptor may be accessed. Only admitted fields are present.
public struct LiquidSystemDescriptor: Sendable, Equatable {
    /// One of the closed public descriptor value kinds.
    public enum Value: Sendable, Equatable {
        /// A text field.
        case text(String)
        /// An ordered list of type-name strings.
        case typeNames([String])
        /// A known boolean field.
        case boolean(Bool)
    }

    /// One declared field, in caller order.
    public struct Entry: Sendable, Equatable {
        /// The exact field name.
        public let name: String
        /// The supplied field value.
        public let value: Value
        /// Creates a declaration. Validation occurs during descriptor admission.
        public init(_ name: String, _ value: Value) {
            self.name = name
            self.value = value
        }
    }

    /// Per-descriptor capacities. Zero is a valid empty capacity.
    public struct Limits: Sendable, Equatable {
        /// Maximum admitted fields.
        public let fields: Int
        /// Aggregate UTF-8 bytes of field names and text values.
        public let textBytes: Int
        /// Maximum aggregate number of type-name elements.
        public let typeNames: Int
        /// Creates capacities checked at admission.
        public init(fields: Int = 7, textBytes: Int = 1_048_576, typeNames: Int = 1_024) {
            self.fields = fields
            self.textBytes = textBytes
            self.typeNames = typeNames
        }
        /// Default per-descriptor capacities.
        public static let `default` = Self()
    }

    /// A descriptor admission failure.
    public enum AdmissionError: Error, Sendable, Equatable {
        /// At least one configured capacity is negative.
        case invalidLimits
        /// A field is not in the closed vocabulary.
        case unknownField
        /// The same field was declared more than once.
        case duplicateField
        /// A value kind is not supported for its field.
        case incorrectValueKind
        /// A finite capacity was exceeded.
        case limitExceeded(String)
    }

    /// Validated entries, retaining caller order.
    public let entries: [Entry]

    /// Validates a closed field set before exposing the immutable view.
    /// Unknown field knowledge is represented by omission, not a null value.
    /// Type-name vocabulary and Content-issued qualification remain host duties.
    /// - Throws: `CancellationError` or ``AdmissionError``.
    public init(_ entries: [Entry], limits: Limits = .default) throws {
        try Task.checkCancellation()
        guard limits.fields >= 0, limits.textBytes >= 0, limits.typeNames >= 0 else {
            throw AdmissionError.invalidLimits
        }
        guard entries.count <= limits.fields else { throw AdmissionError.limitExceeded("fields") }
        var seen = Set<String>()
        var bytes = 0
        var names = 0
        func charge(_ text: String) throws {
            try Task.checkCancellation()
            let (next, overflow) = bytes.addingReportingOverflow(text.utf8.count)
            guard !overflow, next <= limits.textBytes else { throw AdmissionError.limitExceeded("textBytes") }
            bytes = next
        }
        for entry in entries {
            try Task.checkCancellation()
            switch (entry.name, entry.value) {
            case ("title", .text), ("description", .text), ("format", .text),
                 ("type", .typeNames), ("required", .boolean), ("nullable", .boolean),
                 ("deprecated", .boolean): break
            case ("title", _), ("description", _), ("format", _), ("type", _),
                 ("required", _), ("nullable", _), ("deprecated", _):
                throw AdmissionError.incorrectValueKind
            default: throw AdmissionError.unknownField
            }
            guard seen.insert(entry.name).inserted else { throw AdmissionError.duplicateField }
            try charge(entry.name)
            switch entry.value {
            case .text(let text): try charge(text)
            case .boolean: break
            case .typeNames(let values):
                let (next, overflow) = names.addingReportingOverflow(values.count)
                guard !overflow, next <= limits.typeNames else { throw AdmissionError.limitExceeded("typeNames") }
                names = next
                for value in values { try charge(value) }
            }
        }
        try Task.checkCancellation()
        self.entries = entries
    }
}
