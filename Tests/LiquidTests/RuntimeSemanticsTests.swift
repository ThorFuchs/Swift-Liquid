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

}
