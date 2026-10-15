// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import Liquid

@Test func concurrentRendersOwnTheirScopesAndCounters() async throws {
    let engine = LiquidEngine(referenceTime: Date(timeIntervalSince1970: 0))
    let template = try LiquidTemplate("{% increment n %}:{{ name }}:{% assign name = 'local' %}{{ name }}")
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<64 {
            group.addTask {
                let output = try await engine.render(template, context: ["name": .string(String(index))])
                #expect(output == "0:\(index):local")
                #expect(try await engine.render(template: "{{ 'Jan 1' | date: '%F' }}") == "1970-01-01")
            }
        }
        try await group.waitForAll()
    }
}

@Test func partialScopesAndStateAreInvocationOwned() async throws {
    let template = "{% assign name = 'outer' %}{% render 'part' %}|{{ name }}|{% include 'part' %}|{{ name }}"
    let output = try await LiquidEngine().render(template: template, templates: ["part": "{{ name }}{% assign name = 'inner' %}"])
    #expect(output == "|outer|outer|inner")
}

@Test func orderedObjectIterationAndJSONOrderAgree() async throws {
    let value = try LiquidValue(json: #"{"item":{"b":2,"a":1}}"#)
    let context = try #require({ if case .object(let object) = value { return object }; return nil }())
    let output = try await LiquidEngine().render(template: "{% for pair in item %}{{ pair[0] }}={{ pair[1] }};{% endfor %}", context: context)
    #expect(output == "b=2;a=1;")
    let object: LiquidObject = ["b": 2, "a": 1, "b": 3]
    #expect(object.entries.map(\.key) == ["b", "a"])
    #expect(object["b"] == 3)
}

@Test func truthinessAndComparisonLiteralsRemainDistinct() async throws {
    let output = try await LiquidEngine().render(template: "{% if zero %}Z{% endif %}{% if values %}A{% endif %}{% if nil == empty %}X{% endif %}{% if false == blank %}B{% endif %}", context: ["zero": 0, "values": []])
    #expect(output == "ZAB")
}

@Test func standardEscapingAndUnknownFilters() async throws {
    let engine = LiquidEngine()
    #expect(try await engine.render(template: "{{ text | h }}", context: ["text": "<p>"]) == "&lt;p&gt;")
    #expect(try await engine.render(template: "{{ text | json }}", context: ["text": "data"]) == "data")
    await #expect(throws: LiquidError.self) {
        try await LiquidEngine(strictFilters: true).render(template: "{{ 'data' | json }}")
    }
}

@Test(arguments: ["{% macro hi() %}{% endmacro %}", "{% extends 'base' %}", "{% debug name %}", "{% load 'private.json' %}", "{{ hi() }}"])
func platformExtensionsAreRejected(source: String) {
    #expect(throws: LiquidError.self) { try LiquidTemplate(source) }
}

@Test func failuresExposePublicSyntaxAndRenderErrors() async throws {
    do {
        _ = try LiquidTemplate("{% if %}")
        Issue.record("Expected syntax error")
    } catch let error as LiquidError {
        guard case .syntax = error else { Issue.record("Expected public syntax error"); return }
    } catch { Issue.record("Unexpected error type") }
    await #expect(throws: LiquidError.self) { try await LiquidEngine().render(template: "{% render 'missing' %}") }
}

@Test(arguments: ["{\"a\":1,\"a\":2}", "[1,]", "01", "true false", "1e9999", "\"\\uD800\""])
func malformedJSONIsRejected(source: String) {
    #expect(throws: LiquidJSONError.self) { try LiquidValue(json: source) }
}

@Test func JSONNumbersKeepIntegersAndBooleansDistinct() throws {
    let value = try LiquidValue(json: "[true,0,9007199254740993,0.5,null]")
    #expect(value == .array([true, 0, 9_007_199_254_740_993, 0.5, nil]))
}

@Test func sourceAndOutputLimitsUseUTF8Bytes() async throws {
    let admitted = try LiquidTemplate("éé", limits: .init(sourceBytes: 4))
    #expect(admitted.source == "éé")
    #expect(throws: LiquidError.self) { try LiquidTemplate("éé", limits: .init(sourceBytes: 3)) }
    await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 3)).render(admitted) }
}

@Test func loopsShareOneCumulativeBudgetAcrossPartials() async throws {
    let engine = LiquidEngine(limits: .init(loopIterations: 3))
    await #expect(throws: LiquidError.self) {
        try await engine.render(template: "{% for x in items %}{% render 'part', items: items %}{% endfor %}", context: ["items": [1, 2]], templates: ["part": "{% for x in items %}x{% endfor %}"])
    }
}

@Test func emptyLoopBodiesStillChargeIterations() async throws {
    await #expect(throws: LiquidError.self) {
        try await LiquidEngine(limits: .init(loopIterations: 2)).render(template: "{% for x in items %}{% endfor %}", context: ["items": [1, 2, 3]])
    }
}

@Test func nestedSyntaxIsRejectedBeforeDeepRecursion() {
    let source = String(repeating: "{% if true %}", count: 200) + String(repeating: "{% endif %}", count: 200)
    #expect(throws: LiquidError.self) { try LiquidTemplate(source) }
}

@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func cancellationStopsAnEnteredLoopAndPreservesSiblingRender(parsedInput: Bool) async throws {
    let gate = TestSuspensionGate()
    let engine = try LiquidEngine(filters: [LiquidFilter("pause") { value, _, _ in
        await gate.enter()
        return value // The engine must observe cancellation after a successful callback.
    }, LiquidFilter("unreachable") { _, _, _ in
        Issue.record("Cancelled loop reached a later callback")
        return nil
    }])
    let parsed = try LiquidTemplate("{% increment n %}{% for x in (1..3) %}{{ x | pause | unreachable }}{% endfor %}")
    let worker = Task {
        if parsedInput { return try await engine.render(parsed) }
        return try await engine.render(template: parsed.source)
    }
    defer { worker.cancel() }
    try await gate.waitForEntry()
    #expect(try await engine.render(template: "{% increment n %}healthy") == "0healthy")
    worker.cancel()
    _ = try await gate.release()
    await #expect(throws: CancellationError.self) { try await worker.value }
    #expect(try await engine.render(template: "{% increment n %}healthy") == "0healthy")
}

@Test func arithmeticOverflowAndNonfiniteContextThrow() async throws {
    await #expect(throws: LiquidError.self) {
        try await LiquidEngine().render(template: "{{ value | plus: 1 }}", context: ["value": .integer(Int.max)])
    }
    await #expect(throws: LiquidError.self) {
        try await LiquidEngine().render(template: "{{ value }}", context: ["value": .number(.infinity)])
    }
    #expect(try await LiquidEngine().render(template: "{{ value | modulo: -1 }}", context: ["value": .integer(Int.min)]) == "0")
}

@Test func integerLiteralsAndFiltersDoNotRoundThroughDouble() async throws {
    let engine = LiquidEngine()
    let output = try await engine.render(template: "{{ 9007199254740993 }}|{{ 9007199254740993 | plus: 1 }}|{% if 9007199254740993 > 9007199254740992 %}yes{% endif %}")
    #expect(output == "9007199254740993|9007199254740994|yes")
    #expect(try await engine.render(template: "{{ items | sum }}", context: ["items": [9_007_199_254_740_993, 1]]) == "9007199254740994")
    await #expect(throws: LiquidError.self) {
        try await engine.render(template: "{{ value | abs }}", context: ["value": .integer(Int.min)])
    }
}

@Test func dateRangeAndFormattingRespectOperationalLimits() async throws {
    let engine = LiquidEngine()
    for value in [LiquidValue.integer(Int.min), .integer(Int.max), .string(String(repeating: "9", count: 100))] {
        do {
            _ = try await engine.render(template: "{{ value | date: '%F' }}", context: ["value": value])
            Issue.record("Expected a date range error")
        } catch let error as LiquidError {
            guard case .invalidValue = error else { Issue.record("Expected invalidValue, received \(error)"); continue }
        }
    }
    func expectLimit(_ expected: String, operation: () async throws -> String) async {
        let error = await #expect(throws: LiquidError.self) { try await operation() }
        if case .limitExceeded(let name)? = error { #expect(name == expected) }
        else { Issue.record("Expected limitExceeded(\(expected))") }
    }
    for format in ["%1025Y", "%999999999999999999999N"] {
        await expectLimit("date padding") {
            try await engine.render(template: "{{ '2024-02-03' | date: format }}", context: ["format": .string(format)])
        }
    }
    let small = LiquidEngine(limits: .init(outputBytes: 4))
    #expect(try await small.render(template: "{{ '2024-02-03' | date: '%Y' }}") == "2024")
    await expectLimit("outputBytes") {
        try await small.render(template: "{{ '2024-02-03' | date: '%1000Y' }}")
    }
    await expectLimit("renderSteps") {
        try await LiquidEngine(limits: .init(renderSteps: 10)).render(
            template: "{{ '2024-02-03' | date: format }}", context: ["format": .string(String(repeating: "x", count: 100))])
    }
}

@Test func recoveredErrorsAreExplicitAndInvocationOwned() async throws {
    let engine = LiquidEngine()
    let template = try LiquidTemplate("A{% assign b = items | reject: missing %}B")
    await #expect(throws: LiquidError.self) { try await engine.render(template, context: ["items": ["x"]]) }
    let result = try await engine.renderWithDiagnostics(template, context: ["items": ["x"]])
    #expect(result.output == "AB")
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics.first?.message == "cannot select the property ''")
    #expect(result.diagnostics.first?.line == 1)
    let clean = try await engine.renderWithDiagnostics(template, context: ["items": []])
    #expect(clean.output == "AB")
    #expect(clean.diagnostics.isEmpty)
    await #expect(throws: LiquidError.self) {
        try await LiquidEngine(limits: .init(outputBytes: 1)).renderWithDiagnostics(template, context: ["items": ["x"]])
    }
}
