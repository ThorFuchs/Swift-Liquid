// SPDX-License-Identifier: Apache-2.0
import Foundation
@testable import Liquid
import Testing

private typealias GraphRegistry = LiquidTemplateRegistry
private func graphHex(_ value: String) -> String { value.utf8.map { String(format: "%02x", $0) }.joined() }
private func graphID(_ id: LiquidDependencyNodeID) -> String {
    switch id { case .root: return "root"; case .partial(let name): return "partial:" + graphHex(name) }
}
private func graphError(_ work: () throws -> Void) -> String {
    do { try work(); Issue.record("Expected terminal error"); return "NO_ERROR" }
    catch LiquidError.limitExceeded(let kind) { return kind }
    catch LiquidError.invalidValue { return "invalidValue" }
    catch LiquidError.syntax(let message, _, _) { return "syntax:" + message }
    catch GraphRegistry.AdmissionError.limitExceeded(let capacity) { return "registry:" + capacity.rawValue }
    catch is CancellationError { return "cancelled" }
    catch { Issue.record("Unexpected error: \(error)"); return "OTHER" }
}
private struct GraphOracles: Decodable {
    let oracles: [Oracle]
    struct Oracle: Decodable {
        let id: String, root: String
        let entries: [Entry], nodes: [String], edges: [Edge], cycles: [[String]]
        let dynamic: [String]?
    }
    struct Entry: Decodable { let name: String, utf8: String, raw: String }
    struct Edge: Decodable, Equatable { let origin: String, requested: String; let resolved: String? }
}

@Suite("Exact registry dependency inspection", .timeLimit(.minutes(2)))
struct ExactRegistryDependencyInspectionTests {
    @Test(arguments: [false, true])
    func suppliedByteOraclesUseStoredRanks(parsed: Bool) throws {
        let url = try #require(Bundle.module.url(forResource: "U3ExactGraphOracles", withExtension: "json", subdirectory: "Fixtures"))
        let oracles = try JSONDecoder().decode(GraphOracles.self, from: Data(contentsOf: url)).oracles
        #expect(oracles.count == 7)
        for oracle in oracles {
            let entries = try oracle.entries.enumerated().map { index, entry -> GraphRegistry.Entry in
                #expect(graphHex(entry.name) == entry.utf8)
                return .init(entry.name, index % 2 == 0 ? .raw(entry.raw) : .parsed(try LiquidTemplate(entry.raw)))
            }
            let registry = try GraphRegistry(entries)
            let engine = LiquidEngine()
            let result = try parsed
                ? engine.inspectDependencies(LiquidTemplate(oracle.root), registry: registry)
                : engine.inspectDependencies(template: oracle.root, registry: registry)
            #expect(result.nodes.map { graphID($0.id) } == oracle.nodes, "\(oracle.id)")
            #expect(result.edges.map { GraphOracles.Edge(origin: graphID($0.origin), requested: graphHex($0.requestedName), resolved: $0.resolvedName.map(graphHex)) } == oracle.edges)
            #expect(result.cycles.map { $0.map(graphID) } == oracle.cycles)
            #expect(result.dynamicReferences.map(graphID) == (oracle.dynamic ?? []))
        }
    }

    @Test func permutationsKeepCyclesAndOutgoingOrderExact() throws {
        let entries: [GraphRegistry.Entry] = [
            .init("é", .raw("{% include 'e\u{301}' %}{% include 'self' %}")),
            .init("e\u{301}", .raw("{% include 'é' %}")),
            .init("K", .raw("{% render 'K' %}")), .init("K", .raw("{% include 'K' %}")),
            .init("self", .raw("{% include 'self' %}")), .init("unused", .raw("{% include 'unused' %}"))]
        let root = "{% include 'é' %}{% render 'K' %}{% include 'é' %}"
        let engine = LiquidEngine()
        let expected = try engine.inspectDependencies(template: root, registry: GraphRegistry(entries))
        #expect(expected.nodes.map(\.id) == [.root, .partial("K"), .partial("e\u{301}"), .partial("self"), .partial("é"), .partial("K")])
        #expect(expected.cycles == [[.partial("K"), .partial("K")], [.partial("e\u{301}"), .partial("é")], [.partial("self")]])
        #expect(expected.edges.filter { $0.origin == .root }.map(\.requestedName) == ["K", "é"])
        for offset in entries.indices {
            let shifted = Array(entries[offset...]) + entries[..<offset]
            for values in [shifted, Array(shifted.reversed())] {
                #expect(try engine.inspectDependencies(template: root, registry: GraphRegistry(values)) == expected)
            }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func firstLiteralParityAcrossEightRuntimeFamilies(mode: LiquidSyntaxMode) async throws {
        let registry = try GraphRegistry([.init("é", .raw("A{% include 'e\u{301}' %}")),
            .init("e\u{301}", .parsed(LiquidTemplate("B{% render 'K' %}", syntaxMode: mode))),
            .init("K", .raw("C{% include 'K' %}")), .init("K", .raw("D"))])
        let engine = LiquidEngine(), root = "{% include 'é' %}"
        let graph = try engine.inspectDependencies(template: root, registry: registry, syntaxMode: mode)
        #expect(try engine.inspectDependencies(LiquidTemplate(root, syntaxMode: mode), registry: registry, syntaxMode: mode) == graph)
        #expect(graph.edges.count == 4 && graph.missingReferences.isEmpty)
        for edge in graph.edges {
            let selected = try #require(try registry.resolve(edge.requestedName))
            #expect(graphHex(selected.name) == edge.resolvedName.map(graphHex))
            #expect(graph.nodes.contains { $0.id == .partial(registry.entries[selected.entryIndex].name) })
        }
        let parsed = try LiquidTemplate(root, syntaxMode: mode)
        let outputs = try await [
            engine.render(template: root, registry: registry, syntaxMode: mode),
            engine.render(parsed, registry: registry, syntaxMode: mode),
            engine.renderWithDiagnostics(template: root, registry: registry, syntaxMode: mode).output,
            engine.renderWithDiagnostics(parsed, registry: registry, syntaxMode: mode).output,
            engine.renderWithMetrics(template: root, registry: registry, syntaxMode: mode).output,
            engine.renderWithMetrics(parsed, registry: registry, syntaxMode: mode).output,
            engine.renderWithDiagnosticsAndMetrics(template: root, registry: registry, syntaxMode: mode).output,
            engine.renderWithDiagnosticsAndMetrics(parsed, registry: registry, syntaxMode: mode).output]
        #expect(outputs.count == 8 && outputs.allSatisfy { graphHex($0) == "41424344" })
    }

    @Test(arguments: [0, 1, 2, 3])
    func canonicalMissStaysMissingWhileLegacyAndContextRetryRemain(pair: Int) async throws {
        let (stored, requested) = [("é", "e\u{301}"), ("e\u{301}", "é"), ("K", "K"), ("K", "K")][pair]
        let registry = try GraphRegistry([.init(stored + ".liquid", .raw("ALIAS")), .init("target", .raw("FALLBACK"))])
        let root = "{% include '\(requested)' %}"
        let engine = LiquidEngine(), exact = try engine.inspectDependencies(template: root, registry: registry)
        #expect(exact.nodes.map(\.id) == [.root] && exact.missingReferences.count == 1)
        #expect(graphHex(exact.edges[0].requestedName) == graphHex(requested))
        let legacy = try engine.inspectDependencies(template: root, templates: [stored + ".liquid": "ALIAS"])
        #expect(legacy.edges[0].resolvedName.map(graphHex) == graphHex(stored + ".liquid"))
        #expect(try await engine.render(template: root, templates: [stored + ".liquid": "ALIAS"]) == "ALIAS")
        #expect(try await engine.render(template: root, context: [requested: "target"], registry: registry) == "FALLBACK")
        #expect(exact.missingReferences.count == 1) // Static analysis never predicts the context retry.
    }

    @Test func suffixOpaqueNamesAndSeparateRootIdentity() throws {
        let names = ["x", "x.liquid", "double.liquid.liquid", "", "../opaque", "a/b", "%2e%2e", "a\0b"]
        let registry = try GraphRegistry(names.map { .init($0, .raw("SAME")) })
        let requests = ["x", "x.liquid", "double.liquid", "", "../opaque", "a/b", "%2e%2e", "a\0b"]
        let root = requests.map { "{% include '\($0)' %}" }.joined()
        let graph = try LiquidEngine().inspectDependencies(template: root, registry: registry)
        #expect(graph.nodes.count == 9 && graph.nodes[0].id == .root)
        #expect(graph.nodes[1].id == .partial(""))
        for edge in graph.edges {
            #expect(edge.resolvedName.map(graphHex) == graphHex(edge.requestedName == "double.liquid" ? "double.liquid.liquid" : edge.requestedName))
        }
        let same = try GraphRegistry([.init("root", .raw("SAME"))])
        let source = "SAME{% include 'root' %}"
        #expect(try LiquidEngine().inspectDependencies(template: source, registry: same).nodes.map(\.id) == [.root, .partial("root")])
        let sameSource = try GraphRegistry([.init("", .raw(""))])
        #expect(try LiquidEngine().inspectDependencies(template: "{% include '' %}", registry: sameSource).nodes.map(\.id) == [.root, .partial("")])
        let recursiveRoot = "{% include 'root' %}"
        let registeredRoot = try GraphRegistry([.init("root", .raw(recursiveRoot))])
        let capacity = recursiveRoot.utf8.count * 2
        let sameGraph = try LiquidEngine(limits: .init(sourceBytes: capacity)).inspectDependencies(template: recursiveRoot, registry: registeredRoot)
        #expect(sameGraph.nodes.map(\.id) == [.root, .partial("root")])
        #expect(sameGraph.cycles == [[.partial("root")]])
        #expect(graphError { _ = try LiquidEngine(limits: .init(sourceBytes: capacity - 1)).inspectDependencies(template: recursiveRoot, registry: registeredRoot) } == "sourceBytes")
    }

    @Test func syntacticFindingsNeverEvaluateConditionsOrHostFilters() throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("graph_bomb") { _, _, _ in
            Issue.record("Graph evaluated a host callback"); throw LiquidFilterFailure("must not execute")
        }], strictFilters: true)
        let root = "{% if false %}{% include 'missing' %}{% endif %}{% include selected %}{% render 'p' %}{{ value | graph_bomb | unknown }}{% raw %}{% include 'hidden' %}{% endraw %}{% comment %}{% render 'hidden2' %}{% endcomment %}"
        let registry = try GraphRegistry([.init("p", .raw("{% liquid\ninclude other\ninclude 'nested'\n%}")),
            .init("unused", .raw("{% include unused_target %}"))])
        let graph = try engine.inspectDependencies(template: root, registry: registry)
        #expect(graph.edges.map(\.requestedName) == ["missing", "p", "nested"])
        #expect(graph.missingReferences.map(\.requestedName) == ["missing", "nested"])
        #expect(graph.dynamicReferences == [.root, .partial("p")])
        #expect(graph.nodes[0].inspection.filterNames == ["graph_bomb", "unknown"])
        #expect(graphError { _ = try engine.inspectDependencies(template: "{% render selected %}", registry: registry) }.hasPrefix("syntax:"))
    }

    @Test func parsedModesRetainedAndRawEntryModeExplicit() throws {
        let laxSource = "{% if name | ignored: hidden %}{{ shown }}{% endif %}"
        let lax = try LiquidTemplate(laxSource, syntaxMode: .lax)
        let parsed = try GraphRegistry([.init("lax", .parsed(lax))])
        let engine = LiquidEngine(), strictRoot = try LiquidTemplate("{% include 'lax' %}", syntaxMode: .strict2)
        let result = try engine.inspectDependencies(strictRoot, registry: parsed, syntaxMode: .strict2)
        #expect(result.nodes[1].inspection.variableRoots == ["name", "shown"])
        #expect(try engine.inspectDependencies(lax, registry: GraphRegistry([]), syntaxMode: .strict2).nodes[0].inspection.variableRoots == ["name", "shown"])
        let raw = try GraphRegistry([.init("lax", .raw(laxSource))])
        #expect(try engine.inspectDependencies(strictRoot, registry: raw, syntaxMode: .lax) == result)
        #expect(graphError { _ = try engine.inspectDependencies(strictRoot, registry: raw, syntaxMode: .strict2) }.hasPrefix("syntax:"))
        #expect(graphError { _ = try engine.inspectDependencies(template: laxSource, registry: parsed, syntaxMode: .strict2) }.hasPrefix("syntax:"))
    }

    @Test func unusedSourcesAreFatalBeforeFindings() throws {
        let engine = LiquidEngine()
        let invalid = try GraphRegistry([.init("unused", .raw("{% if %}"))])
        #expect(graphError { _ = try engine.inspectDependencies(template: "", registry: invalid) }.hasPrefix("syntax:"))
        #expect(graphError { _ = try engine.inspectDependencies(LiquidTemplate(""), registry: invalid) }.hasPrefix("syntax:"))
        let deep = try LiquidTemplate("{% if true %}{% if true %}X{% endif %}{% endif %}")
        let registry = try GraphRegistry([.init("unused", .parsed(deep))])
        #expect(graphError { _ = try LiquidEngine(limits: .init(nestingDepth: 2)).inspectDependencies(template: "", registry: registry) } == "nestingDepth")
    }

    @Test(arguments: [false, true])
    func cumulativeNameAndSourceBoundariesIncludeUnused(parsed: Bool) throws {
        let entries: [GraphRegistry.Entry] = [.init("é", .raw("😀")), .init("e\u{301}", .parsed(try LiquidTemplate("YZ")))]
        let registry = try GraphRegistry(entries), root = try LiquidTemplate("x")
        func call(_ sourceLimit: Int, _ nameLimit: Int) throws -> LiquidDependencyInspection {
            let engine = LiquidEngine(limits: .init(sourceBytes: sourceLimit))
            let limits = LiquidDependencyLimits(templates: 3, nameBytes: nameLimit, edges: 0)
            return try parsed ? engine.inspectDependencies(root, registry: registry, analysisLimits: limits)
                : engine.inspectDependencies(template: root.source, registry: registry, analysisLimits: limits)
        }
        #expect(try call(7, 5).nodes.map(\.id) == [.root])
        #expect(graphError { _ = try call(6, 5) } == "sourceBytes")
        #expect(graphError { _ = try call(7, 4) } == "dependencyNameBytes")
        let empty = try GraphRegistry([.init("", .raw(""))])
        #expect(try LiquidEngine().inspectDependencies(template: "", registry: empty, analysisLimits: .init(nameBytes: 0, edges: 0)).nodes.count == 1)
        let duplicate = try GraphRegistry([.init("root", .raw("x"))])
        #expect(graphError { _ = try LiquidEngine(limits: .init(sourceBytes: 1)).inspectDependencies(template: "x", registry: duplicate) } == "sourceBytes")
        #expect(try LiquidEngine(limits: .init(sourceBytes: 2)).inspectDependencies(template: "x", registry: duplicate).nodes.count == 1)
    }

    @Test func countInvalidProfilesAndMaxIntRemainSubtractive() throws {
        let empty = try GraphRegistry([]), one = try GraphRegistry([.init("p", .raw(""))]), engine = LiquidEngine()
        #expect(try engine.inspectDependencies(template: "", registry: empty, analysisLimits: .init(templates: 1, nameBytes: 0, edges: 0)).nodes.count == 1)
        #expect(graphError { _ = try engine.inspectDependencies(template: "", registry: one, analysisLimits: .init(templates: 1)) } == "dependencyTemplates")
        for profile in [LiquidDependencyLimits(templates: 0), .init(templates: -1), .init(nameBytes: -1), .init(edges: -1)] {
            #expect(graphError { _ = try engine.inspectDependencies(template: "", registry: empty, analysisLimits: profile) } == "invalidValue")
        }
        #expect(try engine.inspectDependencies(template: "", registry: one, analysisLimits: .init(templates: .max, nameBytes: .max, edges: .max)).nodes.count == 1)
        #expect(graphError { _ = try LiquidEngine(limits: .init(renderSteps: 0)).inspectDependencies(template: "", registry: empty) } == "invalidValue")
    }

    @Test func admissionAndParsePrecedenceIsExplicit() throws {
        let bad = try GraphRegistry([.init("unused", .raw("{% first_problem %}"))])
        #expect(graphError { _ = try LiquidEngine(limits: .init(sourceBytes: 1)).inspectDependencies(template: "xx", registry: bad, analysisLimits: .init(nameBytes: 0)) } == "sourceBytes")
        #expect(graphError { _ = try LiquidEngine(limits: .init(sourceBytes: 1)).inspectDependencies(template: "", registry: bad, analysisLimits: .init(nameBytes: 0)) } == "dependencyNameBytes")
        #expect(graphError { _ = try LiquidEngine().inspectDependencies(template: "{% root_problem %}", registry: bad) }.contains("root_problem"))
        let entries: [GraphRegistry.Entry] = [.init("z", .raw("{% first_problem %}")), .init("a", .raw("{% second_problem %}"))]
        #expect(graphError { _ = try LiquidEngine().inspectDependencies(template: "", registry: GraphRegistry(entries)) }.contains("first_problem"))
        #expect(graphError { _ = try LiquidEngine().inspectDependencies(template: "", registry: GraphRegistry(Array(entries.reversed()))) }.contains("second_problem"))
        let deep = try LiquidTemplate("{% if true %}{% if true %}X{% endif %}{% endif %}")
        let mixed = try GraphRegistry([.init("deep", .parsed(deep)), .init("bad", .raw("{% raw_problem %}"))])
        #expect(graphError { _ = try LiquidEngine(limits: .init(nestingDepth: 2)).inspectDependencies(LiquidTemplate(""), registry: mixed) }.contains("raw_problem"))
    }

    @Test func lookupCapacityIsTerminalAndEdgeCapacityPrecedesLookup() throws {
        let registry = try GraphRegistry([], limits: .init(nameUTF8Bytes: 1))
        let source = "{% include 'é' %}", engine = LiquidEngine()
        #expect(graphError { _ = try engine.inspectDependencies(template: source, registry: registry) } == "registry:nameUTF8Bytes")
        #expect(graphError { _ = try engine.inspectDependencies(template: source, registry: registry, analysisLimits: .init(edges: 0)) } == "dependencyEdges")
        #expect(try engine.inspectDependencies(template: "{% if false %}{% include 'x' %}{% endif %}", registry: registry).missingReferences.count == 1)
    }

    @Test func reachableUniqueMissingEdgesChargeExactly() throws {
        let registry = try GraphRegistry([.init("unused", .raw("{% include 'long-ignored' %}"))], limits: .init(nameUTF8Bytes: 6))
        let engine = LiquidEngine()
        #expect(try engine.inspectDependencies(template: "", registry: registry, analysisLimits: .init(edges: 0)).edges.isEmpty)
        let source = "{% include 'x' %}{% render 'x' %}{% include 'y' %}"
        #expect(try engine.inspectDependencies(template: source, registry: registry, analysisLimits: .init(edges: 2)).missingReferences.map(\.requestedName) == ["x", "y"])
        #expect(graphError { _ = try engine.inspectDependencies(template: source, registry: registry, analysisLimits: .init(edges: 1)) } == "dependencyEdges")
        #expect(graphError { _ = try engine.inspectDependencies(template: "{% include 'x' %}", registry: registry, analysisLimits: .init(edges: 0)) } == "dependencyEdges")
    }

    @Test func sharedPreparationPreservesU2TimingSourcesAndErrors() async throws {
        let engine = LiquidEngine(), root = try LiquidTemplate("x")
        let parsed = try GraphRegistry([.init("p", .parsed(LiquidTemplate("y")))])
        let mixed = try GraphRegistry([.init("p", .raw("y"))])
        for (registry, hasParse) in [(parsed, false), (mixed, true)] {
            let prepared = try engine.prepareExact(.parsed(root), registry: registry, syntaxMode: .strict2, measuring: true)
            #expect(prepared.sourceBytes == 2 && prepared.templates.asts.count == 1)
            #expect((prepared.parseDuration != nil) == hasParse)
            let metrics = try await engine.renderWithMetrics(root, registry: registry, syntaxMode: .strict2).metrics
            #expect(metrics.sourceBytes == 2 && (metrics.parseDuration != nil) == hasParse)
            #expect(try engine.inspectDependencies(root, registry: registry).nodes.count == 1)
        }
        let invalid = try GraphRegistry([.init("unused", .raw("{% bad %}"))])
        do { _ = try await LiquidEngine(limits: .init(sourceBytes: 1)).render(template: "xx", registry: invalid); Issue.record("Expected U2 quota") }
        catch LiquidError.limitExceeded(let kind) { #expect(kind == "sourceBytes") }
    }

    @Test func cancellationAtEntryPrecedesInvalidLimitsAndKeepsSiblingHealthy() async throws {
        let registry = try GraphRegistry([.init("p", .raw("P"))]), engine = LiquidEngine()
        let parsed = try LiquidTemplate("{% include 'p' %}")
        let worker = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(graphError { _ = try engine.inspectDependencies(template: parsed.source, registry: registry, analysisLimits: .init(templates: 0)) } == "cancelled")
            #expect(graphError { _ = try engine.inspectDependencies(parsed, registry: registry) } == "cancelled")
        }
        await worker.value
        #expect(try engine.inspectDependencies(parsed, registry: registry).nodes.count == 2)
        #expect(try await engine.render(parsed, registry: registry) == "P")
    }

    @Test(arguments: [ExactDependencyPhase.ordering, .inspection, .resolution, .traversal, .cycles, .publication])
    func cancellationInsideGraphPhasesPublishesNothing(phase: ExactDependencyPhase) async throws {
        let registry = try GraphRegistry([.init("a", .raw("{% include 'b' %}")), .init("b", .raw("{% include 'a' %}"))])
        let engine = LiquidEngine()
        let prepared = try engine.prepareExact(.raw("{% include 'a' %}"), registry: registry, syntaxMode: .lax, measuring: false, analysisLimits: .default)
        let worker = Task {
            var visits = 0
            #expect(graphError {
                _ = try inspectExactDependencies(prepared, limits: .default, analysisLimits: .default) { observed in
                    if observed == phase {
                        visits += 1
                        if visits == (phase == .cycles ? 4 : 1) { withUnsafeCurrentTask { $0?.cancel() } }
                    }
                    try Task.checkCancellation()
                }
            } == "cancelled")
            #expect(visits == (phase == .cycles ? 4 : 1))
        }
        await worker.value
        #expect(try engine.inspectDependencies(template: "{% include 'a' %}", registry: registry).cycles == [[.partial("a"), .partial("b")]])
    }

    @Test func deepAndWideGraphsUseIterativeSCCAndIndependentRuntimeBudgets() throws {
        let count = 2_001
        let entries = (0..<count).map { GraphRegistry.Entry("p\($0)", .raw("{% include 'p\(($0 + 1) % count)' %}")) }
        let registry = try GraphRegistry(entries)
        let engine = LiquidEngine(limits: .init(outputBytes: 1, loopIterations: 1, nestingDepth: 4, renderSteps: 1, contextValues: 1))
        let chain = try engine.inspectDependencies(template: "{% include 'p0' %}", registry: registry)
        #expect(chain.nodes.count == count + 1 && chain.edges.count == count + 1)
        #expect(chain.cycles.count == 1 && chain.cycles[0].count == count)
        let wide = (0..<count).map { "{% include 'p\($0)' %}" }.joined()
        let graph = try engine.inspectDependencies(template: wide, registry: registry, analysisLimits: .init(edges: count * 2))
        #expect(graph.nodes.map(\.id) == chain.nodes.map(\.id) && graph.edges.count == count * 2)
        #expect(graphError { _ = try engine.inspectDependencies(template: wide, registry: registry, analysisLimits: .init(edges: count * 2 - 1)) } == "dependencyEdges")
        #expect(try engine.inspectDependencies(template: "{% include 'p0' %}", registry: GraphRegistry(Array(entries.reversed()))) == chain)
    }

    @Test func concurrentRendersAndExactGraphInspectionStayInvocationOwned() async throws {
        let registry = try GraphRegistry([.init("é", .raw("A{{ marker }}{% include 'e\u{301}' %}")), .init("e\u{301}", .parsed(LiquidTemplate("B{{ marker }}")))])
        let engine = LiquidEngine(), root = try LiquidTemplate("{% include 'é' %}")
        let expected = try engine.inspectDependencies(root, registry: registry)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let marker = "u3-\(index)"
                    #expect(try engine.inspectDependencies(template: root.source, registry: registry) == expected)
                    let output = try await engine.renderWithMetrics(root, context: ["marker": .string(marker)], registry: registry)
                    #expect(output.output == "A\(marker)B\(marker)" && output.metrics.parseDuration != nil)
                    #expect(try engine.inspectDependencies(root, registry: registry) == expected)
                }
            }
            try await group.waitForAll()
        }
        #expect(registry.entries.map { graphHex($0.name) } == ["c3a9", "65cc81"])
    }
}
