// SPDX-License-Identifier: Apache-2.0

/// An explicitly exposed, asynchronously computed property of a host object.
///
/// The callback is trusted application code. Its captures must be Sendable, and
/// it may run concurrently when an engine is shared by multiple renders.
public struct LiquidHostProperty: Sendable {
    /// The exact Unicode-scalar spelling of the property name.
    public let name: String
    internal let body: @Sendable () async throws -> LiquidValue

    /// Creates a property. Duplicate names are rejected when rendering begins.
    /// - Parameters:
    ///   - name: An explicitly exposed property name.
    ///   - body: Computes one admitted Liquid value for this access.
    public init(_ name: String, body: @escaping @Sendable () async throws -> LiquidValue) {
        self.name = name
        self.body = body
    }
}

/// A bounded family of explicitly exposed host properties.
///
/// The exact UTF-8 prefix limits which keys are passed to trusted host code.
/// A nil return means the requested property is missing; `.null` is an
/// explicitly returned Liquid null. Callbacks must be safe for concurrent use.
public struct LiquidHostDynamicProperty: Sendable {
    /// Nonempty exact UTF-8 prefix of the exposed property family.
    public let prefix: String
    internal let body: @Sendable (String) async throws -> LiquidValue?

    /// Creates a dynamic property family. Duplicate or empty prefixes fail admission.
    /// - Parameters:
    ///   - prefix: Exact nonempty prefix admitted by the host.
    ///   - body: Computes a value for one matching property key.
    public init(prefix: String, body: @escaping @Sendable (String) async throws -> LiquidValue?) {
        self.prefix = prefix
        self.body = body
    }
}

/// A typed key supplied to an explicitly registered host indexer.
public enum LiquidHostIndexKey: Sendable, Equatable {
    /// A string key, retaining its exact Unicode spelling.
    case string(String)
    /// An integer key in the native Int domain.
    case integer(Int)
    /// A key of another Liquid type; no coercion is performed.
    case other
}

/// An explicit asynchronous handler for host-object indexing.
///
/// The handler is trusted application code and must enforce its own exposure
/// policy. All string and integer keys, and the `other` category, can reach it.
public struct LiquidHostIndexer: Sendable {
    internal let body: @Sendable (LiquidHostIndexKey) async throws -> LiquidValue?

    /// Creates an indexer. Return nil for a missing value or `.null` for Liquid null.
    /// - Parameter body: Computes one admitted value for the typed key.
    public init(_ body: @escaping @Sendable (LiquidHostIndexKey) async throws -> LiquidValue?) {
        self.body = body
    }
}

/// One explicitly named nested-node operation.
public struct LiquidHostNodeProperty: Sendable {
    /// The exact property name; validated when the node is admitted.
    public let name: String
    internal let body: @Sendable () async throws -> LiquidHostNodeResult

    /// Creates an asynchronous operation returning a value, node, self or missing.
    public init(_ name: String, _ body: @escaping @Sendable () async throws -> LiquidHostNodeResult) {
        self.name = name
        self.body = body
    }
}

/// The result of one explicit nested-node operation.
public enum LiquidHostNodeResult: Sendable {
    /// An ordinary typed Liquid value.
    case value(LiquidValue)
    /// A separately supplied node; copies retain its identity.
    case node(LiquidHostNode)
    /// The current node, preserving its identity and admitted capabilities.
    case current
    /// A missing property.
    case missing
}

internal final class RuntimeHostNodeIdentity: Sendable {}

/// An explicit integer-valued host node with bounded property access.
///
/// The integer is used for rendering, truthiness and comparison; this profile
/// does not declare a Ruby `to_number` conversion. Property callbacks are trusted
/// Sendable application code and are invoked only for explicit names.
public struct LiquidHostNode: Sendable {
    internal let integerValue: Int
    internal let properties: [LiquidHostNodeProperty]
    internal let identity = RuntimeHostNodeIdentity()

    /// Creates a node. Property names and limits are validated on admission.
    /// - Parameters:
    ///   - integerValue: Integer represented by the node.
    ///   - properties: Explicit operations in declaration order.
    public init(integerValue: Int, properties: [LiquidHostNodeProperty] = []) {
        self.integerValue = integerValue
        self.properties = properties
    }
}

/// One element in an explicitly supplied host array.
///
/// Boxed strings retain object behavior; ordinary values use `LiquidValue`.
/// Host arrays do not admit arbitrary nested host objects.
public enum LiquidHostArrayElement: Sendable {
    /// An ordinary Liquid value, including an ordinary array or object.
    case value(LiquidValue)
    /// A string-backed host object; nil represents a missing string value.
    case boxedString(String?)
}

internal final class RuntimeHostStringIdentity: Sendable {}

internal struct LiquidHostStringBox: Sendable {
    let value: String?
    let identity = RuntimeHostStringIdentity()
}

internal struct LiquidHostSequenceBox: Sendable {
    let values: [LiquidValue]
    let displayName: String
}

/// A named root binding exposing only explicitly supplied host properties.
///
/// Exact and dynamic properties use string keys; an optional indexer accepts
/// typed string and integer keys. Explicit boxed values, nested nodes and finite
/// sequences participate in value operations. Other objects require property access.
/// Ordinary host properties return Liquid values; explicit node properties can return nodes.
public struct LiquidHostObject: Sendable {
    /// The exact name of the root binding supplied to a render.
    public let name: String
    internal let properties: [LiquidHostProperty]
    internal let dynamicProperties: [LiquidHostDynamicProperty]
    internal let indexer: LiquidHostIndexer?
    internal let booleanValue: Bool?
    internal let numberValue: Int?
    internal let stringValue: LiquidHostStringBox?
    internal let arrayValues: [LiquidHostArrayElement]?
    internal let sequenceValue: LiquidHostSequenceBox?
    internal let nodeValue: LiquidHostNode?

    /// Creates a host binding. Names and collisions are validated for each render.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - properties: Explicitly exposed properties in declaration order.
    public init(_ name: String, properties: [LiquidHostProperty]) {
        self.name = name
        self.properties = properties
        self.dynamicProperties = []
        self.indexer = nil
        self.booleanValue = nil
        self.numberValue = nil
        self.stringValue = nil
        self.arrayValues = nil
        self.sequenceValue = nil
        self.nodeValue = nil
    }

    /// Creates a binding with exact properties and explicitly scoped dynamic families.
    /// Exact properties take precedence; among matching families the longest
    /// exact UTF-8 prefix wins. A missing result does not try another family.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - properties: Explicit exact properties.
    ///   - dynamicProperties: Nonempty-prefix property families.
    public init(_ name: String, properties: [LiquidHostProperty] = [], dynamicProperties: [LiquidHostDynamicProperty]) {
        self.name = name
        self.properties = properties
        self.dynamicProperties = dynamicProperties
        self.indexer = nil
        self.booleanValue = nil
        self.numberValue = nil
        self.stringValue = nil
        self.arrayValues = nil
        self.sequenceValue = nil
        self.nodeValue = nil
    }

    /// Creates a host binding with an explicit typed-key indexer.
    /// Exact and dynamic string properties have precedence over the indexer.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - properties: Explicit exact string properties.
    ///   - dynamicProperties: Explicit nonempty-prefix string property families.
    ///   - indexer: Trusted handler for otherwise unhandled typed keys.
    public init(_ name: String, properties: [LiquidHostProperty] = [],
                dynamicProperties: [LiquidHostDynamicProperty] = [], indexer: LiquidHostIndexer) {
        self.name = name
        self.properties = properties
        self.dynamicProperties = dynamicProperties
        self.indexer = indexer
        self.booleanValue = nil
        self.numberValue = nil
        self.stringValue = nil
        self.arrayValues = nil
        self.sequenceValue = nil
        self.nodeValue = nil
    }

    /// Creates a boxed Boolean host binding with no exposed properties.
    /// Boolean value operations use `booleanValue`, while property access
    /// remains object access and yields a missing value for every key.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - booleanValue: Boolean represented by this host object.
    public init(_ name: String, booleanValue: Bool) {
        self.name = name
        self.properties = []
        self.dynamicProperties = []
        self.indexer = nil
        self.booleanValue = booleanValue
        self.numberValue = nil
        self.stringValue = nil
        self.arrayValues = nil
        self.sequenceValue = nil
        self.nodeValue = nil
    }

    /// Creates a boxed integer host binding with no exposed properties.
    /// Numeric value operations use `numberValue`; property access remains
    /// object access and yields a missing value for every key.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - numberValue: Native-width integer represented by this host object.
    public init(_ name: String, numberValue: Int) {
        self.name = name
        self.properties = []
        self.dynamicProperties = []
        self.indexer = nil
        self.booleanValue = nil
        self.numberValue = numberValue
        self.stringValue = nil
        self.arrayValues = nil
        self.sequenceValue = nil
        self.nodeValue = nil
    }

    /// Creates a boxed string host binding with no exposed properties.
    /// A nil value follows the boxed-string nil behavior, including a failed
    /// direct string conversion; it is not an ordinary null input.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - stringValue: String represented by this host object, or nil.
    public init(_ name: String, stringValue: String?) {
        self.name = name
        self.properties = []
        self.dynamicProperties = []
        self.indexer = nil
        self.booleanValue = nil
        self.numberValue = nil
        self.stringValue = LiquidHostStringBox(value: stringValue)
        self.arrayValues = nil
        self.sequenceValue = nil
        self.nodeValue = nil
    }

    /// Creates an explicit finite root array containing ordinary values and
    /// boxed string elements. It does not expose arbitrary host objects.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - array: Ordered elements admitted separately for each render.
    public init(_ name: String, array: [LiquidHostArrayElement]) {
        self.name = name
        self.properties = []
        self.dynamicProperties = []
        self.indexer = nil
        self.booleanValue = nil
        self.numberValue = nil
        self.stringValue = nil
        self.arrayValues = array
        self.sequenceValue = nil
        self.nodeValue = nil
    }

    /// Creates a finite, immutable, invocation-admitted host sequence.
    /// Elements are ordinary Liquid values. Iteration and admission use the
    /// operation's work, value, depth and cancellation limits.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - sequence: Ordered snapshot of ordinary Liquid values.
    ///   - displayName: Text rendered for the sequence object itself.
    public init(_ name: String, sequence: [LiquidValue], displayName: String = "LiquidHostSequence") {
        self.name = name
        self.properties = []
        self.dynamicProperties = []
        self.indexer = nil
        self.booleanValue = nil
        self.numberValue = nil
        self.stringValue = nil
        self.arrayValues = nil
        self.sequenceValue = LiquidHostSequenceBox(values: sequence, displayName: displayName)
        self.nodeValue = nil
    }

    /// Creates a root binding for an explicitly supplied nested host node.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - node: Integer-valued node with explicitly registered operations.
    public init(_ name: String, node: LiquidHostNode) {
        self.name = name
        self.properties = []
        self.dynamicProperties = []
        self.indexer = nil
        self.booleanValue = nil
        self.numberValue = nil
        self.stringValue = nil
        self.arrayValues = nil
        self.sequenceValue = nil
        self.nodeValue = node
    }
}
