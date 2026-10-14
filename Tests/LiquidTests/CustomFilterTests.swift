// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

private struct FilterCase: Sendable, CustomTestStringConvertible {
    let object: LiquidObject
    var testDescription: String { string("name") ?? "Unnamed filter case" }
    func string(_ key: String) -> String? {
        if case .string(let value) = object[key] { return value }
        return nil
    }
}

private enum FilterFixtures {
    static let loaded: Result<[FilterCase], Error> = Result {
        guard let url = Bundle.module.url(forResource: "custom_filters", withExtension: "json", subdirectory: "Fixtures"),
              case .object(let root) = try LiquidValue(json: String(contentsOf: url, encoding: .utf8)),
              case .array(let cases) = root["tests"] else { throw CocoaError(.fileReadCorruptFile) }
        return try cases.map {
            guard case .object(let object) = $0 else { throw CocoaError(.fileReadCorruptFile) }
            return FilterCase(object: object)
        }
    }
    static var cases: [FilterCase] { (try? loaded.get()) ?? [] }
}

private func hostFilters() -> [LiquidFilter] {
    [
        LiquidFilter("host_echo") { value, _, _ in value },
        LiquidFilter("host_kind") { value, _, _ in
            switch value {
            case .null: return "null"
            case .bool: return "bool"
            case .integer: return "integer"
            case .number: return "number"
            case .string: return "string"
            case .array: return "array"
            case .object: return "object"
            }
        },
        LiquidFilter("host_pack") { value, arguments, named in
            func text(_ value: LiquidValue) throws -> String {
                switch value {
                case .null: return ""
                case .string(let text): return text
                default: throw LiquidFilterFailure("Expected string or nil")
                }
            }
            var parts = try ([value] + arguments).map(text)
            for entry in named.entries { parts.append(entry.key + "=" + (try text(entry.value))) }
            return .string(parts.joined(separator: "|"))
        },
        LiquidFilter("host_object") { _, _, _ in ["b": 2, "a": 1] }
    ]
}

@Suite("Custom filter host extensions")
struct CustomFilterTests {
    @Test func fixtureIntegrity() throws { #expect(try FilterFixtures.loaded.get().count == 15) }

    @Test("Custom filter reference cases", arguments: FilterFixtures.cases)
    fileprivate func referenceCases(_ fixture: FilterCase) async throws {
        let source = try #require(fixture.string("template"))
        let expected = try #require(fixture.string("result"))
        let context: LiquidObject
        if case .object(let data) = fixture.object["data"] { context = data } else { context = [:] }
        var partials: [String: String] = [:]
        if case .object(let templates) = fixture.object["templates"] {
            for entry in templates.entries {
                guard case .string(let source) = entry.value else { Issue.record("Invalid fixture partial"); return }
                partials[entry.key] = source
            }
        }
        let mode: LiquidSyntaxMode = fixture.string("syntaxMode") == "strict2" ? .strict2
            : (fixture.string("syntaxMode") == "strict" ? .strict : .lax)
        let engine = try LiquidEngine(filters: hostFilters(), strictFilters: true)
        let parsed = try LiquidTemplate(source, syntaxMode: mode)
        let parsedPartials = try partials.mapValues { try LiquidTemplate($0, syntaxMode: mode) }
        #expect(try await engine.render(template: source, context: context, templates: partials, syntaxMode: mode).utf8.elementsEqual(expected.utf8))
        #expect(try await engine.render(parsed, context: context, templates: parsedPartials).utf8.elementsEqual(expected.utf8))
        let result = try await engine.renderWithDiagnostics(parsed, context: context, templates: parsedPartials)
        #expect(result.output.utf8.elementsEqual(expected.utf8))
        #expect(result.diagnostics.isEmpty)
    }

    @Test func configurationRejectsInvalidDuplicateAndProtectedNames() throws {
        for name in ["", " upcase", "two words", "name|upcase", "a.b", "0name", "x}}", "upcase", "h", "squish", "remove_last"] {
            let error = #expect(throws: LiquidError.self) {
                try LiquidEngine(filters: [LiquidFilter(name) { value, _, _ in value }])
            }
            guard case .invalidValue? = error else { Issue.record("Expected invalidValue for \(name)"); continue }
        }
        #expect(throws: LiquidError.self) { try LiquidEngine(filters: [hostFilters()[0], hostFilters()[0]]) }
        _ = try LiquidEngine(filters: [])
    }

    @Test func namesAndObjectKeysKeepExactScalarSpelling() async throws {
        let composed = "caf\u{e9}"
        let decomposed = "cafe\u{301}"
        let object = LiquidValue.object(LiquidObject([.init(composed, 1), .init(decomposed, 2)]))
        let engine = try LiquidEngine(filters: [
            LiquidFilter(composed) { _, _, _ in "A" },
            LiquidFilter(decomposed) { _, _, _ in "B" },
            LiquidFilter("host_echo") { value, _, _ in value }
        ])
        #expect(try await engine.render(template: "{{ '' | \(composed) }}{{ '' | \(decomposed) }}") == "AB")
        #expect(try await engine.render(template: "{% assign x = x | host_echo %}{{ x['\(composed)'] }}{{ x['\(decomposed)'] }}", context: ["x": object]) == "12")
        let keywords = LiquidFilter("named") { _, _, named in
            .string(named.entries.map {
                if case .integer(let value) = $0.value { return $0.key + String(value) }
                return $0.key + "?"
            }.joined(separator: "|"))
        }
        let names = try LiquidEngine(filters: [keywords])
        #expect(try await names.render(template: "{{ '' | named: \(composed): 1, \(decomposed): 2 }}").utf8.elementsEqual("\(composed)1|\(decomposed)2".utf8))
        let loop = try LiquidTemplate("{% for item in (1..3) %}{{ '' | named: \(composed): item, \(decomposed): 2 }};{% endfor %}")
        #expect(try await names.render(loop).utf8.elementsEqual("\(composed)1|\(decomposed)2;\(composed)2|\(decomposed)2;\(composed)3|\(decomposed)2;".utf8))
    }

    @Test func unregisteredFiltersKeepOnePointZeroBehavior() async throws {
        let originalInitializer: (LiquidLimits, Bool, Date?) -> LiquidEngine = LiquidEngine.init(limits:strictFilters:referenceTime:)
        let parsed = try LiquidTemplate("{{ 'data' | host_echo }}")
        #expect(try await originalInitializer(.default, false, nil).render(parsed) == "data")
        #expect(try await LiquidEngine().render(parsed) == "data")
        #expect(try await LiquidEngine(filters: []).render(parsed) == "data")
        await #expect(throws: LiquidError.self) { try await LiquidEngine(strictFilters: true).render(parsed) }
        let engine = try LiquidEngine(filters: [LiquidFilter("HOST") { _, _, _ in "custom" }])
        #expect(try await engine.render(template: "{{ 'original' | host }}") == "original")
    }

    @Test func explicitFailureUsesExistingDiagnosticBoundaries() async throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("fail") { _, _, _ in throw LiquidFilterFailure("bad input") }])
        let source = "A\n{% assign value = 'kept' %}{% assign value = '' | fail %}B{{ value }}"
        let failure = await #expect(throws: LiquidError.self) { try await engine.render(template: source) }
        guard case .rendering(let message)? = failure else { Issue.record("Expected rendering failure"); return }
        #expect(message == "Filter 'fail' failed: bad input")
        let recovered = try await engine.renderWithDiagnostics(template: source)
        #expect(recovered.output == "A\nBkept")
        #expect(recovered.diagnostics.first?.message == message)
        #expect(recovered.diagnostics.first?.line == 2)
        let partial = try await engine.renderWithDiagnostics(template: "{% render 'card' %}", templates: ["card": "{{ '' | fail }}"])
        #expect(partial.diagnostics.first?.templateName == "card")
        #expect(partial.output.contains(message))
        let strict = try await engine.renderWithDiagnostics(template: "{% assign x = '' | fail %}", syntaxMode: .strict2)
        #expect(strict.output.contains(message))
        #expect(try await engine.renderWithDiagnostics(template: "clean").diagnostics.isEmpty)
    }

    @Test func unexpectedAndOperationalCallbackErrorsAreNotRecovered() async throws {
        enum HostError: Error { case failed }
        let engine = try LiquidEngine(filters: [LiquidFilter("unexpected") { _, _, _ in throw HostError.failed }])
        for recovered in [false, true] {
            await #expect(throws: HostError.self) {
                if recovered { _ = try await engine.renderWithDiagnostics(template: "{{ '' | unexpected }}") }
                else { _ = try await engine.render(template: "{{ '' | unexpected }}") }
            }
        }
        let operational = try LiquidEngine(filters: [LiquidFilter("operational") { _, _, _ in throw LiquidError.limitExceeded("host") }])
        let error = await #expect(throws: LiquidError.self) { try await operational.renderWithDiagnostics(template: "{{ '' | operational }}") }
        guard case .limitExceeded("host")? = error else { Issue.record("Host quota error changed meaning"); return }
    }

    @Test func returnedValuesMustPassAdmissionBeforeFurtherFilters() async throws {
        for value in [LiquidValue.number(.infinity), .array([.number(.nan)])] {
            let engine = try LiquidEngine(filters: [LiquidFilter("invalid") { _, _, _ in value }])
            let error = await #expect(throws: LiquidError.self) { try await engine.renderWithDiagnostics(template: "{% assign x = '' | invalid %}") }
            guard case .invalidValue? = error else { Issue.record("Expected invalidValue"); continue }
        }
        for value in [LiquidValue.string("12345"), .array(["abc", "def"]), .object(["longkey": 1])] {
            let engine = try LiquidEngine(filters: [LiquidFilter("oversize") { _, _, _ in value }], limits: .init(outputBytes: 4))
            let error = await #expect(throws: LiquidError.self) { try await engine.renderWithDiagnostics(template: "{{ '' | oversize | size }}") }
            guard case .limitExceeded("outputBytes")? = error else { Issue.record("Expected outputBytes"); continue }
        }
        let deep = try LiquidEngine(filters: [LiquidFilter("deep") { _, _, _ in [[[[1]]]] }], limits: .init(nestingDepth: 3))
        let error = await #expect(throws: LiquidError.self) { try await deep.renderWithDiagnostics(template: "{{ '' | deep }}") }
        guard case .limitExceeded("nestingDepth")? = error else { Issue.record("Expected nestingDepth"); return }
    }

    @Test func boundariesShareCumulativeValuesAndEvaluatorSteps() async throws {
        let identity = LiquidFilter("host_echo") { value, _, _ in value }
        let engine = try LiquidEngine(filters: [identity], limits: .init(contextValues: 5))
        #expect(try await engine.render(template: "{{ x | host_echo | host_echo }}", context: ["x": 1]) == "1")
        let error = await #expect(throws: LiquidError.self) {
            try await engine.render(template: "{{ x | host_echo | host_echo | host_echo }}", context: ["x": 1])
        }
        guard case .limitExceeded("contextValues")? = error else { Issue.record("Expected cumulative values limit"); return }
        let partial = await #expect(throws: LiquidError.self) {
            try await engine.render(template: "{{ x | host_echo }}{% render 'part', x: x %}", context: ["x": 1], templates: ["part": "{{ x | host_echo | host_echo }}"])
        }
        guard case .limitExceeded("contextValues")? = partial else { Issue.record("Partials reset the value budget"); return }
        let steps = try LiquidEngine(filters: [identity], limits: .init(renderSteps: 6))
        let stepError = await #expect(throws: LiquidError.self) { try await steps.renderWithDiagnostics(template: "{{ '' | host_echo }}") }
        guard case .limitExceeded("renderSteps")? = stepError else { Issue.record("Expected renderSteps"); return }
        let many = try LiquidEngine(filters: [LiquidFilter("many") { _, _, _ in .array(Array(repeating: 1, count: 10)) }], limits: .init(contextValues: 5))
        let manyError = await #expect(throws: LiquidError.self) { try await many.renderWithDiagnostics(template: "{{ '' | many | size }}") }
        guard case .limitExceeded("contextValues")? = manyError else { Issue.record("Expected returned-value capacity"); return }
    }

    @Test func unsupportedComparisonLiteralsAndOversizedInputsFailBeforeCallback() async throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("untouched") { _, _, _ in
            Issue.record("Callback must not run"); return nil
        }], limits: .init(outputBytes: 4))
        for source in ["{{ blank | untouched }}", "{{ empty | untouched }}"] {
            let error = await #expect(throws: LiquidError.self) { try await engine.renderWithDiagnostics(template: source) }
            guard case .invalidValue? = error else { Issue.record("Expected comparison literal rejection"); continue }
        }
        let error = await #expect(throws: LiquidError.self) { try await engine.renderWithDiagnostics(template: "{{ x | untouched }}", context: ["x": "12345"]) }
        guard case .limitExceeded("outputBytes")? = error else { Issue.record("Expected input admission error"); return }
    }

    @Test(arguments: [false, true])
    func cancellationAfterSuspendingCallbackTakesPrecedenceOverRecovery(throwsFailure: Bool) async throws {
        let gate = FilterGate()
        let engine = try LiquidEngine(filters: [LiquidFilter("wait") { _, _, _ in
            await gate.enter()
            if throwsFailure { throw LiquidFilterFailure("Must not recover cancellation") }
            return "Must not return output after cancellation"
        }])
        let task = Task { try await engine.renderWithDiagnostics(template: "{{ '' | wait }}") }
        await gate.waitForEntry()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancellationAtEntryDoesNotInvokeCallback() async throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("untouched") { _, _, _ in
            Issue.record("A cancelled invocation must not call host code")
            return nil
        }])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.renderWithDiagnostics(template: "{{ '' | untouched }}")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func concurrentRendersKeepFilterConfigurationsIsolated() async throws {
        let template = try LiquidTemplate("{% increment n %}:{{ name | scoped }}")
        let first = try LiquidEngine(filters: [LiquidFilter("scoped") { value, _, _ in
            await Task.yield(); return .array(["A", value])
        }])
        let second = try LiquidEngine(filters: [LiquidFilter("scoped") { value, _, _ in
            await Task.yield(); return .array(["B", value])
        }])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<64 {
                group.addTask {
                    let context: LiquidObject = ["name": .string(String(index))]
                    #expect(try await first.render(template, context: context) == "0:A\(index)")
                    let result = try await second.renderWithDiagnostics(template, context: context)
                    #expect(result.output == "0:B\(index)" && result.diagnostics.isEmpty)
                }
            }
            try await group.waitForAll()
        }
    }
}

private actor FilterGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    func enter() async {
        entered = true
        for waiter in entryWaiters { waiter.resume() }
        entryWaiters = []
        await withCheckedContinuation { releaseContinuation = $0 }
    }
    func waitForEntry() async {
        if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
    }
    func release() { releaseContinuation?.resume(); releaseContinuation = nil }
}
