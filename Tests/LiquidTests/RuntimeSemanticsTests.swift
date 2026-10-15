// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

private struct RuntimeRuleControl: Sendable {
    let name: String
    let source: String
    let context: LiquidObject
    let partials: [String: String]
    let expected: String
}

private func checkRuntimeControls(_ controls: [RuntimeRuleControl], mode: LiquidSyntaxMode) async throws {
    let engine = LiquidEngine()
    for control in controls {
        let parsed = try LiquidTemplate(control.source, syntaxMode: mode)
        let partials = try control.partials.mapValues { try LiquidTemplate($0, syntaxMode: mode) }
        let sourceOutput = try await engine.render(template: control.source, context: control.context,
                                                   templates: control.partials, syntaxMode: mode)
        let parsedOutput = try await engine.render(parsed, context: control.context, templates: partials)
        #expect(sourceOutput.utf8.elementsEqual(control.expected.utf8), "\(control.name)")
        #expect(parsedOutput.utf8.elementsEqual(control.expected.utf8), "\(control.name)")
        for result in [try await engine.renderWithDiagnostics(template: control.source, context: control.context,
                                                               templates: control.partials, syntaxMode: mode),
                       try await engine.renderWithDiagnostics(parsed, context: control.context, templates: partials)] {
            #expect(result.output.utf8.elementsEqual(control.expected.utf8), "\(control.name)")
            #expect(result.diagnostics.isEmpty, "\(control.name)")
        }
    }
}

private let runtimeControlsA: [RuntimeRuleControl] = [
    .init(name: "case-list-None", source: "{% case value %}{% when 1, \"string\", null %}M{% endcase %}", context: LiquidObject([.init("value", .null)]), partials: [:], expected: "M"),
    .init(name: "case-list-'other'", source: "{% case value %}{% when 1, \"string\", null %}M{% endcase %}", context: LiquidObject([.init("value", .string("other"))]), partials: [:], expected: ""),
    .init(name: "case-list-1", source: "{% case value %}{% when 1, \"string\", null %}M{% endcase %}", context: LiquidObject([.init("value", .integer(1))]), partials: [:], expected: "M"),
    .init(name: "case-list-'string'", source: "{% case value %}{% when 1, \"string\", null %}M{% endcase %}", context: LiquidObject([.init("value", .string("string"))]), partials: [:], expected: "M"),
    .init(name: "case-list-False", source: "{% case value %}{% when 1, \"string\", null %}M{% endcase %}", context: LiquidObject([.init("value", .bool(false))]), partials: [:], expected: ""),
    .init(name: "null-only-negative", source: "{% case value %}{% when null %}N{% else %}E{% endcase %}", context: LiquidObject([.init("value", .string("other"))]), partials: [:], expected: "E"),
    .init(name: "null-only-positive", source: "{% case value %}{% when null %}N{% else %}E{% endcase %}", context: LiquidObject([.init("value", .null)]), partials: [:], expected: "N"),
    .init(name: "missing-matches-null", source: "{% case missing %}{% when null %}N{% else %}E{% endcase %}", context: LiquidObject([]), partials: [:], expected: "N"),
    .init(name: "duplicate-matching-whens", source: "{% case value %}{% when null %}A{% when null %}B{% else %}E{% endcase %}", context: LiquidObject([.init("value", .null)]), partials: [:], expected: "AB"),
    .init(name: "duplicate-values-one-clause", source: "{% case value %}{% when null, null %}A{% else %}E{% endcase %}", context: LiquidObject([.init("value", .null)]), partials: [:], expected: "AA"),
    .init(name: "else-before-when", source: "{% case value %}{% else %}E{% when null %}N{% else %}Z{% endcase %}", context: LiquidObject([.init("value", .null)]), partials: [:], expected: "EN"),
    .init(name: "repeated-else", source: "{% case value %}{% else %}A{% else %}B{% endcase %}", context: LiquidObject([.init("value", .string("other"))]), partials: [:], expected: "AB"),
    .init(name: "else-after-match", source: "{% case value %}{% when 1 %}M{% else %}E{% when null %}N{% else %}Z{% endcase %}", context: LiquidObject([.init("value", .integer(1))]), partials: [:], expected: "M"),
    .init(name: "nested-case", source: "{% case value %}{% when null %}{% case other %}{% when null %}N{% else %}O{% endcase %}{% else %}E{% endcase %}", context: LiquidObject([.init("value", .null), .init("other", .integer(7))]), partials: [:], expected: "O"),
    .init(name: "unreachable-filter", source: "{% case value %}{% when null %}{{ \"x\" | divided_by: 0 }}{% else %}E{% endcase %}", context: LiquidObject([.init("value", .string("other"))]), partials: [:], expected: "E"),
    .init(name: "blank-case", source: "{% case value %}{% when null %} \n {% else %} \t {% endcase %}", context: LiquidObject([.init("value", .null)]), partials: [:], expected: ""),
    .init(name: "liquid-case", source: "{% liquid\ncase value\nwhen null\necho \"N\"\nelse\necho \"E\"\nendcase\n%}", context: LiquidObject([.init("value", .string("other"))]), partials: [:], expected: "E"),
    .init(name: "case-partials", source: "{% case value %}{% when null %}{% render \"n\" %}{% else %}{% include \"e\" %}{% endcase %}", context: LiquidObject([.init("value", .string("other"))]), partials: ["n": "N", "e": "E"], expected: "E")
]

private let runtimeControlsB: [RuntimeRuleControl] = [
    .init(name: "map", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .object(LiquidObject([.init("a", .integer(1)), .init("b", .integer(2))]))), .init("key", .string("size"))]), partials: [:], expected: "2|||||2"),
    .init(name: "map-size", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .object(LiquidObject([.init("size", .integer(9)), .init("a", .integer(1))]))), .init("key", .string("size"))]), partials: [:], expected: "9||9||9|2"),
    .init(name: "map-length", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .object(LiquidObject([.init("length", .integer(7)), .init("a", .integer(1))]))), .init("key", .string("size"))]), partials: [:], expected: "2|7||7||2"),
    .init(name: "map-both", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .object(LiquidObject([.init("size", .integer(9)), .init("length", .integer(7))]))), .init("key", .string("size"))]), partials: [:], expected: "9|7|9|7|9|2"),
    .init(name: "map-null-size", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .object(LiquidObject([.init("size", .null), .init("length", .integer(7))]))), .init("key", .string("size"))]), partials: [:], expected: "|7||7||2"),
    .init(name: "empty-map", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .object(LiquidObject([]))), .init("key", .string("size"))]), partials: [:], expected: "0|||||0"),
    .init(name: "string", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .string("é👩‍💻")), .init("key", .string("size"))]), partials: [:], expected: "5|||||5"),
    .init(name: "array", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .array([.integer(1), .integer(2), .integer(3)])), .init("key", .string("size"))]), partials: [:], expected: "3|||||3"),
    .init(name: "empty-string", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .string("")), .init("key", .string("size"))]), partials: [:], expected: "0|||||0"),
    .init(name: "null", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .null), .init("key", .string("size"))]), partials: [:], expected: "|||||0"),
    .init(name: "integer", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .integer(42)), .init("key", .string("size"))]), partials: [:], expected: "8|||||8"),
    .init(name: "double", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .number(1.5)), .init("key", .string("size"))]), partials: [:], expected: "|||||0"),
    .init(name: "boolean", source: "{{ obj.size }}|{{ obj.length }}|{{ obj[\"size\"] }}|{{ obj[\"length\"] }}|{{ obj[key] }}|{{ obj | size }}", context: LiquidObject([.init("obj", .bool(true)), .init("key", .string("size"))]), partials: [:], expected: "|||||0"),
    .init(name: "nested-and-dynamic", source: "{{ root.child.size }}|{{ root[key].size }}|{{ root.child | size }}|{{ root.child[\"size\"] }}", context: LiquidObject([.init("root", .object(LiquidObject([.init("child", .object(LiquidObject([.init("a", .integer(1)), .init("b", .integer(2))])))]))), .init("key", .string("child"))]), partials: [:], expected: "2|2|2|"),
    .init(name: "nested-unicode", source: "{{ root.child.size }}|{{ root[key].size }}|{{ root.child | size }}", context: LiquidObject([.init("root", .object(LiquidObject([.init("child", .string("é👩‍💻"))]))), .init("key", .string("child"))]), partials: [:], expected: "5|5|5"),
    .init(name: "forloop-length", source: "{% for x in xs %}{{ forloop.length }}:{{ forloop.size }};{% endfor %}", context: LiquidObject([.init("xs", .array([.integer(1), .integer(2)]))]), partials: [:], expected: "2:;2:;"),
    .init(name: "size-condition", source: "{% if obj.size > 0 %}Y{% endif %}", context: LiquidObject([.init("obj", .object(LiquidObject([.init("a", .integer(1)), .init("b", .integer(2))])))]), partials: [:], expected: "Y"),
    .init(name: "scalar-keys", source: "{{ obj.size }}|{{ obj[\"é\"] }}|{{ obj[\"é\"] }}|{{ obj.length }}", context: LiquidObject([.init("obj", .object(LiquidObject([.init("é", .integer(1)), .init("é", .integer(2)), .init("length", .integer(7))])))]), partials: [:], expected: "3|1|2|7"),
    .init(name: "review-object-property-size", source: "{{ obj.size }}|{{ obj | size }}|{% if obj.size > 0 %}Y{% endif %}", context: LiquidObject([.init("obj", .object(LiquidObject([.init("a", .integer(1)), .init("b", .integer(2))])))]), partials: [:], expected: "2|2|Y")
]

private let runtimeControlsC: [RuntimeRuleControl] = [
    // Maintainer-approved correction of InspectionTests.swift:114; pinned Ruby in all modes/policies.
    .init(name: "authored-host-name", source: "{{ name | upcase }}{% render 'card' %}", context: ["name": "n7"], partials: ["card": "{{ name }}"], expected: "N7n7"),
    .init(name: "review-partial-render-global", source: "{% assign local = \"L\" %}{% render \"p\" %}", context: LiquidObject([.init("title", .string("T"))]), partials: ["p": "{{ title }}|{{ local }}"], expected: "T|"),
    .init(name: "review-partial-render-explicit", source: "{% render \"p\", title: title %}", context: LiquidObject([.init("title", .string("T"))]), partials: ["p": "{{ title }}"], expected: "T"),
    .init(name: "root-shadow", source: "{% assign title = \"L\" %}{% render \"p\" %}|{{ title }}", context: LiquidObject([.init("title", .string("T"))]), partials: ["p": "{{ title }}"], expected: "T|L"),
    .init(name: "include-shares", source: "{% assign title = \"L\" %}{% include \"p\" %}|{{ title }}", context: LiquidObject([.init("title", .string("T"))]), partials: ["p": "{{ title }}{% assign title = \"P\" %}"], expected: "L|P"),
    .init(name: "loop-locals-hidden", source: "{% for item in xs %}{% render \"p\" %}{% endfor %}", context: LiquidObject([.init("xs", .array([.integer(1), .integer(2)])), .init("title", .string("T"))]), partials: ["p": "{{ title }}|{{ item }}|{{ forloop.index }};"], expected: "T||;T||;"),
    .init(name: "named-overrides-host", source: "{% render \"p\", title: \"A\" %}|{{ title }}", context: LiquidObject([.init("title", .string("T"))]), partials: ["p": "{{ title }}"], expected: "A|T"),
    .init(name: "nested-render", source: "{% render \"a\", title: \"A\" %}|{{ title }}", context: LiquidObject([.init("title", .string("T"))]), partials: ["a": "{{ title }}>{% assign local = \"L\" %}{% render \"b\" %}>{{ title }}", "b": "{{ title }}|{{ local }}"], expected: "A>T|>A|T"),
    .init(name: "render-for", source: "{% render \"p\" for xs as item %}", context: LiquidObject([.init("xs", .array([.integer(1), .integer(2)])), .init("title", .string("T"))]), partials: ["p": "{{ title }}:{{ item }}:{{ forloop.index }};{% assign title = \"L\" %}"], expected: "T:1:1;T:2:2;"),
    .init(name: "null-binding", source: "{% render \"p\", title: null %}|{{ title }}", context: LiquidObject([.init("title", .string("T"))]), partials: ["p": "[{{ title }}]{{ missing }}"], expected: "[]|T"),
    .init(name: "null-host", source: "{% assign title = \"L\" %}{% render \"p\" %}|{{ title }}", context: LiquidObject([.init("title", .null)]), partials: ["p": "[{{ title }}]"], expected: "[]|L"),
    .init(name: "missing-host", source: "{% assign title = \"L\" %}{% render \"p\" %}|{{ title }}", context: LiquidObject([]), partials: ["p": "[{{ title }}]"], expected: "[]|L"),
    .init(name: "partial-assign-restoration", source: "{% render \"p\" %}|{{ title }}", context: LiquidObject([.init("title", .string("T"))]), partials: ["p": "{{ title }}{% assign title = \"P\" %}{{ title }}"], expected: "TP|T"),
    .init(name: "render-counter-isolation", source: "{% increment n %}{% render \"p\" %}{% increment n %}", context: LiquidObject([.init("title", .string("T"))]), partials: ["p": "{{ title }}{% increment n %}"], expected: "0T01"),
    .init(name: "render-cycle-isolation", source: "{% cycle x,\"2\" %}{% render \"p\" %}{% cycle x,\"2\" %}", context: LiquidObject([.init("x", .string("1"))]), partials: ["p": "{% cycle x,\"2\" %}"], expected: "111"),
    .init(name: "explicit-input-forloop", source: "{% for x in xs %}{% render \"p\" %}{% endfor %}", context: LiquidObject([.init("xs", .array([.integer(1)])), .init("forloop", .object(LiquidObject([.init("index", .integer(99))])))]), partials: ["p": "{{ forloop.index }}"], expected: "99")
]

@Suite("Pinned runtime semantic regressions", .timeLimit(.minutes(1)))
struct RuntimeSemanticsTests {
    // liquid-spec 84bf25e, liquid_ruby/specs.yml:6701/:6728;
    // Ruby 4e39ae4 tags/case.rb#render_to_output_buffer. Supplementary controls.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func caseBranchesKeepNullSeparateFromElse(mode: LiquidSyntaxMode) async throws {
        try await checkRuntimeControls(runtimeControlsA, mode: mode)
        let source = "{% case value %}{% when null %}{{ 1 | divided_by: 0 }}{% else %}E{% endcase %}"
        let engine = LiquidEngine()
        let parsed = try LiquidTemplate(source, syntaxMode: mode)
        await #expect(throws: LiquidError.self) { try await engine.render(parsed, context: ["value": nil]) }
        let result = try await engine.renderWithDiagnostics(parsed, context: ["value": nil])
        #expect(result.diagnostics.count == 1 && result.diagnostics[0].line == 1)
    }

    @Test func caseInspectionAndOperationalBoundsRemainExplicit() async throws {
        let source = "{% case value %}{% when null %}{% include 'n' %}{% else %}{% render 'e' %}{% endcase %}"
        let engine = LiquidEngine()
        let parsed = try LiquidTemplate(source)
        let inspection = try engine.inspect(parsed)
        #expect(inspection.variableRoots == ["value"])
        #expect(inspection.literalPartialNames == ["e", "n"])
        let graph = try engine.inspectDependencies(parsed, templates: ["n": LiquidTemplate("N"), "e": LiquidTemplate("E")])
        #expect(graph.nodes.count == 3)
        let limited = LiquidEngine(limits: .init(outputBytes: 1))
        await #expect(throws: LiquidError.self) {
            try await limited.renderWithDiagnostics(template: "{% case x %}{% when null %}NN{% else %}EE{% endcase %}")
        }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(renderSteps: 1)).render(parsed, templates: ["n": LiquidTemplate("N")])
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(parsed)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try await engine.render(parsed, context: ["value": "other"], templates: ["e": LiquidTemplate("E")]) == "E")
    }
    // liquid-spec 84bf25e, partials/partials.yml:1022; pinned Ruby
    // variable_lookup.rb#evaluate distinguishes command flags from bracket keys.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func sizeLookupPreservesCommandsKeysAndScalars(mode: LiquidSyntaxMode) async throws {
        try await checkRuntimeControls(runtimeControlsB, mode: mode)
        let source = "{{ obj.size }}!"
        let context: LiquidObject = ["obj": ["a": 1, "b": 2]]
        let parsed = try LiquidTemplate(source, syntaxMode: mode)
        let tight = LiquidEngine(limits: .init(outputBytes: 1))
        await #expect(throws: LiquidError.self) { try await tight.renderWithDiagnostics(parsed, context: context) }
        #expect(try await LiquidEngine(limits: .init(outputBytes: 2)).render(parsed, context: context) == "2!")
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func concurrentRendersKeepCaseAndSizeImmutable(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let source = "{% case choice %}{% when null %}{{ obj.size }}|{{ obj['size'] }}{% else %}E{% endcase %}"
        let parsed = try LiquidTemplate(source, syntaxMode: mode)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask { () async throws -> Void in
                    let object = LiquidObject((0..<index).map { .init(String($0), .integer($0)) })
                    let choice: LiquidValue = index.isMultiple(of: 2) ? .null : false
                    let context: LiquidObject = ["choice": choice, "obj": .object(object)]
                    let expected = index.isMultiple(of: 2) ? "\(index)|" : "E"
                    #expect(try await engine.render(template: source, context: context, syntaxMode: mode) == expected)
                    #expect(try await engine.render(parsed, context: context) == expected)
                    let recovered = try await engine.renderWithDiagnostics(parsed, context: context)
                    #expect(recovered.output == expected && recovered.diagnostics.isEmpty)
                    #expect(try engine.inspect(parsed).variableRoots == ["choice", "obj"])
                }
            }
            try await group.waitForAll()
        }
    }

    // liquid-spec 84bf25e, partials/partials.yml:129; pinned Ruby
    // context.rb#new_isolated_subcontext preserves static_environments.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func isolatedRenderKeepsOriginalInputsAndHidesCallerLocals(mode: LiquidSyntaxMode) async throws {
        try await checkRuntimeControls(runtimeControlsC, mode: mode)
        let root = try LiquidTemplate("{% render 'p' %}{% render 'p' %}", syntaxMode: mode)
        let partials = try ["p": LiquidTemplate("{{ title }}", syntaxMode: mode)]
        let context: LiquidObject = ["title": "T"]
        let admittedOnce = LiquidEngine(limits: .init(contextValues: 1))
        let measured = try await admittedOnce.renderWithMetrics(root, context: context, templates: partials)
        #expect(measured.output == "TT" && measured.metrics.admittedValues == 1)
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 1)).renderWithDiagnostics(root, context: context, templates: partials)
        }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(renderSteps: 1)).renderWithDiagnostics(root, context: context, templates: partials)
        }
        await #expect(throws: LiquidError.self) {
            try await admittedOnce.renderWithDiagnostics(root, context: ["title": "T", "extra": "E"], templates: partials)
        }
        let recursive = try LiquidTemplate("{% render 'p' %}", syntaxMode: mode)
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(nestingDepth: 4)).renderWithDiagnostics(recursive, context: context, templates: ["p": recursive])
        }
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine().render(root, context: context)
        }
        let missing = try await LiquidEngine().renderWithDiagnostics(root, context: context)
        #expect(missing.diagnostics.count == 2)
        let errorRoot = try LiquidTemplate("A{% render 'p' %}Z|{{ title }}", syntaxMode: mode)
        let errorPartial = try LiquidTemplate("{{ title }}\n{{ 1 | divided_by: 0 }}", syntaxMode: mode)
        let engine = LiquidEngine()
        await #expect(throws: LiquidError.self) { try await engine.render(errorRoot, context: context, templates: ["p": errorPartial]) }
        let recovered = try await engine.renderWithDiagnostics(errorRoot, context: context, templates: ["p": errorPartial])
        #expect(recovered.output.hasPrefix("AT\n") && recovered.output.hasSuffix("Z|T"))
        #expect(recovered.diagnostics.count == 1 && recovered.diagnostics[0].line == 2)
        #expect(recovered.diagnostics[0].templateName == "p")
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func concurrentRendersKeepRuntimeRulesInvocationOwned(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let root = try LiquidTemplate("{% assign title = 'local' %}{% case value %}{% when null %}{% render 'p' %}{% else %}BAD{% endcase %}", syntaxMode: mode)
        let partials = try ["p": LiquidTemplate("{{ title }}:{{ obj.size }}", syntaxMode: mode)]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask { () async throws -> Void in
                    let title = String(index)
                    let context: LiquidObject = ["title": .string(title), "obj": ["a": 1, "b": 2], "value": nil]
                    let expected = title + ":2"
                    #expect(try await engine.render(root, context: context, templates: partials) == expected)
                    #expect(try await engine.renderWithDiagnostics(root, context: context, templates: partials).output == expected)
                    #expect(try await engine.renderWithMetrics(root, context: context, templates: partials).output == expected)
                    #expect(try await engine.renderWithDiagnosticsAndMetrics(root, context: context, templates: partials).output == expected)
                }
            }
            try await group.waitForAll()
        }
    }

    @Test(arguments: [false, true])
    func cancellationInsideIsolatedRenderKeepsSiblingHealthy(recovering: Bool) async throws {
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for parsedInput in [false, true] {
                let gate = TestSuspensionGate()
                let engine = try LiquidEngine(filters: [LiquidFilter("r3_pause") { value, _, _ in
                    await gate.enter()
                    return value
                }])
                let source = "{% assign title = 'local' %}{% render 'p' %}"
                let partial = "{{ title | r3_pause }}"
                let root = try LiquidTemplate(source, syntaxMode: mode)
                let parsedPartials = try ["p": LiquidTemplate(partial, syntaxMode: mode)]
                let worker = Task {
                    if parsedInput {
                        if recovering { return try await engine.renderWithDiagnostics(root, context: ["title": "T"], templates: parsedPartials).output }
                        return try await engine.render(root, context: ["title": "T"], templates: parsedPartials)
                    }
                    if recovering { return try await engine.renderWithDiagnostics(template: source, context: ["title": "T"], templates: ["p": partial], syntaxMode: mode).output }
                    return try await engine.render(template: source, context: ["title": "T"], templates: ["p": partial], syntaxMode: mode)
                }
                defer { worker.cancel() }
                try await gate.waitForEntry()
                #expect(try await engine.render(template: "{% render 'q' %}", context: ["title": "S"], templates: ["q": "{{ title }}"]) == "S")
                worker.cancel()
                _ = try await gate.release()
                await #expect(throws: CancellationError.self) { try await worker.value }
                #expect(try await engine.render(root, context: ["title": "U"], templates: parsedPartials) == "U")
            }
        }
    }

}
