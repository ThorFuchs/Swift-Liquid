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

private func makeIntegerNode(_ value: Int) -> LiquidHostNode {
    LiquidHostNode(integerValue: value, properties: [
        LiquidHostNodeProperty("self") { .current },
        LiquidHostNodeProperty("plain") { .value(.integer(value)) },
        LiquidHostNodeProperty("next") {
            let (next, overflow) = value.addingReportingOverflow(1)
            guard !overflow else { throw LiquidError.invalidValue("Node overflow") }
            return .node(makeIntegerNode(next))
        },
        LiquidHostNodeProperty("missing") { .missing }
    ])
}

@Suite("Explicit host objects")
struct HostObjectTests {
    @Test func optedInHostWithBindingPreservesPartialRecoveryAndIsolation() async throws {
        let host = LiquidHostObject("source", partialBindingIndexer: LiquidHostIndexer { key in
            if key == .string("visible") { return "yes" }
            if key == .string("bad") { throw LiquidHostFailure("host denied") }
            return nil
        })
        let engine = LiquidEngine()
        let source = "{% render 'card' with source %}"
        let partial = "{{ card.visible }}|{{ card.bad }}|[{{ card.name }}]"
        let result = try await engine.renderWithDiagnostics(template: source, hostObjects: [host], templates: ["card": partial], syntaxMode: .strict2)
        #expect(result.output == "yes|Liquid error (card line 1): host denied|[]")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.message == "host denied")
        #expect(result.diagnostics.first?.templateName == "card")
        #expect(result.diagnostics.first?.line == 1)
        let root = try LiquidTemplate(source, syntaxMode: .strict2)
        let selected = LiquidTemplateNameResolver(select: { name in name == "card" ? "CARD" : nil }, missing: { _ in "missing" })
        let parsedResult = try await engine.renderWithDiagnostics(root, hostObjects: [host], partialSources: ["CARD": partial], resolver: selected)
        #expect(parsedResult.output == "yes|Liquid error (CARD line 1): host denied|[]")
        #expect(parsedResult.diagnostics.first?.templateName == "CARD")
        let parsedPartial = try LiquidTemplate(partial, syntaxMode: .strict2)
        let storedResult = try await engine.renderWithDiagnostics(root, hostObjects: [host], templates: ["card": parsedPartial])
        #expect(storedResult.output == result.output)
        for invalid in ["{{ source }}", "{% assign x = source %}{{ x }}", "{% include 'card' with source %}", "{% render 'card', card: source %}"] {
            await #expect(throws: LiquidError.self) { try await engine.render(template: invalid, hostObjects: [host], templates: ["card": partial]) }
        }
        let ordinary = LiquidHostObject("source", indexer: LiquidHostIndexer { _ in "yes" })
        await #expect(throws: LiquidError.self) { try await engine.render(template: source, hostObjects: [ordinary], templates: ["card": partial]) }
        await #expect(throws: LiquidError.self) { try await engine.render(template: source, hostObjects: [host], templates: ["card": "{{ card }}"]) }
    }

    @Test func cancellationDuringOptedInPartialHostAccessPreservesReuse() async throws {
        let gate = HostReleaseGate()
        let host = LiquidHostObject("source", partialBindingIndexer: LiquidHostIndexer { _ in
            await gate.suspend()
            throw LiquidHostFailure("late")
        })
        let engine = LiquidEngine()
        let task = Task { try await engine.renderWithDiagnostics(template: "{% render 'card' with source %}", hostObjects: [host], templates: ["card": "{{ card.bad }}"]) }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        let healthy = LiquidHostObject("source", partialBindingIndexer: LiquidHostIndexer { _ in "ok" })
        #expect(try await engine.render(template: "{% render 'card' with source %}", hostObjects: [healthy], templates: ["card": "{{ card.visible }}"]) == "ok")
    }

    @Test func concurrentRendersKeepOptedInPartialHostBindingsIndependent() async throws {
        let engine = LiquidEngine()
        let root = try LiquidTemplate("{% render 'card' with source %}", syntaxMode: .strict2)
        let partial = try LiquidTemplate("{{ card.value }}", syntaxMode: .strict2)
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<24 {
                group.addTask {
                    let host = LiquidHostObject("source", partialBindingIndexer: LiquidHostIndexer { _ in .integer(i) })
                    return try await engine.render(root, hostObjects: [host], templates: ["card": partial])
                }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(Set(outputs) == Set((0..<24).map(String.init)))
    }

    @Test func explicitHostFailuresUseRaisingAndDiagnosticPolicies() async throws {
        let exact = LiquidHostObject("host", properties: [LiquidHostProperty("bad") { throw LiquidHostFailure("host denied") }])
        let indexed = LiquidHostObject("host", indexer: LiquidHostIndexer { _ in throw LiquidHostFailure("host denied") })
        let dynamic = LiquidHostObject("host", dynamicProperties: [LiquidHostDynamicProperty(prefix: "bad") { _ in throw LiquidHostFailure("host denied") }])
        let node = LiquidHostObject("host", node: LiquidHostNode(integerValue: 1, properties: [LiquidHostNodeProperty("bad") { throw LiquidHostFailure("host denied") }]))
        let engine = LiquidEngine()
        for host in [exact, indexed, dynamic, node] {
            let failure = await #expect(throws: LiquidError.self) { try await engine.render(template: "A{{ host.bad }}B", hostObjects: [host], syntaxMode: .strict2) }
            guard case .rendering("host denied")? = failure else { Issue.record("Expected explicit host rendering failure"); continue }
            let result = try await engine.renderWithDiagnostics(template: "A{{ host.bad }}B", hostObjects: [host], syntaxMode: .strict2)
            #expect(result.output == "ALiquid error (line 1): host deniedB")
            #expect(result.diagnostics.count == 1)
            #expect(result.diagnostics.first?.message == "host denied")
            #expect(result.diagnostics.first?.line == 1)
            let parsed = try LiquidTemplate("{% render 'card' %}", syntaxMode: .strict2)
            let partial = try LiquidTemplate("start\n{{ host.bad }}", syntaxMode: .strict2)
            let partialResult = try await engine.renderWithDiagnostics(parsed, hostObjects: [host], templates: ["card": partial])
            #expect(partialResult.output == "start\nLiquid error (card line 2): host denied")
            #expect(partialResult.diagnostics.first?.templateName == "card")
            #expect(partialResult.diagnostics.first?.line == 2)
        }
        let unexpected = LiquidHostObject("host", properties: [LiquidHostProperty("bad") { throw HostProbeError.failed }])
        await #expect(throws: HostProbeError.self) { try await engine.renderWithDiagnostics(template: "{{ host.bad }}", hostObjects: [unexpected]) }
        let oversized = LiquidHostObject("h", properties: [LiquidHostProperty("x") { throw LiquidHostFailure(String(repeating: "a", count: 32)) }])
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 16)).renderWithDiagnostics(template: "{{ h.x }}", hostObjects: [oversized]) }
    }

    @Test func cancellationTakesPrecedenceOverExplicitHostFailure() async throws {
        let gate = HostReleaseGate()
        let host = LiquidHostObject("host", properties: [LiquidHostProperty("bad") {
            await gate.suspend()
            throw LiquidHostFailure("late")
        }])
        let engine = LiquidEngine()
        let task = Task { try await engine.renderWithDiagnostics(template: "{{ host.bad }}", hostObjects: [host]) }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await engine.render(template: "{{ host.good }}", hostObjects: [LiquidHostObject("host", properties: [LiquidHostProperty("good") { "ok" }])]) == "ok")
    }

    @Test func opaqueHostObjectPreservesIdentityAndObjectBehavior() async throws {
        let engine = LiquidEngine()
        let hosts = [LiquidHostObject("d", opaqueDisplayName: "opaque"), LiquidHostObject("e", opaqueDisplayName: "opaque")]
        let source = "{{ d }}|[{{ d.size }}]|[{{ d.unknown }}]|[{{ d[0] }}]|{% if d %}T{% endif %}|{% if d == empty %}E{% else %}N{% endif %}|{% if d == blank %}B{% else %}N{% endif %}|{% if d == 'opaque' %}E{% else %}N{% endif %}|{% if 'opaque' == d %}E{% else %}N{% endif %}|{% if d == d %}E{% endif %}|{% if d == e %}E{% else %}N{% endif %}|{% assign x = d.to_liquid %}{% if d == x %}E{% endif %}|{{ d | size }}|{{ d | upcase }}|{{ d | plus: 1 }}|{{ 5 | plus: d }}|{% for item in d %}bad{% else %}none{% endfor %}"
        let expected = "opaque|[]|[]|[]|T|N|N|N|N|E|N|E|0|OPAQUE|1|5|none"
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await engine.render(template: source, hostObjects: hosts, syntaxMode: mode) == expected)
            #expect(try await engine.render(LiquidTemplate(source, syntaxMode: mode), hostObjects: hosts) == expected)
            #expect(try await engine.render(template: "{% render 'p' %}", hostObjects: hosts, templates: ["p": "{{ d }}"], syntaxMode: mode) == "opaque")
        }
        let collectionFilters = "{{ d | reverse | size }}|{{ d | sort | size }}|{{ d | compact | size }}|{{ d | uniq | size }}|{{ d | map: 'foo' | size }}|{{ d | where: 'foo' | size }}|{{ d | reject: 'foo' | size }}"
        let collectionOutput = try await engine.render(template: collectionFilters, hostObjects: hosts)
        #expect(collectionOutput == "1|1|1|1|1|0|1")
        let collectionIdentity = "{% assign r = d | reverse %}{% assign u = d | uniq %}{% assign m = d | map: 'to_liquid' %}{% if r[0] == d %}E{% endif %}|{% if u[0] == d %}E{% endif %}|{% if m[0] == d %}E{% endif %}|{% assign hidden = d | map: 'displayName' %}[{{ hidden[0] }}]"
        #expect(try await engine.render(template: collectionIdentity, hostObjects: hosts) == "E|E|E|[]")
        let rejected = "{{ d | reject: 'to_liquid' | size }}|{{ d | reject: 'to_liquid', d | size }}|{{ d | reject: 'to_liquid', e | size }}|{{ d | reverse | reject: 'foo' | size }}"
        #expect(try await engine.render(template: rejected, hostObjects: hosts) == "0|0|1|1")
        let distinct = "{% assign a = d | reverse %}{% assign b = e | reverse %}{% assign both = a | concat: b %}{% assign same = a | concat: a %}{{ both | uniq | size }}|{{ same | uniq | size }}|{{ both | where: 'to_liquid', d | size }}"
        #expect(try await engine.render(template: distinct, hostObjects: hosts) == "2|1|1")
        let mixedContext: LiquidObject = ["strings": ["foo", "bar"], "hashes": [["foo": true]]]
        let mixed = "{% assign a = d | reverse %}{% assign b = a | concat: strings %}{{ b | reject: 'foo' | size }}|{% assign c = strings | concat: a %}{{ c | reject: 'foo' | size }}|{% assign h = a | concat: hashes %}{{ h | reject: 'foo' | size }}|{{ h | reject: 'to_liquid', d | size }}"
        #expect(try await engine.render(template: mixed, context: mixedContext, hostObjects: hosts) == "2|2|1|1")
        let boxedMixed = hosts + [LiquidHostObject("boxed", array: [.boxedString("abc")])]
        let boxedSource = "{% assign a = d | reverse %}{% assign both = a | concat: boxed %}{{ both | reject: 'to_liquid' | size }}"
        #expect(try await engine.render(template: boxedSource, hostObjects: boxedMixed) == "0")
        let firstLast = "{% assign a = d | first %}{% assign b = d | last %}{% if a == nil %}N{% endif %}|{% if b == nil %}N{% endif %}"
        #expect(try await engine.render(template: firstLast, hostObjects: hosts) == "N|N")
        let empty = LiquidHostObject("d", opaqueDisplayName: "")
        #expect(try await engine.render(template: "{% if d %}T{% endif %}|{% if d == blank %}B{% else %}N{% endif %}|{% assign x = d | default: 'fallback' %}{% if x == d %}E{% endif %}", hostObjects: [empty]) == "T|N|E")
        #expect(try await engine.render(template: "{{ d | plus: 1 }}", hostObjects: [LiquidHostObject("d", opaqueDisplayName: "123")]) == "1")
        let custom = try LiquidEngine(filters: [LiquidFilter("opaque_text") { value, _, _ in
            if case .string(let text) = value { return .string(text) }; return "wrong"
        }])
        #expect(try await custom.render(template: "{{ d | opaque_text }}", hostObjects: hosts) == "opaque")
    }

    @Test func opaqueHostObjectAdmissionHonorsLimits() async throws {
        let host = LiquidHostObject("d", opaqueDisplayName: "opaque")
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(contextValues: 1)).render(template: "{{ d }}", hostObjects: [host]) }
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 5)).render(template: "{{ d }}", hostObjects: [host]) }
    }

    @Test func concurrentRendersKeepOpaqueObjectsInvocationScoped() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{{ d }}|{% assign x = d %}{% if x == d %}E{% endif %}")
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<24 {
                group.addTask { try await engine.render(template, hostObjects: [LiquidHostObject("d", opaqueDisplayName: String(index))]) }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(Set(results) == Set((0..<24).map { "\($0)|E" }))
    }

    @Test func typedNullPreservesLiquidNilBehaviorAcrossModes() async throws {
        let source = "[{{ d }}]|{% if d %}T{% else %}F{% endif %}|{% if d == empty %}E{% else %}N{% endif %}|{% if d == blank %}B{% else %}N{% endif %}|{% if d == nil %}equal{% endif %}|{{ d | default: 'fallback' }}|{{ d | plus: 1 }}|{% assign x = d %}[{{ x }}]"
        let context: LiquidObject = ["d": .null]
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let expected = "[]|F|N|B|equal|fallback|1|[]"
            #expect(try await engine.render(template: source, context: context, syntaxMode: mode) == expected)
            #expect(try await engine.render(LiquidTemplate(source, syntaxMode: mode), context: context) == expected)
            #expect(try await engine.render(template: "{% render 'p' %}", context: context, templates: ["p": "[{{ d }}]"], syntaxMode: mode) == "[]")
        }
    }

    @Test func nestedHostNodesPreserveAccessValuesAndAliases() async throws {
        let engine = LiquidEngine()
        let root = LiquidHostObject("d", node: makeIntegerNode(3))
        let source = "{{ d }}|{{ d.self.self }}|{{ d.next.next }}|{{ d.self.next.self }}|[{{ d.missing }}]|[{{ d.unknown }}]|[{{ d[0] }}]|{{ d | size }}|{{ d | plus: 1 }}|{{ 5 | plus: d }}"
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await engine.render(template: source, hostObjects: [root], syntaxMode: mode) == "3|3|5|4|[]|[]|[]|0|1|5")
            #expect(try await engine.render(LiquidTemplate(source, syntaxMode: mode), hostObjects: [root]) == "3|3|5|4|[]|[]|[]|0|1|5")
            let aliases = "{% assign x = d.self %}{{ x.next }}|{% assign y = d | default %}{{ y.next }}|{{ self.d.self.next }}|{% if d.self == d %}equal{% endif %}|[{{ d.plain.self }}]"
            #expect(try await engine.render(template: aliases, hostObjects: [root], syntaxMode: mode) == "4|4|4|equal|[]")
            #expect(try await engine.render(template: "{% render 'p' %}", hostObjects: [root], templates: ["p": "{{ d.self.next }}"], syntaxMode: mode) == "4")
        }
        let custom = try LiquidEngine(filters: [LiquidFilter("node_kind") { value, _, _ in
            if case .integer = value { return "integer" }; return "wrong"
        }])
        #expect(try await custom.render(template: "{{ d.self | node_kind }}", hostObjects: [root]) == "integer")
    }

    @Test func nestedHostNodeAdmissionAndDepthRemainBounded() async throws {
        let root = LiquidHostObject("d", node: makeIntegerNode(1))
        let source = "{% assign x = d %}{% for i in (1..limit) %}{% assign x = x.self %}{% endfor %}{{ x }}"
        let parsed = try LiquidTemplate(source)
        #expect(try await LiquidEngine(limits: .init(nestingDepth: 12)).render(parsed, context: ["limit": 6], hostObjects: [root]) == "1")
        #expect(try await LiquidEngine(limits: .init(nestingDepth: 4)).render(parsed, context: ["limit": 2], hostObjects: [root]) == "1")
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(nestingDepth: 4)).render(parsed, context: ["limit": 6], hostObjects: [root])
        }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(contextValues: 2)).render(template: "{{ d }}", hostObjects: [root])
        }
        let duplicate = LiquidHostNode(integerValue: 1, properties: [LiquidHostNodeProperty("x") { .missing }, LiquidHostNodeProperty("x") { .missing }])
        let parent = LiquidHostObject("d", node: LiquidHostNode(integerValue: 0, properties: [LiquidHostNodeProperty("child") { .node(duplicate) }]))
        await #expect(throws: LiquidError.self) { try await LiquidEngine().render(template: "{{ d.child }}", hostObjects: [parent]) }
        let badValue = LiquidHostObject("d", node: LiquidHostNode(integerValue: 0, properties: [LiquidHostNodeProperty("bad") { .value(.number(.infinity)) }]))
        await #expect(throws: LiquidError.self) { try await LiquidEngine().render(template: "{{ d.bad }}", hostObjects: [badValue]) }
    }

    @Test func cancellationDuringNestedHostAccessPreservesReuse() async throws {
        let gate = HostReleaseGate()
        let suspended = LiquidHostObject("d", node: LiquidHostNode(integerValue: 3, properties: [LiquidHostNodeProperty("next") {
            await gate.suspend()
            return .current
        }]))
        let engine = LiquidEngine()
        let task = Task { try await engine.render(template: "{{ d.next.next }}", hostObjects: [suspended]) }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await engine.render(template: "{{ d.self.next }}", hostObjects: [LiquidHostObject("d", node: makeIntegerNode(3))]) == "4")
    }

    @Test func concurrentRendersKeepHostNodesInvocationScoped() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{{ d.self.next }}")
        let outputs = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<24 {
                group.addTask {
                    let result = try await engine.render(template, hostObjects: [LiquidHostObject("d", node: makeIntegerNode(index))])
                    return Int(result) ?? -1
                }
            }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(outputs.sorted() == Array(1...24))
    }

    @Test func finiteHostSequencePreservesReferenceOperations() async throws {
        let engine = LiquidEngine()
        let host = LiquidHostObject("d", sequence: ["first", "second", "third"], displayName: "ExampleSequence")
        let source = "{{ d.size }}|{{ d.first }}|{{ d.last }}|[{{ d[0] }}]|[{{ d.unknown }}]|{{ d | size }}|{{ d | first }}|{{ d | last }}|{{ d | join: ',' }}|{{ d | reverse | join: ',' }}"
        let expected = "3|first|third|[]|[]|3|first|third|first,second,third|third,second,first"
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await engine.render(template: source, hostObjects: [host], syntaxMode: mode) == expected)
            #expect(try await engine.render(LiquidTemplate(source, syntaxMode: mode), hostObjects: [host]) == expected)
            let loops = "{% for x in d %}{{ forloop.index }}:{{ x }};{% endfor %}|{% for x in d limit: 1 offset: 1 %}{{ x }}{% endfor %}|{% for x in d reversed %}{{ x }};{% endfor %}"
            #expect(try await engine.render(template: loops, hostObjects: [host], syntaxMode: mode) == "1:first;2:second;3:third;|second|third;second;first;")
            let methods = "{{ d.count }}|{{ d.min }}|{{ d.max }}|{{ d.sort | join: ',' }}|{% if d.to_liquid == d %}same{% endif %}|[{{ d.length }}]"
            #expect(try await engine.render(template: methods, hostObjects: [host], syntaxMode: mode) == "3|first|third|first,second,third|same|[]")
            let row = "{% tablerow x in d cols: 2 %}{{ x }}{% endtablerow %}"
            #expect(try await engine.render(template: row, hostObjects: [host], syntaxMode: mode) == "<tr class=\"row1\">\n<td class=\"col1\">first</td><td class=\"col2\">second</td></tr>\n<tr class=\"row2\"><td class=\"col1\">third</td></tr>\n")
            let aliases = "{% assign x = d %}{{ x.size }}|{{ self.d.first }}|{% if x == d %}same{% else %}different{% endif %}|{% if d contains 'first' %}yes{% endif %}|{{ d }}"
            #expect(try await engine.render(template: aliases, hostObjects: [host], syntaxMode: mode) == "3|first|same|yes|ExampleSequence")
            #expect(try await engine.render(template: "{% render 'p' %}", hostObjects: [host], templates: ["p": "{{ d.last }}"], syntaxMode: mode) == "third")
        }
        let unordered = LiquidHostObject("d", sequence: ["z", "a", "m"])
        #expect(try await engine.render(template: "{{ d.min }}|{{ d.max }}|{{ d.sort | join: ',' }}", hostObjects: [unordered]) == "a|z|a,m,z")
        let incompatible = LiquidHostObject("d", sequence: ["a", 1])
        await #expect(throws: (any Error).self) { try await engine.render(template: "{{ d.sort }}", hostObjects: [incompatible]) }
        let empty = LiquidHostObject("d", sequence: [], displayName: "EmptySequence")
        let emptySource = "{% if d %}truthy{% endif %}|{% if d == empty %}empty{% else %}not empty{% endif %}|{{ d | default: 'fallback' }}|{{ d.size }}|[{{ d.first }}]|{% for x in d %}{{ x }}{% else %}none{% endfor %}"
        #expect(try await engine.render(template: emptySource, hostObjects: [empty]) == "truthy|not empty|EmptySequence|0|[]|none")
        let custom = try LiquidEngine(filters: [LiquidFilter("host_count") { value, _, _ in
            if case .array(let values) = value { return .integer(values.count) }; return "wrong"
        }])
        #expect(try await custom.render(template: "{{ d | host_count }}", hostObjects: [host]) == "3")
    }

    @Test func finiteHostSequenceHonorsIterationAndAdmissionLimits() async throws {
        let host = LiquidHostObject("d", sequence: ["a", "b", "c"])
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(loopIterations: 2)).render(template: "{% for x in d %}{{ x }}{% endfor %}", hostObjects: [host])
        }
        #expect(try await LiquidEngine(limits: .init(loopIterations: 1)).render(template: "{% for x in d limit: 1 %}{{ x }}{% endfor %}", hostObjects: [host]) == "a")
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(contextValues: 3)).render(template: "{{ d.size }}", hostObjects: [host])
        }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine().render(template: "{{ d.size }}", hostObjects: [LiquidHostObject("d", sequence: [.number(.infinity)])])
        }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(nestingDepth: 1)).render(template: "{{ d.size }}", hostObjects: [host])
        }
        let many = LiquidHostObject("d", sequence: Array(repeating: .integer(1), count: 100))
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(renderSteps: 10, contextValues: 200)).render(template: "static", hostObjects: [many])
        }
        let ordered = LiquidHostObject("d", sequence: (0..<40).reversed().map { .integer($0) })
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(renderSteps: 70, contextValues: 100)).render(template: "{{ d.sort | size }}", hostObjects: [ordered])
        }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 2)).render(template: "ok", hostObjects: [LiquidHostObject("d", sequence: [], displayName: "large")])
        }
    }

    @Test func cancellationDuringHostSequenceIterationPreservesReuse() async throws {
        let gate = HostReleaseGate()
        let filter = LiquidFilter("pause_sequence") { value, _, _ in
            await gate.suspend()
            return value
        }
        let engine = try LiquidEngine(filters: [filter])
        let host = LiquidHostObject("d", sequence: ["one", "two", "three"])
        let task = Task { try await engine.render(template: "{% for x in d %}{{ x | pause_sequence }}{% endfor %}", hostObjects: [host]) }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await engine.render(template: "{% for x in d %}{{ x }}{% endfor %}", hostObjects: [host]) == "onetwothree")
    }

    @Test func concurrentRendersKeepHostSequencesInvocationScoped() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{% for x in d %}{{ x }},{% endfor %}")
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<24 {
                group.addTask { try await engine.render(template, hostObjects: [LiquidHostObject("d", sequence: [.integer(index)])]) }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(Set(outputs) == Set((0..<24).map { "\($0)," }))
    }

    @Test func boxedStringPreservesObjectSensitiveBehavior() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (value, expected) in [("abc", "abc|T|N|N|abc|0|||[]|[]|empty|ABC"),
                                      ("", "|T|E|B||0|||[]|[]|empty|")] {
                let host = LiquidHostObject("d", stringValue: value)
                let source = "{{ d }}|{% if d %}T{% else %}F{% endif %}|{% if d == empty %}E{% else %}N{% endif %}|{% if d == blank %}B{% else %}N{% endif %}|{{ d | default: 'fallback' }}|{{ d | size }}|{{ d | first }}|{{ d | last }}|[{{ d.size }}]|[{{ d[0] }}]|{% for item in d %}{{ item }}{% else %}empty{% endfor %}|{{ d | upcase }}"
                #expect(try await engine.render(template: source, hostObjects: [host], syntaxMode: mode) == expected)
                #expect(try await engine.render(LiquidTemplate(source, syntaxMode: mode), hostObjects: [host]) == expected)
                let aliases = "{% assign x = d | default: 'fallback' %}[{{ x.size }}]|[{{ self.d.size }}]|{{ x }}"
                #expect(try await engine.render(template: aliases, hostObjects: [host], syntaxMode: mode) == "[]|[]|\(value)")
                let noFallback = "{% assign x = d | default %}[{{ x.size }}]|[{{ x }}]"
                #expect(try await engine.render(template: noFallback, hostObjects: [host], syntaxMode: mode) == "[]|[\(value)]")
                let extraOption = "{% assign x = d | default: 'fallback', 'extra' %}[{{ x.size }}]|[{{ x }}]"
                #expect(try await engine.render(template: extraOption, hostObjects: [host], syntaxMode: mode) == "[]|[\(value)]")
                #expect(try await engine.render(template: "{% render 'p' %}", hostObjects: [host], templates: ["p": "{{ d }}"], syntaxMode: mode) == value)
            }
            let nilHost = LiquidHostObject("d", stringValue: nil)
            let nilSource = "{% if d %}T{% else %}F{% endif %}|{% if d == empty %}E{% else %}N{% endif %}|{% if d == blank %}B{% else %}N{% endif %}|{{ d | default: 'fallback' }}|{{ d | size }}"
            #expect(try await engine.render(template: nilSource, hostObjects: [nilHost], syntaxMode: mode) == "F|N|B|fallback|0")
            let collectionFilters = "{{ d | compact | size }}|{{ d | reverse | size }}|{{ d | sort | size }}|{{ d | uniq | size }}|{{ d | map: 'value' | size }}|{{ d | where: 'value' | size }}|{{ d | reject: 'value' | size }}"
            #expect(try await engine.render(template: collectionFilters, hostObjects: [nilHost], syntaxMode: mode) == "1|1|1|1|1|0|1")
            let noFallback = "{% assign x = d | default %}[{{ x.size }}]|[{{ x }}]"
            #expect(try await engine.render(template: noFallback, hostObjects: [nilHost], syntaxMode: mode) == "[0]|[]")
            let preserveNil = "{% assign x = d | default: 'fallback', allow_false: true %}[{{ x.size }}]|[{{ x }}]"
            await #expect(throws: LiquidError.self) { try await engine.render(template: preserveNil, hostObjects: [nilHost], syntaxMode: mode) }
            for source in ["{{ d }}", "{{ d | upcase }}", "{{ d | append: 'x' }}", "{{ d | join: ',' }}", "{{ d | reverse }}", "{{ d | base64_decode }}"] {
                await #expect(throws: LiquidError.self) { try await engine.render(template: source, hostObjects: [nilHost], syntaxMode: mode) }
            }
        }
        #expect(try await engine.render(template: "{{ d | base64_decode }}", hostObjects: [LiquidHostObject("d", stringValue: "YWJj")]) == "abc")
        #expect(try await engine.render(template: "{{ d | base64_url_safe_decode }}", hostObjects: [LiquidHostObject("d", stringValue: "YQ")]) == "a")
        for (source, value) in [("{{ d | base64_decode }}", "abc"), ("{{ d | base64_url_safe_decode }}", "YR=="), ("{{ d | base64_url_safe_decode }}", "abc")] {
            await #expect(throws: (any Error).self) { try await engine.render(template: source, hostObjects: [LiquidHostObject("d", stringValue: value)]) }
        }
        let custom = try LiquidEngine(filters: [LiquidFilter("kind") { value, _, _ in
            switch value { case .string: return "string"; case .null: return "null"; default: return "wrong" }
        }])
        #expect(try await custom.render(template: "{{ d | kind }}", hostObjects: [LiquidHostObject("d", stringValue: "a")]) == "string")
        #expect(try await custom.render(template: "{{ d | kind }}", hostObjects: [LiquidHostObject("d", stringValue: nil)]) == "null")
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(contextValues: 1)).render(template: "{{ d }}", hostObjects: [LiquidHostObject("d", stringValue: "x")])
        }
    }

    @Test func boxedStringsInExplicitArraysPreserveFirstIdentity() async throws {
        let engine = LiquidEngine()
        let firstDrop = LiquidHostObject("a", array: [.boxedString("foo"), .value("foo"), .boxedString("bar")])
        let firstPlain = LiquidHostObject("a", array: [.value("foo"), .boxedString("foo"), .boxedString("bar")])
        let source = "{{ a | uniq }}|{% assign u = a | uniq %}{{ u | size }}|[{{ u[0].size }}]"
        #expect(try await engine.render(template: source, hostObjects: [firstDrop]) == "foobar|2|[]")
        #expect(try await engine.render(template: source, hostObjects: [firstPlain]) == "foobar|2|[3]")
        let unicode = LiquidHostObject("a", array: [.value("é"), .boxedString("e\u{301}"), .boxedString("é")])
        #expect(try await engine.render(template: "{{ a | uniq | size }}", hostObjects: [unicode]) == "2")
        let boxedEquality = LiquidHostObject("b", array: [.boxedString("foo")])
        let plainEquality = LiquidHostObject("p", array: [.value("foo")])
        let equality = "{% if b == p %}T{% else %}F{% endif %}|{% if p == b %}T{% else %}F{% endif %}"
        #expect(try await engine.render(template: equality, hostObjects: [boxedEquality, plainEquality]) == "T|F")
        let emptyEquality = LiquidHostObject("b", array: [.boxedString("")])
        let nilEquality = LiquidHostObject("p", array: [.value(.null)])
        #expect(try await engine.render(template: equality, hostObjects: [emptyEquality, nilEquality]) == "T|F")
        let nilBoxA = LiquidHostObject("b", array: [.boxedString(nil)])
        let nilBoxB = LiquidHostObject("p", array: [.boxedString(nil)])
        #expect(try await engine.render(template: equality, hostObjects: [nilBoxA, nilBoxB]) == "F|F")
        #expect(try await engine.render(template: "{% if b == b %}T{% else %}F{% endif %}", hostObjects: [nilBoxA]) == "T")
        let property = LiquidHostObject("a", array: [.boxedString("abc"), .boxedString("def"), .value("abc")])
        #expect(try await engine.render(template: "{% assign u = a | uniq: 'a' %}{{ u | size }}|[{{ u[0].size }}]", hostObjects: [property]) == "2|[]")
        let objects = LiquidHostObject("a", array: [.boxedString("abc"), .boxedString(nil)])
        #expect(try await engine.render(template: "{{ a | compact | size }}|{{ a | map: 'value' | size }}|{{ a | where: 'a' | size }}|{{ a | reject: 'a' | size }}", hostObjects: [objects]) == "2|2|0|2")
        #expect(try await engine.render(template: "[{{ a | find: 'a' }}]|[{{ a | find_index: 'a' }}]|{{ a | has: 'a' }}", hostObjects: [objects]) == "[]|[]|false")
        #expect(try await engine.render(template: "{% assign x = d | map: 'to_liquid' %}[{{ x[0].size }}]", hostObjects: [LiquidHostObject("d", stringValue: "abc")]) == "[]")
        let nilFirst = LiquidHostObject("a", array: [.boxedString(nil), .value(.null)])
        let plainNilFirst = LiquidHostObject("a", array: [.value(.null), .boxedString(nil)])
        #expect(try await engine.render(template: "{{ a | uniq: 'a' | size }}", hostObjects: [nilFirst]) == "0")
        await #expect(throws: LiquidError.self) { try await engine.render(template: "{{ a | uniq }}", hostObjects: [nilFirst]) }
        #expect(try await engine.render(template: "{{ a | uniq }}", hostObjects: [plainNilFirst]) == "")
        await #expect(throws: LiquidError.self) { try await engine.render(template: "{{ a | join: ',' }}", hostObjects: [nilFirst]) }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(contextValues: 2)).render(template: "{{ a }}", hostObjects: [firstDrop])
        }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 2)).render(template: "{{ a }}", hostObjects: [LiquidHostObject("a", array: [.boxedString("abc")])])
        }
        await #expect(throws: LiquidError.self) {
            try await engine.render(template: "{{ a }}", hostObjects: [LiquidHostObject("a", array: [.value(.number(.infinity))])])
        }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(nestingDepth: 1)).render(template: "{{ a }}", hostObjects: [LiquidHostObject("a", array: [.boxedString("x")])])
        }
    }

    @Test func ordinaryHostArraysRetainTheirExistingStepBudget() async throws {
        let values = Array(repeating: LiquidValue.integer(1), count: 200)
        let context: LiquidObject = ["a": .array(values), "b": .array(values)]
        let engine = LiquidEngine(limits: .init(renderSteps: 40, contextValues: 500))
        let host = LiquidHostObject("h", properties: [])
        #expect(try await engine.render(template: "{% if a == b %}equal{% endif %}", context: context, hostObjects: [host]) == "equal")
    }

    @Test func concurrentRendersKeepBoxedStringsInvocationScoped() async throws {
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{{ d | upcase }}")
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<32 {
                group.addTask { try await engine.render(template, hostObjects: [LiquidHostObject("d", stringValue: "s\(index)")]) }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(Set(outputs) == Set((0..<32).map { "S\($0)" }))
    }

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
