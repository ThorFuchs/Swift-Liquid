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

/// A named root binding exposing only explicitly supplied host properties.
///
/// This first profile supports string-keyed property access. The object itself
/// is not a Liquid value: output, conditions, filters and assignments must use a
/// property. Host objects cannot be returned by a property in this profile.
public struct LiquidHostObject: Sendable {
    /// The exact name of the root binding supplied to a render.
    public let name: String
    internal let properties: [LiquidHostProperty]
    internal let dynamicProperties: [LiquidHostDynamicProperty]

    /// Creates a host binding. Names and collisions are validated for each render.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - properties: Explicitly exposed properties in declaration order.
    public init(_ name: String, properties: [LiquidHostProperty]) {
        self.name = name
        self.properties = properties
        self.dynamicProperties = []
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
    }
}
