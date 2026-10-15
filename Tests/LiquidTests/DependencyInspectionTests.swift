// SPDX-License-Identifier: Apache-2.0
@testable import Liquid
import Testing

@Suite("Bounded partial-dependency inspection", .timeLimit(.minutes(1)))
struct DependencyInspectionTests {
    @Test func diamondsRepeatedRequestsAndDeterministicMapOrder() throws {
        let source = "{% render 'b' %}{% render 'a' %}{% include 'a' %}"
        let entries = [("a", "{% render 'shared' %}"), ("b", "{% include 'shared' %}"), ("shared", "{{ value | escape }}"), ("unused", "{{ invisible }}")]
        let engine = LiquidEngine()
        let expected = try engine.inspectDependencies(template: source, templates: Dictionary(uniqueKeysWithValues: entries))
        #expect(expected.nodes.map(\.id) == [.root, .partial("a"), .partial("b"), .partial("shared")])
        #expect(expected.edges.map(\.requestedName) == ["a", "b", "shared", "shared"])
        #expect(expected.nodes.last?.inspection.variableRoots == ["value"])
        #expect(expected.cycles.isEmpty && expected.missingReferences.isEmpty && expected.dynamicReferences.isEmpty)
        for offset in entries.indices {
            let shuffled = Array(entries[offset...]) + entries[..<offset]
            #expect(try engine.inspectDependencies(template: source, templates: Dictionary(uniqueKeysWithValues: shuffled.reversed())) == expected)
        }
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let partials = try Dictionary(uniqueKeysWithValues: entries).mapValues { try LiquidTemplate($0, syntaxMode: mode) }
            #expect(try engine.inspectDependencies(LiquidTemplate(source, syntaxMode: mode), templates: partials) == expected)
        }
    }

    @Test func rendererLookupPrecedenceAliasesAndRootIdentity() async throws {
        let engine = LiquidEngine()
        let partials = ["card": "exact", "card.liquid": "suffix", "only.liquid": "only", "root": "root partial", "../card": "relative literal"]
        let source = "{% include 'card' %}{% include 'card.liquid' %}{% include 'only' %}{% include 'root' %}{% include '../card' %}"
        let result = try engine.inspectDependencies(template: source, templates: partials)
        #expect(result.edges.map(\.resolvedName) == ["../card", "card", "card.liquid", "only.liquid", "root"])
        #expect(result.nodes.first?.id == .root)
        #expect(result.nodes.contains { $0.id == .partial("root") })
        #expect(try await engine.render(template: source, templates: partials) == "exactsuffixonlyroot partialrelative literal")
    }

    @Test func exactSpellingAndCanonicalDictionaryLookup() throws {
        let nfc = "caf\u{e9}", nfd = "cafe\u{301}"
        let source = "{% include '\(nfc)' %}{% include '\(nfd)' %}"
        let result = try LiquidEngine().inspectDependencies(template: source, templates: [nfc + ".liquid": ""])
        #expect(result.edges.count == 2)
        #expect(result.edges[0].requestedName.utf8.elementsEqual(nfd.utf8))
        #expect(result.edges[1].requestedName.utf8.elementsEqual(nfc.utf8))
        for edge in result.edges { #expect(edge.resolvedName!.utf8.elementsEqual((nfc + ".liquid").utf8)) }
        let other = try LiquidEngine().inspectDependencies(template: source, templates: [nfd + ".liquid": ""])
        #expect(other != result)
        #expect(Set([LiquidDependencyNodeID.partial(nfc), .partial(nfd), .root]).count == 3)
        #expect(result.edges[0] != result.edges[1])
    }

    @Test func selfLoopsAndStronglyConnectedGroups() throws {
        let result = try LiquidEngine().inspectDependencies(template: "{% render 'c' %}{% include 'a' %}{% include 'self' %}", templates: [
            "a": "{% render 'b' %}{% render 'c' %}", "b": "{% render 'a' %}",
            "c": "{% render 'd' %}", "d": "{% include 'c' %}", "self": "{% include 'self' %}",
            "unreachable": "{% include 'unreachable' %}"
        ])
        #expect(result.cycles == [[.partial("a"), .partial("b")], [.partial("c"), .partial("d")], [.partial("self")]])
        #expect(result.nodes.count == 6)
    }

    @Test func retainedSyntaxFindingsWithoutEvaluation() throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("explode") { _, _, _ in
            Issue.record("Dependency inspection invoked a callback")
            throw LiquidFilterFailure("must not execute")
        }], strictFilters: true)
        let root = "{% if false %}{% include 'missing' %}{% endif %}{% include selected %}{% raw %}{% include 'ignored' %}{% endraw %}{% comment %}{% include 'hidden' %}{% endcomment %}{% capture local %}{% for item in items %}{% render 'card' %}{% endfor %}{% endcapture %}{{ value | explode | unknown }}"
        let result = try engine.inspectDependencies(template: root, templates: ["card": "{% liquid\ninclude chosen\ninclude 'nested'\n%}"])
        #expect(result.edges.map(\.requestedName) == ["card", "missing", "nested"])
        #expect(result.missingReferences.map(\.requestedName) == ["missing", "nested"])
        #expect(result.dynamicReferences == [.root, .partial("card")])
        #expect(result.nodes[0].inspection.filterNames == ["explode", "unknown"])
        #expect(throws: LiquidError.self) { try engine.inspectDependencies(template: "{% render selected %}") }
    }

    @Test func wholeBundleAdmissionAndParsedModes() throws {
        let engine = LiquidEngine()
        #expect(throws: LiquidError.self) { try engine.inspectDependencies(template: "", templates: ["unused": "{% if %}"]) }
        let lax = try LiquidTemplate("{% if name | ignored: hidden %}{{ shown }}{% endif %}", syntaxMode: .lax)
        let strict = try LiquidTemplate("{% include 'lax' %}", syntaxMode: .strict2)
        let parsed = try engine.inspectDependencies(strict, templates: ["lax": lax])
        #expect(parsed.nodes[1].inspection.variableRoots == ["name", "shown"])
        #expect(throws: LiquidError.self) { try engine.inspectDependencies(template: strict.source, templates: ["lax": lax.source], syntaxMode: .strict2) }
        for limits in [LiquidLimits(sourceBytes: 1), LiquidLimits(nestingDepth: 2)] {
            let bounded = LiquidEngine(limits: limits)
            #expect(throws: LiquidError.self) { try bounded.inspectDependencies(try LiquidTemplate(""), templates: ["unused": lax]) }
            #expect(throws: LiquidError.self) { try bounded.inspectDependencies(template: "", templates: ["unused": lax.source]) }
        }
    }

    @Test func exactCapacityBoundariesAndInvalidProfiles() throws {
        let engine = LiquidEngine(limits: .init(sourceBytes: 2))
        #expect(try engine.inspectDependencies(template: "x", templates: ["a": "x"], analysisLimits: .init(templates: 2, nameBytes: 1, edges: 0)).nodes.count == 1)
        func expectLimit(_ expected: String, _ work: () throws -> Void) {
            do { try work(); Issue.record("Expected \(expected)") }
            catch LiquidError.limitExceeded(let actual) { #expect(actual == expected) }
            catch { Issue.record("Unexpected error: \(error)") }
        }
        expectLimit("sourceBytes") { _ = try engine.inspectDependencies(template: "x", templates: ["a": "xx"]) }
        expectLimit("dependencyTemplates") { _ = try engine.inspectDependencies(template: "", templates: ["a": ""], analysisLimits: .init(templates: 1)) }
        expectLimit("dependencyNameBytes") { _ = try engine.inspectDependencies(template: "", templates: ["é": ""], analysisLimits: .init(nameBytes: 1)) }
        let refs = "{% include 'missing' %}{% include 'missing' %}"
        #expect(try LiquidEngine().inspectDependencies(template: refs, analysisLimits: .init(edges: 1)).edges.count == 1)
        expectLimit("dependencyEdges") { _ = try LiquidEngine().inspectDependencies(template: refs, analysisLimits: .init(edges: 0)) }
        // Unreachable edges consume no retained-edge capacity, but their source and names were admitted.
        #expect(try LiquidEngine().inspectDependencies(template: "", templates: ["unused": refs], analysisLimits: .init(edges: 0)).edges.isEmpty)
        for profile in [LiquidDependencyLimits(templates: 0), .init(nameBytes: -1), .init(edges: -1)] {
            #expect(throws: LiquidError.self) { try engine.inspectDependencies(template: "", analysisLimits: profile) }
        }
        #expect(try engine.inspectDependencies(template: "", analysisLimits: .init(templates: .max, nameBytes: .max, edges: .max)).nodes.count == 1)
        #expect(throws: LiquidError.self) { try LiquidEngine(limits: .init(renderSteps: 0)).inspectDependencies(template: "") }
    }

    @Test func deepChainsWideGraphsAndIndependentRenderBudgets() throws {
        var partials: [String: String] = [:]
        for i in 0..<2_000 { partials["p\(i)"] = i == 1_999 ? "{% include 'p0' %}" : "{% include 'p\(i + 1)' %}" }
        let engine = LiquidEngine(limits: .init(outputBytes: 1, loopIterations: 1, nestingDepth: 4, renderSteps: 1, contextValues: 1))
        let chain = try engine.inspectDependencies(template: "{% include 'p0' %}", templates: partials)
        #expect(chain.nodes.count == 2_001 && chain.edges.count == 2_001)
        #expect(chain.cycles.count == 1 && chain.cycles[0].count == 2_000)
        let wide = (0..<2_000).map { "{% include 'p\($0)' %}" }.joined()
        #expect(try engine.inspectDependencies(template: wide, templates: partials, analysisLimits: .init(edges: 4_000)).edges.count == 4_000)
        #expect(throws: LiquidError.self) { try engine.inspectDependencies(template: wide, templates: partials, analysisLimits: .init(edges: 3_999)) }
    }

    @Test func cancellationInPublicAndCycleTraversals() async throws {
        let parsed = try LiquidTemplate("{% include 'a' %}")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try LiquidEngine().inspectDependencies(template: parsed.source) }
            #expect(throws: CancellationError.self) { try LiquidEngine().inspectDependencies(parsed, templates: ["a": parsed]) }
            // Exercise the separate iterative SCC phase's cancellation boundary directly.
            #expect(throws: CancellationError.self) { try dependencyCycles([[1], [0]], reachable: [0, 1]) }
        }
        await task.value
    }

    @Test(arguments: [false, true])
    func cancellationAtCoordinatedInspectionEntryLeavesReuseHealthy(parsedInput: Bool) async throws {
        let engine = LiquidEngine()
        let root = try LiquidTemplate("{% include 'a' %}")
        let partials = ["a": try LiquidTemplate("{% include 'a' %}")]
        let expected = try engine.inspectDependencies(root, templates: partials)
        let gate = TestSuspensionGate()
        let worker = Task {
            await gate.enter()
            if parsedInput { return try engine.inspectDependencies(root, templates: partials) }
            return try engine.inspectDependencies(template: root.source, templates: partials.mapValues(\.source))
        }
        defer { worker.cancel() }
        try await gate.waitForEntry()
        worker.cancel()
        _ = try await gate.release()
        await #expect(throws: CancellationError.self) { try await worker.value }
        // Synchronous traversal has no public suspension point. This proves entry
        // cancellation and independent reuse, not cancellation at a chosen SCC step.
        #expect(try engine.inspectDependencies(root, templates: partials) == expected)
    }

    @Test func concurrentRendersMetricsAndDependencyInspection() async throws {
        let engine = LiquidEngine()
        let root = try LiquidTemplate("{{ name | upcase }}{% include 'card' %}")
        let partials = ["card": try LiquidTemplate("{{ name }}")]
        let expected = try engine.inspectDependencies(root, templates: partials)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    #expect(try engine.inspectDependencies(root, templates: partials) == expected)
                    let context: LiquidObject = ["name": .string("n\(index)")]
                    let ordinary = try await engine.render(root, context: context, templates: partials)
                    let measured = try await engine.renderWithMetrics(root, context: context, templates: partials)
                    #expect(ordinary == "N\(index)n\(index)" && measured.output == ordinary)
                    #expect(measured.metrics.parseDuration == nil)
                    #expect(try engine.inspectDependencies(root, templates: partials) == expected)
                }
            }
            try await group.waitForAll()
        }
    }
}
