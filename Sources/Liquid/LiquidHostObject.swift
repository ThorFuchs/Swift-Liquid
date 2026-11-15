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

/// A named root binding exposing only explicitly supplied host properties.
///
/// This first profile supports string-keyed property access. The object itself
/// is not a Liquid value: output, conditions, filters and assignments must use a
/// property. Host objects cannot be returned by a property in this profile.
public struct LiquidHostObject: Sendable {
    /// The exact name of the root binding supplied to a render.
    public let name: String
    internal let properties: [LiquidHostProperty]

    /// Creates a host binding. Names and collisions are validated for each render.
    /// - Parameters:
    ///   - name: Root binding name, distinct from ordinary context names.
    ///   - properties: Explicitly exposed properties in declaration order.
    public init(_ name: String, properties: [LiquidHostProperty]) {
        self.name = name
        self.properties = properties
    }
}
