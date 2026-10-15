// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

/// Small deterministic inputs keep every seed reproducible under parallel Swift Testing.
private struct SeededValues {
    var state: UInt64
    mutating func next(_ upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 32) % UInt64(upperBound))
    }
}

@Suite("Public contract properties", .timeLimit(.minutes(1)))
struct QualityPropertyTests {
    @Test(arguments: [UInt64(0), 1, 0x5eed, .max])
    func renderingEntryPointsAgree(seed: UInt64) async throws {
        var values = SeededValues(state: seed)
        let texts = ["", "<Swift & Liquid>", "é", "e\u{301}", "👩‍💻", "\0", "001", "a\nb"]
        let sources = ["{{ text | escape }}", "{% for item in items %}{{ item }};{% endfor %}",
                       "{% include 'card' %}|{% render 'card', text: text %}",
                       "{% capture label %}{{ text | host_echo }}{% endcapture %}{{ label }}",
                       "{% if flag %}{{ text }}{% else %}{{ items | join: ',' }}{% endif %}"]
        let engine = try LiquidEngine(filters: [LiquidFilter("host_echo") { value, _, _ in value }])
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for _ in 0..<16 {
                let text = texts[values.next(texts.count)]
                let context: LiquidObject = ["text": .string(text), "flag": .bool(values.next(2) == 0),
                                             "items": .array((0..<values.next(5)).map { .integer($0) })]
                let source = sources[values.next(sources.count)]
                let partials = ["card": "[{{ text | escape }}]"]
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                let parsedPartials = try partials.mapValues { try LiquidTemplate($0, syntaxMode: mode) }
                let expected = try await engine.render(template: source, context: context, templates: partials, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: context, templates: parsedPartials).utf8.elementsEqual(expected.utf8))
                let measured = try await engine.renderWithMetrics(parsed, context: context, templates: parsedPartials)
                let recovered = try await engine.renderWithDiagnosticsAndMetrics(template: source, context: context, templates: partials, syntaxMode: mode)
                #expect(measured.output.utf8.elementsEqual(expected.utf8))
                #expect(recovered.output.utf8.elementsEqual(expected.utf8) && recovered.diagnostics.isEmpty)
                #expect(measured.metrics.parseDuration == nil && recovered.metrics.parseDuration != nil)
                #expect(measured.metrics.outputBytes == expected.utf8.count)
            }
        }
    }

    @Test(arguments: [UInt64(0), 1, 0x5eed, .max])
    func dependencyCyclesAgreeWithReachabilityOracle(seed: UInt64) throws {
        var random = SeededValues(state: seed)
        let count = 16
        var adjacency = [[Bool]](repeating: [Bool](repeating: false, count: count), count: count)
        for origin in 0..<count {
            for target in 0..<count { adjacency[origin][target] = random.next(5) == 0 }
        }
        func name(_ index: Int) -> String { "p\(index)" }
        func stored(_ index: Int) -> String { name(index) + (index.isMultiple(of: 2) ? "" : ".liquid") }
        let entries = (0..<count).map { origin in
            (stored(origin), (0..<count).filter { adjacency[origin][$0] }.map { "{% include '\(name($0))' %}" }.joined())
        }
        let source = (0..<count).map { "{% include '\(name($0))' %}" }.joined()
            + "{% include 'missing' %}{% include 'missing' %}{% include selected %}"
        let engine = LiquidEngine()
        let report = try engine.inspectDependencies(template: source, templates: Dictionary(uniqueKeysWithValues: entries))
        let reordered = try engine.inspectDependencies(template: source, templates: Dictionary(uniqueKeysWithValues: entries.reversed()))
        let parsed = try Dictionary(uniqueKeysWithValues: entries).mapValues { try LiquidTemplate($0) }
        #expect(try engine.inspectDependencies(LiquidTemplate(source), templates: parsed) == report)
        #expect(reordered == report)
        #expect(report.nodes.count == count + 1)
        #expect(report.edges.count == count + 1 + adjacency.flatMap { $0 }.filter { $0 }.count)
        #expect(report.missingReferences.map(\.requestedName) == ["missing"])
        #expect(report.dynamicReferences == [.root])

        // Floyd–Warshall reachability is independent of the production iterative SCC algorithm.
        var reachable = adjacency
        for via in 0..<count {
            for origin in 0..<count {
                for target in 0..<count {
                    reachable[origin][target] = reachable[origin][target] || (reachable[origin][via] && reachable[via][target])
                }
            }
        }
        var remaining = Set(0..<count)
        var expected: [[LiquidDependencyNodeID]] = []
        for origin in 0..<count where remaining.contains(origin) {
            let members = (0..<count).filter { reachable[origin][$0] && reachable[$0][origin] }
            if !members.isEmpty {
                expected.append(members.map { .partial(stored($0)) }.sorted { key($0).utf8.lexicographicallyPrecedes(key($1).utf8) })
                remaining.subtract(members)
            }
        }
        expected.sort { key($0[0]).utf8.lexicographicallyPrecedes(key($1[0]).utf8) }
        #expect(report.cycles == expected)
    }

    @Test func suspensionBarriersDoNotStrandCancelledObserversOrHosts() async throws {
        let absent = TestSuspensionGate()
        let observer = Task { try await absent.waitForEntry() }
        defer { observer.cancel() }
        observer.cancel()
        await #expect(throws: CancellationError.self) { try await observer.value }

        let gate = TestSuspensionGate()
        let host = Task { await gate.enter() }
        defer { host.cancel() }
        try await gate.waitForEntry()
        host.cancel() // The callback's suspension must end even when no release is sent.
        await host.value
        #expect(try await gate.release() >= .zero)
    }
}

private func key(_ identity: LiquidDependencyNodeID) -> String {
    switch identity { case .root: ""; case .partial(let name): name }
}
