// SPDX-License-Identifier: Apache-2.0

/// Finite capacities for dependency inspection, independent of render budgets.
public struct LiquidDependencyLimits: Sendable, Equatable {
    /// Maximum supplied templates, including the root and unused partials.
    public let templates: Int
    /// Maximum aggregate UTF-8 bytes of all supplied partial keys.
    public let nameBytes: Int
    /// Maximum unique literal edges retained from reachable nodes, including missing references.
    public let edges: Int
    /// Creates a profile. Template capacity must be positive; other capacities may be zero.
    /// - Parameters:
    ///   - templates: Maximum supplied templates, including the root and unused partials.
    ///   - nameBytes: Aggregate UTF-8 capacity of every supplied partial key.
    ///   - edges: Maximum retained unique literal edges, including missing references.
    public init(templates: Int = 4_096, nameBytes: Int = 262_144, edges: Int = 65_536) {
        self.templates = templates; self.nameBytes = nameBytes; self.edges = edges
    }
    /// Default finite dependency capacities.
    public static let `default` = LiquidDependencyLimits()

    internal func validate() throws {
        guard templates > 0, nameBytes >= 0, edges >= 0 else {
            throw LiquidError.invalidValue("Dependency limits require templates > 0, nameBytes >= 0 and edges >= 0")
        }
    }
}

/// An identity that keeps the root distinct from every possible supplied partial key.
public enum LiquidDependencyNodeID: Sendable, Hashable {
    /// The explicitly supplied root template.
    case root
    /// The actual key retained in the supplied partial dictionary.
    case partial(String)

    /// Compares exact UTF-8 spelling, without canonical-equivalence folding.
    /// - Parameters:
    ///   - lhs: Left value, compared using exact UTF-8 spellings.
    ///   - rhs: Right value, compared using exact UTF-8 spellings.
    /// - Returns: Whether all identity and retained-content fields are equal.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.root, .root): true
        case (.partial(let a), .partial(let b)): a.utf8.elementsEqual(b.utf8)
        default: false
        }
    }
    /// Hashes exact UTF-8 spelling consistently with identity equality.
    /// - Parameter hasher: Hasher receiving the root discriminator or exact partial-name bytes.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .root: hasher.combine(0)
        case .partial(let name): hasher.combine(1); hasher.combine(ScalarKey(name))
        }
    }
}

/// One reachable template and its existing single-template AST summary.
public struct LiquidDependencyNode: Sendable, Equatable {
    /// Root or actual supplied partial identity.
    public let id: LiquidDependencyNodeID
    /// Retained syntactic reads, filters and partial references.
    public let inspection: LiquidTemplateInspection
}

/// One distinct literal request from one reachable template.
public struct LiquidDependencyEdge: Sendable, Equatable {
    /// Template containing the request.
    public let origin: LiquidDependencyNodeID
    /// Exact literal spelling before lookup or suffix fallback.
    public let requestedName: String
    /// Actual supplied key, or nil when neither lookup candidate exists.
    public let resolvedName: String?

    /// Compares exact UTF-8 spelling for both requested and supplied names.
    /// - Parameters:
    ///   - lhs: Left value, compared using exact UTF-8 spellings.
    ///   - rhs: Right value, compared using exact UTF-8 spellings.
    /// - Returns: Whether all identity and retained-content fields are equal.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        let resolved: Bool
        switch (lhs.resolvedName, rhs.resolvedName) {
        case (nil, nil): resolved = true
        case (.some(let a), .some(let b)): resolved = a.utf8.elementsEqual(b.utf8)
        default: resolved = false
        }
        return lhs.origin == rhs.origin && lhs.requestedName.utf8.elementsEqual(rhs.requestedName.utf8) && resolved
    }
}

/// A deterministic, bounded syntactic graph; findings do not predict render success.
public struct LiquidDependencyInspection: Sendable, Equatable {
    /// Root first, then reachable partials in ascending UTF-8 key order.
    public let nodes: [LiquidDependencyNode]
    /// Ordered by origin node, then exact requested-name bytes. Repeated requests share an edge.
    public let edges: [LiquidDependencyEdge]
    /// Strongly connected groups with multiple members or a self-loop.
    /// Members and groups follow node order; paths and simple cycles are not enumerated.
    public let cycles: [[LiquidDependencyNodeID]]
    /// Missing literal requests in edge order. Missing references are successful findings.
    public var missingReferences: [LiquidDependencyEdge] { edges.filter { $0.resolvedName == nil } }
    /// Nodes containing unresolved dynamic includes, in node order.
    public var dynamicReferences: [LiquidDependencyNodeID] { nodes.filter(\.inspection.hasDynamicPartials).map(\.id) }
}

extension LiquidEngine {
    /// Admits and parses the whole supplied bundle, then inspects literal dependencies reachable from the root.
    /// No expressions, callbacks or context values are evaluated; no I/O is performed.
    /// - Parameters:
    ///   - template: Root Liquid source.
    ///   - templates: Explicit partial sources; unused sources are also admitted and inspected.
    ///   - syntaxMode: Parser mode for every source in this bundle.
    ///   - analysisLimits: Finite template-count, name-byte and edge capacities.
    /// - Throws: Existing Liquid syntax/limit errors or `CancellationError`. No partial result is returned.
    public func inspectDependencies(template: String, templates: [String: String] = [:],
                                    syntaxMode: LiquidSyntaxMode = .lax,
                                    analysisLimits: LiquidDependencyLimits = .default) throws -> LiquidDependencyInspection {
        try admitDependencies(root: template, templates: templates, source: { $0 }, analysisLimits: analysisLimits)
        let root = try LiquidTemplate(template, syntaxMode: syntaxMode, limits: limits)
        var parsed: [String: LiquidTemplate] = [:]
        for key in templates.keys.sorted(by: dependencyNameOrder) {
            try Task.checkCancellation()
            parsed[key] = try LiquidTemplate(templates[key]!, syntaxMode: syntaxMode, limits: limits)
        }
        return try inspectDependencies(root, templates: parsed, analysisLimits: analysisLimits)
    }

    /// Inspects a parsed bundle without reparsing, retaining each template's selected parser mode.
    /// Current cumulative source and syntax-depth limits apply even to unused partials.
    /// - Parameters:
    ///   - template: The reusable root template, distinct from all named partial identities.
    ///   - templates: Explicit parsed partials, including unused templates in admission and inspection.
    ///   - analysisLimits: Finite template-count, name-byte and retained-edge capacities.
    /// - Returns: Deterministically ordered literal-reachable nodes, references and cycle groups.
    /// - Throws: Syntax/depth, invalid-limit, capacity or cancellation errors; no partial graph is returned.
    public func inspectDependencies(_ template: LiquidTemplate, templates: [String: LiquidTemplate] = [:],
                                    analysisLimits: LiquidDependencyLimits = .default) throws -> LiquidDependencyInspection {
        try admitDependencies(root: template.source, templates: templates, source: { $0.source }, analysisLimits: analysisLimits)
        let keys = templates.keys.sorted(by: dependencyNameOrder)
        // String lookup deliberately follows the renderer's canonical-equivalence semantics.
        // The ordered array retains the dictionary's actual stored key spelling.
        var indexes: [String: Int] = [:]
        var summaries = [try inspectTemplate(template.ast, limits: limits)]
        for key in keys {
            try Task.checkCancellation()
            indexes[key] = summaries.count
            summaries.append(try inspectTemplate(templates[key]!.ast, limits: limits))
        }
        func identity(_ index: Int) -> LiquidDependencyNodeID { index == 0 ? .root : .partial(keys[index - 1]) }
        var reachable = Set([0])
        var pending = [0]
        var outgoing = [[LiquidDependencyEdge]](repeating: [], count: summaries.count)
        var adjacency = [[Int]](repeating: [], count: summaries.count)
        var edgeRemaining = analysisLimits.edges
        while let origin = pending.popLast() {
            try Task.checkCancellation()
            for name in summaries[origin].literalPartialNames {
                try Task.checkCancellation()
                guard edgeRemaining > 0 else { throw LiquidError.limitExceeded("dependencyEdges") }
                edgeRemaining -= 1
                let target = indexes[name] ?? indexes[name + ".liquid"]
                outgoing[origin].append(.init(origin: identity(origin), requestedName: name,
                                               resolvedName: target.map { keys[$0 - 1] }))
                if let target {
                    adjacency[origin].append(target)
                    if reachable.insert(target).inserted { pending.append(target) }
                }
            }
        }
        let ordered = reachable.sorted()
        let groups = try dependencyCycles(adjacency, reachable: ordered)
        var nodes: [LiquidDependencyNode] = []
        var edges: [LiquidDependencyEdge] = []
        var cycles: [[LiquidDependencyNodeID]] = []
        for index in ordered {
            try Task.checkCancellation()
            nodes.append(.init(id: identity(index), inspection: summaries[index]))
            edges.append(contentsOf: outgoing[index])
        }
        for group in groups {
            var members: [LiquidDependencyNodeID] = []
            for index in group { try Task.checkCancellation(); members.append(identity(index)) }
            cycles.append(members)
        }
        try Task.checkCancellation()
        return .init(nodes: nodes, edges: edges, cycles: cycles)
    }

    private func admitDependencies<T>(root: String, templates: [String: T], source: (T) -> String,
                                      analysisLimits: LiquidDependencyLimits) throws {
        try Task.checkCancellation()
        try limits.validate()
        try analysisLimits.validate()
        // Compare before adding one, including for Int.max input capacities.
        guard templates.count < analysisLimits.templates else { throw LiquidError.limitExceeded("dependencyTemplates") }
        var nameRemaining = analysisLimits.nameBytes
        var sourceRemaining = limits.sourceBytes
        func admitSource(_ text: String) throws {
            guard text.utf8.count <= sourceRemaining else { throw LiquidError.limitExceeded("sourceBytes") }
            sourceRemaining -= text.utf8.count
        }
        try admitSource(root)
        for (key, value) in templates {
            try Task.checkCancellation()
            guard key.utf8.count <= nameRemaining else { throw LiquidError.limitExceeded("dependencyNameBytes") }
            nameRemaining -= key.utf8.count
            try admitSource(source(value))
        }
    }
}

internal func dependencyNameOrder(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }

/// Iterative Kosaraju traversal followed by deterministic ordering; no recursion or cycle path expansion.
internal func dependencyCycles(_ adjacency: [[Int]], reachable: [Int]) throws -> [[Int]] {
    var visited = Set<Int>()
    var finish: [Int] = []
    for start in reachable where visited.insert(start).inserted {
        var stack = [(start, 0)]
        while let (node, offset) = stack.last {
            try Task.checkCancellation()
            if offset < adjacency[node].count {
                let child = adjacency[node][offset]
                stack[stack.count - 1].1 += 1
                if visited.insert(child).inserted { stack.append((child, 0)) }
            } else { finish.append(node); stack.removeLast() }
        }
    }
    var reverse = [[Int]](repeating: [], count: adjacency.count)
    for node in reachable {
        for child in adjacency[node] { try Task.checkCancellation(); reverse[child].append(node) }
    }
    visited.removeAll(keepingCapacity: true)
    var groups: [[Int]] = []
    for start in finish.reversed() where visited.insert(start).inserted {
        var members: [Int] = []
        var stack = [start]
        while let node = stack.popLast() {
            try Task.checkCancellation()
            members.append(node)
            for parent in reverse[node] {
                try Task.checkCancellation()
                if visited.insert(parent).inserted { stack.append(parent) }
            }
        }
        if members.count > 1 || adjacency[start].contains(start) { groups.append(members.sorted()) }
    }
    try Task.checkCancellation()
    return groups.sorted { $0[0] < $1[0] }
}
