// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

private struct AuditObservation: Sendable {
    let output: String
    let diagnostics: [LiquidDiagnostic]
    let metrics: LiquidRenderMetrics?
    init(_ output: String) { self.output = output; diagnostics = []; metrics = nil }
    init(_ result: LiquidRenderResult) { output = result.output; diagnostics = result.diagnostics; metrics = nil }
    init(_ result: LiquidMeasuredRenderResult) { output = result.output; diagnostics = result.diagnostics; metrics = result.metrics }
}
private func auditRender(_ source: String, parsed: Bool, family: Int, exact: Bool,
    entries: [(String, String)], engine: LiquidEngine, context: LiquidObject = [:],
    mode: LiquidSyntaxMode = .lax) async throws -> AuditObservation {
    let root = try LiquidTemplate(source, syntaxMode: mode)
    let registry = try LiquidTemplateRegistry(entries.enumerated().map { offset, entry in
        .init(entry.0, offset % 2 == 0 ? .raw(entry.1) : .parsed(try LiquidTemplate(entry.1, syntaxMode: mode)))
    })
    var raw: [String: String] = [:]
    for (name, value) in entries { raw[name] = value }
    let templates = try raw.mapValues { try LiquidTemplate($0, syntaxMode: mode) }
    switch (exact, parsed, family) {
    case (true, false, 0): return .init(try await engine.render(template: source, context: context, registry: registry, syntaxMode: mode))
    case (true, true, 0): return .init(try await engine.render(root, context: context, registry: registry, syntaxMode: mode))
    case (true, false, 1): return .init(try await engine.renderWithDiagnostics(template: source, context: context, registry: registry, syntaxMode: mode))
    case (true, true, 1): return .init(try await engine.renderWithDiagnostics(root, context: context, registry: registry, syntaxMode: mode))
    case (true, false, 2): return .init(try await engine.renderWithMetrics(template: source, context: context, registry: registry, syntaxMode: mode))
    case (true, true, 2): return .init(try await engine.renderWithMetrics(root, context: context, registry: registry, syntaxMode: mode))
    case (true, false, 3): return .init(try await engine.renderWithDiagnosticsAndMetrics(template: source, context: context, registry: registry, syntaxMode: mode))
    case (true, true, 3): return .init(try await engine.renderWithDiagnosticsAndMetrics(root, context: context, registry: registry, syntaxMode: mode))
    case (false, false, 0): return .init(try await engine.render(template: source, context: context, templates: raw, syntaxMode: mode))
    case (false, true, 0): return .init(try await engine.render(root, context: context, templates: templates))
    case (false, false, 1): return .init(try await engine.renderWithDiagnostics(template: source, context: context, templates: raw, syntaxMode: mode))
    case (false, true, 1): return .init(try await engine.renderWithDiagnostics(root, context: context, templates: templates))
    case (false, false, 2): return .init(try await engine.renderWithMetrics(template: source, context: context, templates: raw, syntaxMode: mode))
    case (false, true, 2): return .init(try await engine.renderWithMetrics(root, context: context, templates: templates))
    case (false, false, 3): return .init(try await engine.renderWithDiagnosticsAndMetrics(template: source, context: context, templates: raw, syntaxMode: mode))
    case (false, true, 3): return .init(try await engine.renderWithDiagnosticsAndMetrics(root, context: context, templates: templates))
    default: preconditionFailure("Unknown family")
    }
}
private func auditCounters(_ metrics: LiquidRenderMetrics) -> [Int] {
    [metrics.sourceBytes, metrics.outputBytes, metrics.renderSteps, metrics.loopIterations, metrics.admittedValues]
}
private actor AuditVisits {
    var count = 0
    func visit() { count += 1 }
}
private enum AuditHostError: Error { case original }

@Suite("U4 exact and legacy conformance audit", .timeLimit(.minutes(2)))
struct RegistryConformanceAuditTests {
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func ordinaryNamesAllTenAPIsPreserveScopeClockAndLogicalCounters(mode: LiquidSyntaxMode) async throws {
        let visits = AuditVisits()
        let engine = try LiquidEngine(filters: [LiquidFilter("audit_visit") { value, _, _ in await visits.visit(); return value }],
            referenceTime: .init(timeIntervalSince1970: 1_704_067_200))
        let entries = [("shared", "{% assign touched='S' %}{{ name }}{% include 'leaf' %}"),
            ("leaf", "L"), ("island", "{{ name }}{% assign touched='I' %}")]
        let source = "{{ name | audit_visit | escape }}|{% include 'shared' %}|{{ touched }}|{% render 'island', name: name %}|{{ touched }}|{% for x in items %}{{ x }}{% endfor %}|{{ 'now' | date: '%s' }}"
        let context: LiquidObject = ["name": "<N>", "items": [1, 2]]
        let registry = try LiquidTemplateRegistry(entries.map { .init($0.0, .raw($0.1)) })
        let rawGraph = try engine.inspectDependencies(template: source, registry: registry, syntaxMode: mode)
        #expect(try engine.inspectDependencies(LiquidTemplate(source, syntaxMode: mode), registry: registry, syntaxMode: mode) == rawGraph)
        #expect(try engine.inspectDependencies(template: source, templates: Dictionary(uniqueKeysWithValues: entries), syntaxMode: mode) == rawGraph)
        #expect(await visits.count == 0)
        for parsed in [false, true] {
            for family in 0..<4 {
                let exact = try await auditRender(source, parsed: parsed, family: family, exact: true, entries: entries, engine: engine, context: context, mode: mode)
                let legacy = try await auditRender(source, parsed: parsed, family: family, exact: false, entries: entries, engine: engine, context: context, mode: mode)
                #expect(exact.output == "&lt;N&gt;|<N>L|S|<N>|S|12|1704067200")
                #expect(exact.output == legacy.output && exact.diagnostics == legacy.diagnostics)
                if let measured = exact.metrics, let baseline = legacy.metrics {
                    #expect(auditCounters(measured) == auditCounters(baseline))
                    #expect(measured.parseDuration != nil) // Mixed registry always contains raw content.
                    #expect((baseline.parseDuration != nil) == !parsed)
                }
            }
        }
        #expect(await visits.count == 16)
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func canonicalDifferenceAndSuffixIdentityAreIntentional(mode: LiquidSyntaxMode) async throws {
        let entries = [("é", "A"), ("e\u{301}", "B"), ("K", "C"), ("K", "D"), ("only.liquid", "E"), ("double.liquid.liquid", "F")]
        let requests = ["é", "e\u{301}", "K", "K", "only", "double.liquid"]
        let source = requests.map { "{% include '\($0)' %}" }.joined(separator: "|")
        let registry = try LiquidTemplateRegistry(entries.map { .init($0.0, .raw($0.1)) }), engine = LiquidEngine()
        let graph = try engine.inspectDependencies(template: source, registry: registry, syntaxMode: mode)
        #expect(graph.nodes.count == 7 && graph.edges.count == 6)
        for edge in graph.edges {
            let match = try #require(try registry.resolve(edge.requestedName))
            #expect(edge.resolvedName?.utf8.elementsEqual(match.name.utf8) == true)
            #expect(entries[match.entryIndex].0.utf8.elementsEqual(match.name.utf8))
        }
        for parsed in [false, true] { for family in 0..<4 {
            #expect(try await auditRender(source, parsed: parsed, family: family, exact: true, entries: entries, engine: engine, mode: mode).output == "A|B|C|D|E|F")
            #expect(try await auditRender(source, parsed: parsed, family: family, exact: false, entries: entries, engine: engine, mode: mode).output == "B|B|D|D|E|F")
        } }
    }

    @Test func recoveredAndRaisingPoliciesMatchForOrdinaryNames() async throws {
        let engine = LiquidEngine(strictFilters: true)
        let source = "before{{ value | absent_filter }}after{% include 'p' %}"
        for parsed in [false, true] { for family in 0..<4 {
            if family == 1 || family == 3 {
                let a = try await auditRender(source, parsed: parsed, family: family, exact: true, entries: [("p", "P")], engine: engine, context: ["value": "V"])
                let b = try await auditRender(source, parsed: parsed, family: family, exact: false, entries: [("p", "P")], engine: engine, context: ["value": "V"])
                #expect(a.output == b.output && a.diagnostics == b.diagnostics && a.diagnostics.count == 1)
                if let ma = a.metrics, let mb = b.metrics { #expect(auditCounters(ma) == auditCounters(mb)) }
            } else {
                for exact in [false, true] {
                    await #expect(throws: LiquidError.self) { try await auditRender(source, parsed: parsed, family: family, exact: exact, entries: [("p", "P")], engine: engine, context: ["value": "V"]) }
                }
            }
        } }
        #expect(try engine.inspectDependencies(template: source, registry: LiquidTemplateRegistry([.init("p", .raw("P"))])).nodes[0].inspection.filterNames == ["absent_filter"])
    }

    @Test func dynamicMissingAndCyclicStaticFindingsDoNotPredictExecution() async throws {
        let registry = try LiquidTemplateRegistry([.init("p", .raw("P")), .init("cycle", .raw("{% include 'cycle' %}"))])
        let source = "{% if false %}{% include 'cycle' %}{% endif %}{% include 'alias' %}{% include selected %}"
        let engine = LiquidEngine(), graph = try engine.inspectDependencies(template: source, registry: registry)
        #expect(graph.missingReferences.map(\.requestedName) == ["alias"])
        #expect(graph.dynamicReferences == [.root] && graph.cycles == [[.partial("cycle")]])
        #expect(try await engine.render(template: source, context: ["alias": "p", "selected": "p"], registry: registry) == "PP")
        #expect(try engine.inspectDependencies(LiquidTemplate(source), registry: registry) == graph)
    }

    @Test func parsedModeAndDeclarationOrderRemainIndependentOfGraphRank() async throws {
        let lax = try LiquidTemplate("{% if flag | ignored: hidden %}X{% endif %}", syntaxMode: .lax)
        let entries: [LiquidTemplateRegistry.Entry] = [.init("z", .parsed(lax)), .init("a", .raw("A"))]
        let source = "{% include 'z' %}{% include 'a' %}", engine = LiquidEngine()
        let registry = try LiquidTemplateRegistry(entries)
        #expect(try await engine.render(LiquidTemplate(source, syntaxMode: .strict2), context: ["flag": true], registry: registry, syntaxMode: .strict2) == "XA")
        let graph = try engine.inspectDependencies(template: source, registry: registry, syntaxMode: .strict2)
        #expect(graph.nodes.map(\.id) == [.root, .partial("a"), .partial("z")])
        #expect(try engine.inspectDependencies(template: source, registry: LiquidTemplateRegistry(Array(entries.reversed())), syntaxMode: .strict2) == graph)
        let raw = try LiquidTemplateRegistry([.init("unused", .raw(lax.source))])
        #expect(throws: LiquidError.self) { try engine.inspectDependencies(LiquidTemplate(""), registry: raw, syntaxMode: .strict2) }
        #expect(try engine.inspectDependencies(LiquidTemplate(""), registry: raw, syntaxMode: .lax).nodes.count == 1)
    }

    @Test func atomicCapacityAndHostErrorsNeverBecomeFallbackSuccess() async throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("audit_bomb") { _, _, _ in throw AuditHostError.original }])
        let tiny = try LiquidTemplateRegistry([.init("p", .raw("P"))], limits: .init(nameUTF8Bytes: 1))
        for parsed in [false, true] { for family in 0..<4 {
            let root = try LiquidTemplate("{% include 'long' %}")
            do {
                switch (parsed, family) {
                case (false, 0): _ = try await engine.render(template: root.source, context: ["long": "p"], registry: tiny)
                case (true, 0): _ = try await engine.render(root, context: ["long": "p"], registry: tiny)
                case (false, 1): _ = try await engine.renderWithDiagnostics(template: root.source, context: ["long": "p"], registry: tiny)
                case (true, 1): _ = try await engine.renderWithDiagnostics(root, context: ["long": "p"], registry: tiny)
                case (false, 2): _ = try await engine.renderWithMetrics(template: root.source, context: ["long": "p"], registry: tiny)
                case (true, 2): _ = try await engine.renderWithMetrics(root, context: ["long": "p"], registry: tiny)
                case (false, 3): _ = try await engine.renderWithDiagnosticsAndMetrics(template: root.source, context: ["long": "p"], registry: tiny)
                default: _ = try await engine.renderWithDiagnosticsAndMetrics(root, context: ["long": "p"], registry: tiny)
                }
                Issue.record("Capacity became a successful result")
            } catch LiquidTemplateRegistry.AdmissionError.limitExceeded(let kind) { #expect(kind == .nameUTF8Bytes) }
            do {
                _ = try await auditRender("private{{ '' | audit_bomb }}{% include 'alias' %}", parsed: parsed, family: family, exact: true, entries: [("p", "P")], engine: engine, context: ["alias": "p"])
                Issue.record("Host failure became success")
            } catch AuditHostError.original {}
            await #expect(throws: LiquidError.self) {
                try await auditRender("", parsed: parsed, family: family, exact: true, entries: [("unused", "{% if %}")], engine: engine)
            }
        } }
        #expect(throws: LiquidTemplateRegistry.AdmissionError.self) { try engine.inspectDependencies(template: "{% include 'long' %}", registry: tiny) }
        #expect(try await engine.render(template: "OK", registry: tiny) == "OK")
    }

    @Test func cancellationBeforeAdmissionAndDuringSuspendedCallbacksIsTerminal() async throws {
        let root = try LiquidTemplate("before{{ '' | audit_wait }}after"), empty = try LiquidTemplateRegistry([])
        for parsed in [false, true] { for family in 0..<4 {
            let gate = TestSuspensionGate()
            let engine = try LiquidEngine(filters: [LiquidFilter("audit_wait") { value, _, _ in await gate.enter(); return value }])
            let worker = Task { try await auditRender(root.source, parsed: parsed, family: family, exact: true, entries: [], engine: engine) }
            defer { worker.cancel() }
            try await gate.waitForEntry(); worker.cancel(); _ = try await gate.release()
            await #expect(throws: CancellationError.self) { try await worker.value }
            #expect(try await engine.render(template: "OK", registry: empty) == "OK")
        } }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try LiquidEngine(limits: .init(sourceBytes: 0)).inspectDependencies(root, registry: empty, analysisLimits: .init(templates: 0)) }
        }
        await cancelled.value
    }

    @Test func htmlRemainsRawUnlessTheTemplateExplicitlyEscapes() async throws {
        for exact in [false, true] { for parsed in [false, true] { for family in 0..<4 {
            let result = try await auditRender("{{ value }}|{{ value | escape }}", parsed: parsed, family: family, exact: exact, entries: [], engine: .init(), context: ["value": "<tag>"])
            #expect(result.output == "<tag>|&lt;tag&gt;")
        } } }
    }

    @Test func concurrentRendersAndRegistryAuditPreserveRequestIsolation() async throws {
        let barrier = TestRendezvousGate(target: 16)
        let engine = try LiquidEngine(filters: [LiquidFilter("audit_hold") { value, _, _ in await barrier.enter(); return value }])
        let source = "{% include 'p' %}|{% render 'q', marker: marker %}|{{ touched }}"
        let entries = [("p", "{{ marker | audit_hold }}{% assign touched='S' %}"), ("q", "{{ marker }}{% assign touched='I' %}")]
        let registry = try LiquidTemplateRegistry(entries.map { .init($0.0, .raw($0.1)) })
        let graph = try engine.inspectDependencies(template: source, registry: registry)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask {
                    let marker = "u4-\(index)"
                    #expect(try engine.inspectDependencies(template: source, registry: registry) == graph)
                    let result = try await auditRender(source, parsed: index % 2 == 0, family: index % 4, exact: true, entries: entries, engine: engine, context: ["marker": .string(marker)])
                    #expect(result.output == "\(marker)|\(marker)|S")
                    #expect(try engine.inspectDependencies(LiquidTemplate(source), registry: registry) == graph)
                }
            }
            try await group.waitForAll()
        }
        #expect(await barrier.arrivals == 16)
    }
}
