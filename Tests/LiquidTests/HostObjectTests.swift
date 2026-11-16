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
private actor DynamicAccessCounter {
    private(set) var keys: [String] = []
    func record(_ key: String) { keys.append(key) }
}

@Suite("Explicit host objects")
struct HostObjectTests {
    @Test func boxedNumberPreservesNumericAndObjectBehavior() async throws {
        let engine = LiquidEngine()
        let source = "{{ d }}|{% if d %}T{% else %}F{% endif %}|{% if d == 0 %}Z{% else %}N{% endif %}|{% if d == empty %}E{% else %}N{% endif %}|{{ d | plus: 1 }}|{{ d | size }}|{{ d | first }}|{{ d | last }}|[{{ d.size }}]|[{{ d[0] }}]"
        for (value, expected) in [(0, "0|T|Z|N|1|0|||[]|[]"), (41, "41|T|N|N|42|0|||[]|[]"), (-2, "-2|T|N|N|-1|0|||[]|[]")] {
            let host = LiquidHostObject("d", numberValue: value)
            for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
                #expect(try await engine.render(template: source, hostObjects: [host], syntaxMode: mode) == expected)
                #expect(try await engine.render(LiquidTemplate(source, syntaxMode: mode), hostObjects: [host]) == expected)
                let aliases = "{% assign x = d %}[{{ x.size }}]|[{{ self.d.size }}]|{{ self.d }}|{% assign x = d | default: 'no' %}[{{ x.size }}]|{{ x }}"
                #expect(try await engine.render(template: aliases, hostObjects: [host], syntaxMode: mode) == "[]|[]|\(value)|[]|\(value)")
                #expect(try await engine.render(template: "{% render 'p' %}", hostObjects: [host], templates: ["p": "{{ d }}"], syntaxMode: mode) == String(value))
            }
        }
        for value in [Int.min, Int.max] {
            #expect(try await engine.render(template: "{{ d }}", hostObjects: [LiquidHostObject("d", numberValue: value)]) == String(value))
        }
        let custom = try LiquidEngine(filters: [LiquidFilter("is_integer") { value, _, _ in
            if case .integer = value { return "integer" }; return "wrong"
        }])
        #expect(try await custom.render(template: "{{ d | is_integer }}", hostObjects: [LiquidHostObject("d", numberValue: 0)]) == "integer")
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(contextValues: 1)).render(template: "{{ d }}", hostObjects: [LiquidHostObject("d", numberValue: 0)])
        }
    }

    @Test func concurrentRendersKeepBoxedNumbersInvocationScoped() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{{ d | plus: 1 }}")
        let outputs = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<32 {
                group.addTask {
                    let text = try await engine.render(template, hostObjects: [LiquidHostObject("d", numberValue: index)])
                    return Int(text) ?? -1
                }
            }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(outputs.sorted() == Array(1...32))
    }

    @Test func boxedBooleanKeepsReferenceTruthinessEqualityAndFilters() async throws {
        let engine = LiquidEngine()
        let source = "{{ d }}|{% if d %}T{% else %}F{% endif %}|{% if d == true %}T{% else %}F{% endif %}|{% if d == blank %}T{% else %}F{% endif %}|{% if d == empty %}T{% else %}F{% endif %}|{{ d | default: 'fallback' }}|{{ d | default: 'fallback', allow_false: true }}|{{ d | upcase }}|{{ d | first }}|{{ d | last }}|{{ d | size }}"
        for (value, expected) in [(true, "true|T|T|F|F|true|true|TRUE|||0"),
                                  (false, "false|F|F|T|F|fallback|false|FALSE|||0")] {
            let host = LiquidHostObject("d", booleanValue: value)
            for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
                #expect(try await engine.render(template: source, hostObjects: [host], syntaxMode: mode) == expected)
                #expect(try await engine.render(LiquidTemplate(source, syntaxMode: mode), hostObjects: [host]) == expected)
                let aliases = "{% assign x = d %}{{ x }}|[{{ x.value }}]|[{{ self.d.value }}]|{{ self.d }}|{{ d | default: 'no', allow_false: true }}"
                #expect(try await engine.render(template: aliases, hostObjects: [host], syntaxMode: mode) == "\(value ? "true" : "false")|[]|[]|\(value ? "true" : "false")|\(value ? "true" : "false")")
                #expect(try await engine.render(template: "{% render 'p' %}", hostObjects: [host], templates: ["p": "{{ d }}"], syntaxMode: mode) == (value ? "true" : "false"))
                let selected = "{% assign x = d | default: 'fallback', allow_false: true %}[{{ x.value }}]|{{ x }}"
                #expect(try await engine.render(template: selected, hostObjects: [host], syntaxMode: mode) == "[]|\(value ? "true" : "false")")
                let referenceControls = "{% if true == d %}T{% else %}F{% endif %}|{% unless d %}T{% else %}F{% endunless %}|{{ d | append: '!' }}|{{ d | plus: 1 }}|{% for x in d %}{{ x }}{% else %}empty{% endfor %}"
                #expect(try await engine.render(template: referenceControls, hostObjects: [host], syntaxMode: mode) == (value ? "T|F|true!|1|empty" : "F|T|false!|1|empty"))
            }
        }
        let custom = try LiquidEngine(filters: [LiquidFilter("is_boolean") { value, _, _ in
            if case .bool = value { return "boolean" }; return "wrong"
        }])
        #expect(try await custom.render(template: "{{ d | is_boolean }}", hostObjects: [LiquidHostObject("d", booleanValue: false)]) == "boolean")
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(contextValues: 1)).render(template: "{{ d }}", hostObjects: [LiquidHostObject("d", booleanValue: true)])
        }
    }

    @Test func concurrentRendersKeepBoxedBooleansInvocationScoped() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{% if d %}T{% else %}F{% endif %}")
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<32 {
                group.addTask { try await engine.render(template, hostObjects: [LiquidHostObject("d", booleanValue: index.isMultiple(of: 2))]) }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(outputs.filter { $0 == "T" }.count == 16)
        #expect(outputs.filter { $0 == "F" }.count == 16)
    }

    @Test func typedIndexerPreservesKeysAndPropertyPrecedence() async throws {
        let host = LiquidHostObject("drop", properties: [LiquidHostProperty("fixed") { "exact" }],
            dynamicProperties: [LiquidHostDynamicProperty(prefix: "dyn_") { key in key == "dyn_missing" ? nil : "dynamic" }],
            indexer: LiquidHostIndexer { key in
                switch key {
                case .integer(let value): return .string("i:\(value)")
                case .string(let value): return .string("s:\(value)")
                case .other: return "other"
                }
            })
        let source = "{{ drop[0] }}|{{ drop[-1] }}|{{ drop['0'] }}|{{ drop.fixed }}|{{ drop.dyn_key }}|[{{ drop.dyn_missing }}]|{{ drop[true] }}|{{ drop[1.5] }}|{{ drop[missing] }}"
        let expected = "i:0|i:-1|s:0|exact|dynamic|[]|other|other|other"
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await LiquidEngine().render(template: source, hostObjects: [host], syntaxMode: mode) == expected)
            #expect(try await LiquidEngine().render(LiquidTemplate(source, syntaxMode: mode), hostObjects: [host]) == expected)
            #expect(try await LiquidEngine().render(template: "{{ drop[key] }}", context: ["key": 0], hostObjects: [host], syntaxMode: mode) == "i:0")
            #expect(try await LiquidEngine().render(template: "{{ drop[key] }}", context: ["key": "0"], hostObjects: [host], syntaxMode: mode) == "s:0")
            #expect(try await LiquidEngine().render(template: "{{ drop[key] }}", context: ["key": false], hostObjects: [host], syntaxMode: mode) == "other")
        }
        let oldHost = LiquidHostObject("drop", properties: [])
        await #expect(throws: LiquidError.self) { try await LiquidEngine().render(template: "{{ drop[0] }}", hostObjects: [oldHost]) }
    }

    @Test func cancellationAndIndexerResultsUseInvocationBudgets() async throws {
        let oversized = LiquidHostObject("drop", indexer: LiquidHostIndexer { _ in [1, 2, 3] })
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(contextValues: 3)).render(template: "{{ drop[0] }}", hostObjects: [oversized])
        }
        let gate = HostReleaseGate()
        let blocked = LiquidHostObject("drop", indexer: LiquidHostIndexer { _ in
            await gate.suspend(); return "must not escape"
        })
        let task = Task { try await LiquidEngine().render(template: "{{ drop[0] }}", hostObjects: [blocked]) }
        await gate.waitUntilEntered(); task.cancel(); await gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        let throwing = LiquidHostObject("drop", indexer: LiquidHostIndexer { _ in throw HostProbeError.failed })
        await #expect(throws: HostProbeError.self) { try await LiquidEngine().render(template: "{{ drop[0] }}", hostObjects: [throwing]) }
    }

    @Test func concurrentRendersKeepIndexersInvocationScoped() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{{ drop[0] }}")
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<32 {
                group.addTask {
                    let host = LiquidHostObject("drop", indexer: LiquidHostIndexer { _ in .integer(index) })
                    return try await engine.render(template, hostObjects: [host])
                }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(Set(outputs) == Set((0..<32).map(String.init)))
    }

    @Test func dynamicFamiliesAreExplicitExactAndDeterministic() async throws {
        let host = LiquidHostObject("drop", properties: [LiquidHostProperty("op_fixed") { "fixed" }], dynamicProperties: [
            LiquidHostDynamicProperty(prefix: "op_") { key in .string("general:" + key) },
            LiquidHostDynamicProperty(prefix: "op_deep_") { key in .string("specific:" + key) },
            LiquidHostDynamicProperty(prefix: "missing_") { _ in nil }
        ])
        let source = "{{ drop.op_fixed }}|{{ drop.op_any }}|{{ drop.op_deep_x }}|[{{ drop.missing_x }}]|[{{ drop.secret }}]"
        let expected = "fixed|general:op_any|specific:op_deep_x|[]|[]"
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await LiquidEngine().render(template: source, hostObjects: [host], syntaxMode: mode) == expected)
            #expect(try await LiquidEngine().render(LiquidTemplate(source, syntaxMode: mode), hostObjects: [host]) == expected)
        }
        let unicode = LiquidHostObject("drop", dynamicProperties: [LiquidHostDynamicProperty(prefix: "café_") { _ in "matched" }])
        #expect(try await LiquidEngine().render(template: "{{ drop['café_x'] }}|[{{ drop['cafe\u{301}_x'] }}]", hostObjects: [unicode]) == "matched|[]")
        let empty = LiquidHostObject("drop", dynamicProperties: [LiquidHostDynamicProperty(prefix: "") { _ in nil }])
        let duplicate = LiquidHostObject("drop", dynamicProperties: [LiquidHostDynamicProperty(prefix: "x") { _ in nil }, LiquidHostDynamicProperty(prefix: "x") { _ in nil }])
        for invalid in [empty, duplicate] {
            await #expect(throws: LiquidError.self) { try await LiquidEngine().render(template: "", hostObjects: [invalid]) }
        }
    }

    @Test func cancellationAndDynamicFamilyResultsUseInvocationBudgets() async throws {
        let oversized = LiquidHostObject("drop", dynamicProperties: [LiquidHostDynamicProperty(prefix: "x_") { _ in [1, 2, 3] }])
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(contextValues: 3)).render(template: "{{ drop.x_a }}", hostObjects: [oversized])
        }
        let gate = HostGate()
        let blocked = LiquidHostObject("drop", dynamicProperties: [LiquidHostDynamicProperty(prefix: "x_") { _ in
            await gate.signal(); try await Task.sleep(for: .seconds(30)); return "unexpected"
        }])
        let task = Task { try await LiquidEngine().render(template: "{{ drop.x_a }}", hostObjects: [blocked]) }
        await gate.waitUntilEntered(); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let throwsHost = LiquidHostObject("drop", dynamicProperties: [LiquidHostDynamicProperty(prefix: "x_") { _ in throw HostProbeError.failed }])
        await #expect(throws: HostProbeError.self) { try await LiquidEngine().render(template: "{{ drop.x_a }}", hostObjects: [throwsHost]) }
    }

    @Test func cancellationAfterDynamicFamilyReturnsKeepsReuse() async throws {
        let counter = DynamicAccessCounter()
        let host = LiquidHostObject("drop", dynamicProperties: [LiquidHostDynamicProperty(prefix: "ok_") { key in
            await counter.record(key); return .string(key)
        }])
        let source = "{{ drop.ok_one }}|[{{ drop.secret }}]|{{ drop.ok_two }}"
        #expect(try await LiquidEngine().render(template: source, hostObjects: [host]) == "ok_one|[]|ok_two")
        #expect(await counter.keys == ["ok_one", "ok_two"])
        let gate = HostReleaseGate()
        let blocked = LiquidHostObject("drop", dynamicProperties: [LiquidHostDynamicProperty(prefix: "x_") { _ in
            await gate.suspend(); return "must not escape"
        }])
        let task = Task { try await LiquidEngine().render(template: "{{ drop.x_a }}", hostObjects: [blocked]) }
        await gate.waitUntilEntered(); task.cancel(); await gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await LiquidEngine().render(template: "{{ drop.ok_reused }}", hostObjects: [host]) == "ok_reused")
    }

    @Test func concurrentRendersKeepDynamicFamiliesInvocationScoped() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{{ drop.value_key }}")
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<32 {
                group.addTask {
                    let object = LiquidHostObject("drop", dynamicProperties: [
                        LiquidHostDynamicProperty(prefix: "value_") { _ in .integer(index) }
                    ])
                    return try await engine.render(template, hostObjects: [object])
                }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(Set(outputs) == Set((0..<32).map(String.init)))
    }

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
