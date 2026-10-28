// SPDX-License-Identifier: Apache-2.0
import Foundation
@testable import Liquid
import Testing

private typealias ExactRegistry = LiquidTemplateRegistry
private enum ExactRoot: Sendable {
    case source(String), parsed(LiquidTemplate)
}
private struct ExactObservation: Sendable {
    let output: String
    let diagnostics: [LiquidDiagnostic]
    let metrics: LiquidRenderMetrics?
    init(_ output: String) { self.output = output; diagnostics = []; metrics = nil }
    init(_ result: LiquidRenderResult) { output = result.output; diagnostics = result.diagnostics; metrics = nil }
    init(_ result: LiquidMeasuredRenderResult) { output = result.output; diagnostics = result.diagnostics; metrics = result.metrics }
}
private func roots(_ source: String, mode: LiquidSyntaxMode = .lax) throws -> [ExactRoot] {
    [.source(source), .parsed(try LiquidTemplate(source, syntaxMode: mode))]
}
private func exactCall(_ root: ExactRoot, registry: ExactRegistry, family: Int = 0,
                       engine: LiquidEngine = .init(), context: LiquidObject = [:],
                       mode: LiquidSyntaxMode = .lax) async throws -> ExactObservation {
    switch (root, family) {
    case (.source(let source), 0): return .init(try await engine.render(template: source, context: context, registry: registry, syntaxMode: mode))
    case (.parsed(let parsed), 0): return .init(try await engine.render(parsed, context: context, registry: registry, syntaxMode: mode))
    case (.source(let source), 1): return .init(try await engine.renderWithDiagnostics(template: source, context: context, registry: registry, syntaxMode: mode))
    case (.parsed(let parsed), 1): return .init(try await engine.renderWithDiagnostics(parsed, context: context, registry: registry, syntaxMode: mode))
    case (.source(let source), 2): return .init(try await engine.renderWithMetrics(template: source, context: context, registry: registry, syntaxMode: mode))
    case (.parsed(let parsed), 2): return .init(try await engine.renderWithMetrics(parsed, context: context, registry: registry, syntaxMode: mode))
    case (.source(let source), 3): return .init(try await engine.renderWithDiagnosticsAndMetrics(template: source, context: context, registry: registry, syntaxMode: mode))
    case (.parsed(let parsed), 3): return .init(try await engine.renderWithDiagnosticsAndMetrics(parsed, context: context, registry: registry, syntaxMode: mode))
    default: preconditionFailure("Unknown test family")
    }
}
private func expectExactLimit(_ expected: String, _ operation: () async throws -> Void) async {
    do { try await operation(); Issue.record("Expected terminal \(expected)") }
    catch LiquidError.limitExceeded(let actual) { #expect(actual == expected) }
    catch { Issue.record("Wrong limit error: \(error)") }
}
private actor ExactCallbackCount {
    var count = 0
    func visit() { count += 1 }
}

@Suite("Exact registry runtime", .timeLimit(.minutes(2)))
struct ExactRegistryRenderingTests {
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func allEightFamiliesResolveNestedCanonicalSiblings(mode: LiquidSyntaxMode) async throws {
        let registry = try ExactRegistry([
            .init("é", .raw("A{% include 'e\u{301}' %}")),
            .init("e\u{301}", .parsed(LiquidTemplate("B{% render 'K' %}", syntaxMode: mode))),
            .init("K", .raw("C{% include 'K' %}")), .init("K", .raw("D"))])
        let source = "{% include 'é' %}|{% render 'e\u{301}' %}|{% include 'K' %}|{% render 'K' %}"
        for root in try roots(source, mode: mode) {
            for family in 0..<4 {
                let result = try await exactCall(root, registry: registry, family: family, mode: mode)
                #expect(result.output.utf8.elementsEqual("ABCD|BCD|CD|D".utf8))
                #expect(result.diagnostics.isEmpty)
                if let metrics = result.metrics { #expect(metrics.outputBytes == 13 && metrics.parseDuration != nil) }
            }
        }
    }

    @Test func preparedSlotsRetainOriginalIndexSpellingAndAST() async throws {
        let registry = try ExactRegistry([.init("é", .raw("A")), .init("e\u{301}", .parsed(LiquidTemplate("B"))),
            .init("K", .raw("C")), .init("K", .raw("D")), .init("x.liquid", .raw("E"))])
        var parser = ExactTemplatePreparation(limits: .default, syntaxMode: .strict2, measuring: false)
        let table = PreparedExactTemplates(registry: registry, asts: try parser.prepareEntries(registry.entries))
        #expect(table.asts.count == registry.count)
        for (index, name) in ["é", "e\u{301}", "K", "K", "x"].enumerated() {
            let selected = try #require(try table.select(name))
            #expect(selected.entryIndex == index)
            #expect(selected.storedName.utf8.elementsEqual(registry.entries[index].name.utf8))
            let rendered = try await Renderer().render(selected.ast)
            #expect(rendered == ["A", "B", "C", "D", "E"][index])
        }
        #expect(try table.select("missing") == nil)
    }

    @Test(arguments: [0, 1, 2, 3])
    func exactMissingSiblingDoesNotAlias(pair: Int) async throws {
        let pairs = [("é", "e\u{301}"), ("e\u{301}", "é"), ("K", "K"), ("K", "K")]
        let (stored, requested) = pairs[pair]
        let registry = try ExactRegistry([.init(stored, .raw("WRONG"))])
        for root in try roots("{% include '\(requested)' %}") {
            for family in [0, 2] {
                await #expect(throws: LiquidError.self) { try await exactCall(root, registry: registry, family: family) }
            }
            let recovered = try await exactCall(root, registry: registry, family: 1)
            #expect(recovered.diagnostics.count == 1 && !recovered.output.contains("WRONG"))
        }
    }

    @Test func literalSuffixAndVariableFallbackPreserveOrder() async throws {
        let registry = try ExactRegistry([.init("x", .raw("BASE")), .init("x.liquid", .raw("SUFFIX")),
            .init("only.liquid", .raw("ONLY")), .init("double.liquid.liquid", .raw("DOUBLE")),
            .init("é", .raw("A")), .init("e\u{301}", .raw("B"))])
        let source = "{% include 'x' %}|{% include 'x.liquid' %}|{% include 'only' %}|{% include 'double.liquid' %}|{% include alias %}|{% include other %}"
        for root in try roots(source) {
            let result = try await exactCall(root, registry: registry, context: ["x": "e\u{301}", "alias": "é", "other": "e\u{301}"])
            #expect(result.output == "BASE|SUFFIX|ONLY|DOUBLE|A|B")
        }
        let literal = try ExactRegistry([.init("alias.liquid", .raw("LITERAL")), .init("é", .raw("VARIABLE"))])
        #expect(try await LiquidEngine().render(template: "{% include alias %}", context: ["alias": "é"], registry: literal) == "LITERAL")
    }

    @Test func allSourceBytesIncludeUnusedMixedContentAndNamedRoot() async throws {
        let registry = try ExactRegistry([.init("é", .raw("😀")), .init("e\u{301}", .parsed(LiquidTemplate("YZ")))])
        for root in try roots("x") {
            for family in 0..<4 {
                let accepted = try await exactCall(root, registry: registry, family: family, engine: .init(limits: .init(sourceBytes: 7)))
                #expect(accepted.output == "x")
                if let metrics = accepted.metrics { #expect(metrics.sourceBytes == 7) }
                await expectExactLimit("sourceBytes") {
                    _ = try await exactCall(root, registry: registry, family: family, engine: .init(limits: .init(sourceBytes: 6)))
                }
            }
        }
        let namedRoot = try ExactRegistry([.init("root", .raw("x"))])
        await expectExactLimit("sourceBytes") { _ = try await LiquidEngine(limits: .init(sourceBytes: 1)).render(template: "x", registry: namedRoot) }
        #expect(try await LiquidEngine(limits: .init(sourceBytes: 2)).render(template: "x", registry: namedRoot) == "x")
        let empty = try ExactRegistry([])
        for root in try roots("") {
            let metrics = try await exactCall(root, registry: empty, family: 2, engine: .init(limits: .init(sourceBytes: 1)))
            #expect(metrics.output.isEmpty && metrics.metrics?.sourceBytes == 0)
        }
        for capacity in [0, -1] {
            await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(sourceBytes: capacity)).render(template: "", registry: empty) }
        }
        let many = try ExactRegistry((0..<256).map { .init("n\($0)", .raw("a")) }, limits: .init(nameUTF8Bytes: .max))
        let unlimited = LiquidEngine(limits: .init(sourceBytes: .max))
        let observed = try await unlimited.renderWithMetrics(template: "x", registry: many)
        #expect(observed.output == "x" && observed.metrics.sourceBytes == 257)
    }

    @Test func sourceAndSyntaxPreflightPrecedeCallbacksAndContext() async throws {
        let visits = ExactCallbackCount()
        let filter = LiquidFilter("touch") { value, _, _ in await visits.visit(); return value }
        let source = "{{ '' | touch }}"
        let firstInvalid = "{% if %}"
        let registry = try ExactRegistry([.init("valid", .raw("valid")), .init("first", .raw(firstInvalid)), .init("second", .raw("{% assign %}"))])
        var expected: String?
        do { _ = try LiquidTemplate(firstInvalid, syntaxMode: .strict2) }
        catch let error as LiquidError { expected = error.description }
        #expect(expected != nil)
        for root in try roots(source) {
            for family in 0..<4 {
                let engine = try LiquidEngine(filters: [filter])
                do { _ = try await exactCall(root, registry: registry, family: family, engine: engine, context: ["bad": .number(.nan)], mode: .strict2); Issue.record("Invalid source succeeded") }
                catch let error as LiquidError { #expect(error.description == expected) }
                let tight = try LiquidEngine(filters: [filter], limits: .init(sourceBytes: source.utf8.count))
                await expectExactLimit("sourceBytes") { _ = try await exactCall(root, registry: registry, family: family, engine: tight) }
            }
        }
        #expect(await visits.count == 0)
    }

    @Test func hugeUnusedSourceIsRejectedBeforeParsingOrCallback() async throws {
        let visits = ExactCallbackCount()
        let source = "{{ '' | touch }}"
        let registry = try ExactRegistry([.init("unused", .raw(String(repeating: "x", count: 50 * 1_024 * 1_024)))])
        let engine = try LiquidEngine(filters: [LiquidFilter("touch") { value, _, _ in await visits.visit(); return value }], limits: .init(sourceBytes: 1_024))
        await expectExactLimit("sourceBytes") { _ = try await engine.renderWithDiagnosticsAndMetrics(template: source, registry: registry) }
        #expect(await visits.count == 0)
    }

    @Test func parsedModesAreRetainedAndCurrentDepthIsRevalidated() async throws {
        let lax = "{{ [x] }}"
        await #expect(throws: LiquidError.self) { try await LiquidEngine().render(template: lax, registry: ExactRegistry([]), syntaxMode: .strict2) }
        let parsed = try LiquidTemplate(lax, syntaxMode: .lax)
        let parsedRegistry = try ExactRegistry([.init("p", .parsed(parsed))])
        let expected = try await LiquidEngine().render(parsed, context: ["x": "X"])
        let root = try LiquidTemplate("{% include 'p' %}", syntaxMode: .lax)
        #expect(try await LiquidEngine().render(root, context: ["x": "X"], registry: parsedRegistry, syntaxMode: .strict2) == expected)
        let empty = try ExactRegistry([])
        #expect(try await LiquidEngine().render(parsed, context: ["x": "X"], registry: empty, syntaxMode: .strict2) == expected)
        let raw = try ExactRegistry([.init("p", .raw(lax))])
        await #expect(throws: LiquidError.self) { try await LiquidEngine().render(root, registry: raw, syntaxMode: .strict2) }
        let deep = try LiquidTemplate(String(repeating: "{% if true %}", count: 8) + "x" + String(repeating: "{% endif %}", count: 8))
        let tight = LiquidEngine(limits: .init(nestingDepth: 4))
        await expectExactLimit("nestingDepth") { _ = try await tight.render(deep, registry: empty) }
        let unused = try ExactRegistry([.init("unused", .parsed(deep))])
        await expectExactLimit("nestingDepth") { _ = try await tight.render(template: "", registry: unused) }
    }

    @Test func exactNameCapacityNeverTriggersVariableRetry() async throws {
        let visits = ExactCallbackCount()
        let registry = try ExactRegistry([.init("p", .raw("{{ '' | touch }}"))], limits: .init(nameUTF8Bytes: 1))
        let engine = try LiquidEngine(filters: [LiquidFilter("touch") { value, _, _ in await visits.visit(); return value }])
        for root in try roots("{% include alias %}") {
            for family in 0..<4 {
                do { _ = try await exactCall(root, registry: registry, family: family, engine: engine, context: ["alias": "p"]); Issue.record("Capacity became fallback success") }
                catch ExactRegistry.AdmissionError.limitExceeded(let capacity) { #expect(capacity == .nameUTF8Bytes) }
            }
        }
        #expect(await visits.count == 0)
        let second = try ExactRegistry([.init("p", .raw("P"))], limits: .init(nameUTF8Bytes: 5))
        await #expect(throws: ExactRegistry.AdmissionError.self) { try await engine.renderWithDiagnostics(template: "{% include alias %}", context: ["alias": "too-long"], registry: second) }
        #expect(try await engine.render(template: "{% include 'p' %}", context: ["p": "too-long"], registry: second) == "P")
    }

    @Test func recoveryRetainsActualStoredNameForIdenticalSources() async throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("host_deny") { _, _, _ in throw LiquidFilterFailure("explicit synthetic failure") }])
        let names = ["é", "e\u{301}", "K", "K", "only.liquid"]
        let registry = try ExactRegistry(names.map { .init($0, .raw("{{ '' | host_deny }}")) })
        let source = "{% include 'é' %}{% render 'e\u{301}' %}{% include 'K' %}{% render 'K' %}{% include 'only' %}"
        for root in try roots(source) {
            for family in [1, 3] {
                let result = try await exactCall(root, registry: registry, family: family, engine: engine)
                #expect(result.diagnostics.count == names.count)
                for (diagnostic, name) in zip(result.diagnostics, names) {
                    #expect(diagnostic.templateName?.utf8.elementsEqual(name.utf8) == true)
                }
                if let metrics = result.metrics { #expect(metrics.outputBytes == result.output.utf8.count) }
            }
            await #expect(throws: LiquidError.self) { try await exactCall(root, registry: registry, engine: engine) }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func sourceParsedMetricsAndScopeMatchLegacy(mode: LiquidSyntaxMode) async throws {
        let cases = [
            ("{% include 'p' %}|{{ shared }}", "{% assign shared = 'S' %}{{ marker }}"),
            ("{% assign marker = 'local' %}{% render 'p' %}|{{ marker }}", "{{ marker }}{% assign marker = 'inside' %}{% increment n %}"),
            ("{% include 'p' for items %}|{% render 'p' for items as item %}", "{{ p }}{{ item }}{% cycle 'a','b' %}{% ifchanged %}X{% endifchanged %}"),
            ("{% for item in items %}{% include 'p' %}Z{% endfor %}", "{{ item }}{% if item == 2 %}{% continue %}{% endif %}{% if item == 3 %}{% break %}{% endif %}"),
            ("{% include 'p' with marker as item %}", "{{ item }}")]
        let context: LiquidObject = ["marker": "host", "items": [1, 2, 3]]
        for (source, partial) in cases {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            let p = try LiquidTemplate(partial, syntaxMode: mode)
            let normalLegacy = try await LiquidEngine().renderWithMetrics(parsed, context: context, templates: ["p": p])
            let recoveredLegacy = try await LiquidEngine().renderWithDiagnosticsAndMetrics(parsed, context: context, templates: ["p": p])
            for content in [ExactRegistry.Content.raw(partial), .parsed(p)] {
                let registry = try ExactRegistry([.init("p", content)])
                for root in try roots(source, mode: mode) {
                    for family in 0..<4 {
                        let result = try await exactCall(root, registry: registry, family: family, context: context, mode: mode)
                        let legacy = family == 3 ? recoveredLegacy : normalLegacy
                        #expect(result.output.utf8.elementsEqual(legacy.output.utf8))
                        #expect(result.diagnostics.isEmpty)
                        if let metrics = result.metrics {
                            #expect(metrics.sourceBytes == legacy.metrics.sourceBytes)
                            #expect(metrics.renderSteps == legacy.metrics.renderSteps)
                            #expect(metrics.loopIterations == legacy.metrics.loopIterations)
                            #expect(metrics.admittedValues == legacy.metrics.admittedValues)
                            let hasRaw: Bool
                            if case .source = root { hasRaw = true }
                            else if case .raw = content { hasRaw = true }
                            else { hasRaw = false }
                            #expect((metrics.parseDuration != nil) == hasRaw)
                            if let duration = metrics.parseDuration { #expect(duration >= .zero && metrics.totalDuration >= duration) }
                        }
                    }
                }
            }
        }
    }

    @Test func immediateTemplatesStillAdmitAllUnusedSource() async throws {
        let valid = try ExactRegistry([.init("unused", .raw(""))])
        let invalid = try ExactRegistry([.init("unused", .raw("{% if %}"))])
        for source in ["", "text", "{{ marker }}", "{{ marker }}!"] {
            let legacy = try await LiquidEngine().renderWithMetrics(template: source, context: ["marker": "M"])
            for root in try roots(source) {
                let result = try await exactCall(root, registry: valid, family: 2, context: ["marker": "M"])
                #expect(result.output == legacy.output && result.metrics?.renderSteps == legacy.metrics.renderSteps)
                #expect(result.metrics?.parseDuration != nil) // Empty raw partial is still parsed.
                await #expect(throws: LiquidError.self) { try await exactCall(root, registry: invalid, context: ["marker": "M"]) }
            }
        }
    }

    @Test func operationalFailuresReturnNoPartialMetrics() async throws {
        let registry = try ExactRegistry([.init("p", .raw("{% include 'p' %}"))])
        for (limits, source, context) in [
            (LiquidLimits(outputBytes: 1), "ab", LiquidObject()),
            (.init(renderSteps: 1), "{{ marker }}", ["marker": "M"]),
            (.init(loopIterations: 1), "{% for x in items %}x{% endfor %}", ["items": [1, 2, 3]]),
            (.init(contextValues: 1), "{{ marker }}", ["marker": [1, 2]]),
            (.init(nestingDepth: 4), "{% include 'p' %}", [:]),
            (.init(renderSteps: 0), "", [:]),
            (.default, "{{ marker }}", ["marker": .number(.nan)])] {
            for root in try roots(source) {
                for family in 0..<4 {
                    await #expect(throws: LiquidError.self) { try await exactCall(root, registry: registry, family: family, engine: .init(limits: limits), context: context) }
                }
            }
        }
    }

    @Test func hostErrorsRemainOriginalAcrossAllFamilies() async throws {
        final class HostFailure: Error {}
        let failure = HostFailure()
        let visits = ExactCallbackCount()
        let engine = try LiquidEngine(filters: [LiquidFilter("host_fail") { _, _, _ in throw failure },
            LiquidFilter("touch") { value, _, _ in await visits.visit(); return value }])
        for source in ["{{ '' | host_fail }}{% include alias %}", "{% include alias %}"] {
            let body = source.hasPrefix("{{") ? "{{ '' | touch }}" : "{{ '' | host_fail }}"
            let registry = try ExactRegistry([.init("p", .raw(body)), .init("alternate", .raw("{{ '' | touch }}"))])
            for root in try roots(source) {
                for family in 0..<4 {
                    do { _ = try await exactCall(root, registry: registry, family: family, engine: engine, context: ["alias": "p", "p": "alternate"]); Issue.record("Host error became success") }
                    catch { #expect((error as? HostFailure) === failure) }
                }
            }
        }
        // Binding pipelines are not admitted by public grammar. Keep that
        // negative control and exercise the existing binding evaluator directly.
        let unsupported = "{% include alias, value: '' | host_fail %}"
        let registry = try ExactRegistry([.init("p", .raw("{{ '' | touch }}"))])
        await #expect(throws: LiquidError.self) { try await engine.render(template: unsupported, registry: registry) }
        await #expect(throws: LiquidError.self) { try await engine.render(template: unsupported, templates: ["p": "P"]) }
        let expressionSource = try LiquidTemplate("{{ '' | host_fail }}")
        guard case .template(let nodes) = expressionSource.ast, let node = nodes.first,
              case .output(let expression, _) = node else { Issue.record("Expected filter expression"); return }
        var preparation = ExactTemplatePreparation(limits: .default, syntaxMode: .lax, measuring: false)
        let renderer = Renderer(filters: [ScalarKey("host_fail"): LiquidFilter("host_fail") { _, _, _ in throw failure }])
        renderer.setTemplateLoader(.exact(.init(registry: registry, asts: try preparation.prepareEntries(registry.entries))))
        do { _ = try await renderer.renderInclude(template: InlineString("p"), with: ["value": expression], as: nil); Issue.record("Binding host failure returned") }
        catch { #expect((error as? HostFailure) === failure) }

        #expect(await visits.count == 0)
    }

    @Test func cancellationBeforeAdmissionAndAtLookupIsTerminal() async throws {
        let registry = try ExactRegistry([.init("p", .raw("P"))])
        let inputs = try roots("{% include alias %}")
        for root in inputs {
            for family in 0..<4 {
                let cancelled = Task {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return try await exactCall(root, registry: registry, family: family, engine: .init(limits: .init(sourceBytes: 0)), context: ["alias": "p"])
                }
                await #expect(throws: CancellationError.self) { try await cancelled.value }
            }
        }
        var parser = ExactTemplatePreparation(limits: .default, syntaxMode: .lax, measuring: false)
        let loader = TemplateLoader.exact(.init(registry: registry, asts: try parser.prepareEntries(registry.entries)))
        let lookup = Task {
            let renderer = Renderer()
            renderer.setTemplateLoader(loader)
            renderer.context.setVariable("alias", value: "p")
            withUnsafeCurrentTask { $0?.cancel() }
            return try await renderer.renderInclude(template: InlineString("alias"), with: nil, as: nil)
        }
        await #expect(throws: CancellationError.self) { try await lookup.value }
    }

    @Test func cancellationDuringRawEntryPreparationPublishesNoTable() async {
        let task = Task {
            let visits = ExactEntryVisits()
            let entries = ExactCancellingEntries(source: (0..<128).map { .init("p\($0)", .raw("{{ value }}")) }, visits: visits)
            var parser = ExactTemplatePreparation(limits: .default, syntaxMode: .strict2, measuring: true)
            do { _ = try parser.prepareEntries(entries); Issue.record("Partial AST table returned") }
            catch is CancellationError {}
            catch { Issue.record("Wrong preparation error: \(error)") }
            #expect(visits.count == 65)
        }
        await task.value
    }

    @Test(arguments: [false, true])
    func cancellationDuringSuspendedFilterAndSiblingReuse(recovering: Bool) async throws {
        let registry = try ExactRegistry([.init("p", .raw("P"))])
        let inputs = try roots("{{ '' | wait }}{% include alias %}")
        for root in inputs {
            for family in (recovering ? [1, 3] : [0, 2]) {
                let gate = TestSuspensionGate()
                let engine = try LiquidEngine(filters: [LiquidFilter("wait") { _, _, _ in await gate.enter(); return "done" }])
                let task = Task { try await exactCall(root, registry: registry, family: family, engine: engine, context: ["alias": "p"]) }
                defer { task.cancel() }
                try await gate.waitForEntry()
                task.cancel()
                _ = try await gate.release()
                await #expect(throws: CancellationError.self) { try await task.value }
                #expect(try await engine.render(template: "{% include 'p' %}", registry: registry) == "P")
            }
        }
    }

    @Test func concurrentRendersKeepExactASTsBudgetsAndContextsInvocationOwned() async throws {
        let barrier = TestRendezvousGate(target: 16)
        let engine = try LiquidEngine(filters: [LiquidFilter("hold") { value, _, _ in await barrier.enter(); return value }])
        let registry = try ExactRegistry([
            .init("é", .raw("A{{ marker | hold }}{% include 'e\u{301}' %}{% assign shared = 'S' %}")),
            .init("e\u{301}", .raw("B{{ marker }}")),
            .init("K", .parsed(LiquidTemplate("K{{ marker }}{% increment n %}{% render 'K', marker: marker %}"))),
            .init("K", .raw("Q{{ marker }}"))])
        let source = "{% increment n %}|{% include 'é' %}|{{ shared }}|{% render 'K', marker: marker %}|{% increment n %}"
        let parsed = try LiquidTemplate(source)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask {
                    let marker = "u2-request-\(index)"
                    let expected = "0|A\(marker)B\(marker)|S|K\(marker)0Q\(marker)|1"
                    for repeatIndex in 0..<2 {
                        let root: ExactRoot = (index + repeatIndex) % 2 == 0 ? .source(source) : .parsed(parsed)
                        let result = try await exactCall(root, registry: registry, family: (index + repeatIndex) % 4, engine: engine, context: ["marker": .string(marker)])
                        #expect(result.output.utf8.elementsEqual(expected.utf8))
                        #expect(result.diagnostics.isEmpty)
                        if let metrics = result.metrics { #expect(metrics.admittedValues == 3 && metrics.loopIterations == 0 && metrics.parseDuration != nil) }
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await barrier.arrivals == 32)
        #expect(await barrier.firstReleaseCount == 16)
    }

    @Test func opaqueNamesStayNonIOAndUnsupportedGrammarStaysRejected() async throws {
        let names = ["../relative", "a/b", "%2e%2e", "a\0b"]
        let registry = try ExactRegistry(names.enumerated().map { .init($0.element, .raw("\($0.offset)")) })
        let source = names.map { "{% include '\($0)' %}" }.joined(separator: "|")
        #expect(try await LiquidEngine().render(template: source, registry: registry) == "0|1|2|3")
        await #expect(throws: LiquidError.self) { try await LiquidEngine().render(template: "{% render selected %}", context: ["selected": "a/b"], registry: registry) }
    }

    @Test func legacyCanonicalLookupAndGraphRemainUnchanged() async throws {
        let source = "{% include 'é' %}|{% render 'K' %}"
        var partials: [String: String] = [:]
        partials["é"] = "A"; partials["e\u{301}"] = "B"
        partials["K"] = "C"; partials["K"] = "D"
        #expect(partials.count == 2)
        let parsed = try LiquidTemplate(source)
        let templates = try partials.mapValues { try LiquidTemplate($0) }
        let engine = LiquidEngine()
        #expect(try await engine.render(template: source, templates: partials) == "B|D")
        #expect(try await engine.render(parsed, templates: templates) == "B|D")
        #expect(try await engine.renderWithDiagnostics(template: source, templates: partials).output == "B|D")
        #expect(try await engine.renderWithDiagnostics(parsed, templates: templates).output == "B|D")
        #expect(try await engine.renderWithMetrics(template: source, templates: partials).output == "B|D")
        #expect(try await engine.renderWithMetrics(parsed, templates: templates).output == "B|D")
        #expect(try await engine.renderWithDiagnosticsAndMetrics(template: source, templates: partials).output == "B|D")
        #expect(try await engine.renderWithDiagnosticsAndMetrics(parsed, templates: templates).output == "B|D")
        #expect(try engine.inspectDependencies(template: source, templates: partials).missingReferences.isEmpty)
    }
}

private final class ExactEntryVisits { var count = 0 }
private struct ExactCancellingEntries: RandomAccessCollection {
    let source: [ExactRegistry.Entry]
    let visits: ExactEntryVisits
    var startIndex: Int { source.startIndex }
    var endIndex: Int { source.endIndex }
    func index(after index: Int) -> Int { index + 1 }
    func index(before index: Int) -> Int { index - 1 }
    subscript(index: Int) -> ExactRegistry.Entry {
        visits.count += 1
        if index == 64 { withUnsafeCurrentTask { $0?.cancel() } }
        return source[index]
    }
}
