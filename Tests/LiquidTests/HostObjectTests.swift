// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

private actor HostGate {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?

    func signal() {
        entered = true
        waiter?.resume()
        waiter = nil
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private actor HostReleaseGate {
    private var entered = false
    private var observer: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        observer?.resume()
        observer = nil
        await withCheckedContinuation { release = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func finish() { release?.resume(); release = nil }
}

private enum HostProbeError: Error { case failed }

@Suite("Explicit host objects")
struct HostObjectTests {
    @Test func propertiesSupportSourceParsedDynamicKeysAndPartials() async throws {
        let object = LiquidHostObject("product", properties: [
            LiquidHostProperty("title") { "Swift" },
            LiquidHostProperty("details") { ["year": 2026] },
            LiquidHostProperty("nullValue") { nil }
        ])
        let engine = LiquidEngine()
        let source = "{{ product.title | upcase }}:{{ product[key].year }}:[{{ product.missing }}]:[{{ product.nullValue }}]"
        let context: LiquidObject = ["key": "details"]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await engine.render(template: source, context: context, hostObjects: [object], syntaxMode: mode) == "SWIFT:2026:[]:[]")
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            #expect(try await engine.render(parsed, context: context, hostObjects: [object]) == "SWIFT:2026:[]:[]")
            #expect(try await engine.render(template: "{% render 'card' %}", hostObjects: [object], templates: ["card": "{{ product.title }}"], syntaxMode: mode) == "Swift")
        }
    }

    @Test func namesRemainExactAndBindingsAreValidated() async throws {
        let composed = "caf\u{e9}"
        let decomposed = "cafe\u{301}"
        let object = LiquidHostObject("host", properties: [
            LiquidHostProperty(composed) { "A" }, LiquidHostProperty(decomposed) { "B" }
        ])
        let engine = LiquidEngine()
        let source = "{{ host['\(composed)'] }}{{ host['\(decomposed)'] }}"
        #expect(try await engine.render(template: source, hostObjects: [object]) == "AB")
        let duplicate = LiquidHostObject("host", properties: [LiquidHostProperty("x") { 1 }, LiquidHostProperty("x") { 2 }])
        await #expect(throws: LiquidError.self) { try await engine.render(template: "", hostObjects: [duplicate]) }
        await #expect(throws: LiquidError.self) { try await engine.render(template: "", hostObjects: [object, object]) }
        await #expect(throws: LiquidError.self) { try await engine.render(template: "", context: ["host": "ordinary"], hostObjects: [object]) }
        await #expect(throws: LiquidError.self) { try await engine.render(template: "", hostObjects: [LiquidHostObject("self", properties: [])]) }
    }

    @Test func hostObjectsCannotEscapeAsValues() async throws {
        let object = LiquidHostObject("host", properties: [LiquidHostProperty("title") { "visible" }])
        let engine = LiquidEngine()
        for source in ["{{ host }}", "A{{ host }}B", "{{ host | upcase }}", "{% if host %}yes{% endif %}",
                       "{% assign x = host %}{{ x }}", "{{ self.host }}", "{{ self.host.name }}",
                       "{% assign alias = self %}{{ alias.host.name }}", "{{ host[0] }}"] {
            await #expect(throws: LiquidError.self) { try await engine.render(template: source, hostObjects: [object]) }
        }
        #expect(try await engine.render(template: "{{ host.title }}", hostObjects: [object]) == "visible")
    }

    @Test func ordinaryContextKeepsItsExistingBehavior() async throws {
        let context: LiquidObject = ["title": "Swift", "items": [1, 2], "record": ["first": "custom"]]
        let source = "{{ title.first }}|{{ title.last }}|{{ items.first }}|{{ record.first }}|{{ title.first | upcase }}"
        let engine = LiquidEngine()
        let ordinary = try await engine.render(template: source, context: context)
        let host = LiquidHostObject("host", properties: [LiquidHostProperty("value") { "unused" }])
        #expect(try await engine.render(template: source, context: context, hostObjects: [host]) == ordinary)
    }

    @Test func callbackValuesUseExistingBudgets() async throws {
        let object = LiquidHostObject("host", properties: [LiquidHostProperty("value") { .array([1, 2, 3]) }])
        let engine = LiquidEngine(limits: LiquidLimits(contextValues: 2))
        let error = await #expect(throws: LiquidError.self) { try await engine.render(template: "{{ host.value }}", hostObjects: [object]) }
        guard case .limitExceeded("contextValues")? = error else { Issue.record("Expected context capacity failure"); return }
        let invalid = LiquidHostObject("host", properties: [LiquidHostProperty("value") { .number(.infinity) }])
        await #expect(throws: LiquidError.self) { try await LiquidEngine().render(template: "{{ host.value }}", hostObjects: [invalid]) }
    }

    @Test func cancellationDuringSuspendingPropertyPreservesReuse() async throws {
        let gate = HostGate()
        let object = LiquidHostObject("host", properties: [LiquidHostProperty("value") {
            await gate.signal()
            try await Task.sleep(for: .seconds(30))
            return "unexpected"
        }])
        let engine = LiquidEngine()
        let task = Task { try await engine.render(template: "{{ host.value }}", hostObjects: [object]) }
        await gate.waitUntilEntered()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let healthy = LiquidHostObject("host", properties: [LiquidHostProperty("value") { "healthy" }])
        #expect(try await engine.render(template: "{{ host.value }}", hostObjects: [healthy]) == "healthy")
    }

    @Test func cancellationAfterUncooperativeHostReturns() async throws {
        let gate = HostReleaseGate()
        let object = LiquidHostObject("host", properties: [LiquidHostProperty("value") {
            await gate.suspend()
            return "must not escape"
        }])
        let task = Task { try await LiquidEngine().render(template: "{{ host.value }}", hostObjects: [object]) }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func unexpectedCallbackErrorsRemainErrors() async throws {
        let object = LiquidHostObject("host", properties: [LiquidHostProperty("value") { throw HostProbeError.failed }])
        await #expect(throws: HostProbeError.self) {
            try await LiquidEngine().render(template: "{{ host.value }}", hostObjects: [object])
        }
    }

    @Test func concurrentRendersKeepHostBindingsIndependent() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{{ host.value }}")
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<32 {
                group.addTask {
                    let object = LiquidHostObject("host", properties: [LiquidHostProperty("value") { .integer(index) }])
                    return try await engine.render(template, hostObjects: [object])
                }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(Set(outputs) == Set((0..<32).map(String.init)))
    }
}
