// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

private struct RangePropertyControl: Sendable {
    let name: String
    let source: String
    let contextJSON: String
    let partials: [String: String]
    let expected: String
}

// Supplementary controls: liquid-spec 84bf25e variable_type_filters.yml:342,510;
// Liquid 4e39ae4 variable_lookup.rb command flags and standardfilters.rb.
private let rangePropertyControls: [RangePropertyControl] = [
    .init(name: "ascending", source: "{% assign r = (1..5) %}{{ r.first }}|{{ r.last }}|{{ r.size }};{{ r | first }}|{{ r | last }}|{{ r | size }}", contextJSON: "{}", partials: [:], expected: "1|5|5;1|5|5"),
    .init(name: "singleton", source: "{% assign r = (3..3) %}{{ r.first }}|{{ r.last }}|{{ r.size }};{{ r | first }}|{{ r | last }}|{{ r | size }}", contextJSON: "{}", partials: [:], expected: "3|3|1;3|3|1"),
    .init(name: "negative", source: "{% assign r = (-3..-1) %}{{ r.first }}|{{ r.last }}|{{ r.size }};{{ r | first }}|{{ r | last }}|{{ r | size }}", contextJSON: "{}", partials: [:], expected: "-3|-1|3;-3|-1|3"),
    .init(name: "cross-zero", source: "{% assign r = (-2..2) %}{{ r.first }}|{{ r.last }}|{{ r.size }};{{ r | first }}|{{ r | last }}|{{ r | size }}", contextJSON: "{}", partials: [:], expected: "-2|2|5;-2|2|5"),
    .init(name: "descending", source: "{% assign r = (5..1) %}{{ r.first }}|{{ r.last }}|{{ r.size }};{{ r | first }}|{{ r | last }}|{{ r | size }}", contextJSON: "{}", partials: [:], expected: "5|1|0;5|1|0"),
    .init(name: "brackets-are-keys", source: "{% assign r = (1..5) %}{{ r[\"first\"] | default: \"N\" }}|{{ r[\"last\"] | default: \"N\" }}|{{ r[\"size\"] | default: \"N\" }}|{{ r[k] | default: \"N\" }}", contextJSON: "{\"k\":\"first\"}", partials: [:], expected: "N|N|N|N"),
    .init(name: "array-stored-ranges", source: "{% assign r = (2..5) %}{% assign ranges = r | reverse | reverse %}{{ ranges.first }}|{{ ranges.last }}|{{ ranges.size }}", contextJSON: "{}", partials: [:], expected: "2|5|4"),
    .init(name: "indexed-bound-host-object", source: "{% assign r = (obj.lo..obj.hi) %}{{ r.first }}|{{ r.last }}|{{ r.size }}", contextJSON: "{\"obj\":{\"lo\":-3,\"hi\":4}}", partials: [:], expected: "-3|4|8"),
    .init(name: "mutation", source: "{% assign r = (1..3) %}{{ r.first }}|{{ r.last }}|{{ r.size }};{% assign r = (5..6) %}{{ r.first }}|{{ r.last }}|{{ r.size }}", contextJSON: "{}", partials: [:], expected: "1|3|3;5|6|2"),
    .init(name: "explicit-object-key-priority", source: "{{ obj.first }}|{{ obj.last }}|{{ obj.size }}|{{ obj[\"first\"] }}|{{ obj[\"last\"] }}|{{ obj[\"size\"] }}", contextJSON: "{\"obj\":{\"first\":null,\"last\":false,\"size\":0}}", partials: [:], expected: "|false|0||false|0"),
    .init(name: "unrelated-values", source: "{{ a.first }}|{{ a.last }}|{{ a.size }};{{ s.first }}|{{ s.last }}|{{ s.size }};{{ missing.first }}|{{ missing.last }}|{{ missing.size }}", contextJSON: "{\"a\":[1,3],\"s\":\"é🌍\"}", partials: [:], expected: "1|3|2;e|🌍|3;||"),
    .init(name: "include", source: "{% assign r = (-1..2) %}{% include \"p\" %}", contextJSON: "{}", partials: ["p": "{{ r.first }}|{{ r.last }}|{{ r.size }}"], expected: "-1|2|4"),
    .init(name: "render-binding", source: "{% assign r = (2..4) %}{% render \"p\", r: r %}", contextJSON: "{}", partials: ["p": "{{ r.first }}|{{ r.last }}|{{ r.size }}"], expected: "2|4|3"),
    .init(name: "loop-invariant", source: "{% assign r = (2..4) %}{% for n in r %}{{ n }}:{{ r.first }},{{ r.last }},{{ r.size }},{{ forloop.first }},{{ forloop.last }},{{ forloop.length }};{% endfor %}", contextJSON: "{}", partials: [:], expected: "2:2,4,3,true,false,3;3:2,4,3,false,false,3;4:2,4,3,false,true,3;"),
    .init(name: "descending-iteration", source: "{% assign r = (5..1) %}{% for n in r %}X{% else %}E{% endfor %}|{{ r | join: \",\" }}|{{ r }}|{% if r == empty %}empty{% endif %}", contextJSON: "{}", partials: [:], expected: "E||5..1|"),
    .init(name: "range-no-index-no-length", source: "{% assign r = (1..3) %}{{ r[0] | default: \"N\" }}|{{ r.length | default: \"N\" }}|{{ r[\"length\"] | default: \"N\" }}", contextJSON: "{}", partials: [:], expected: "N|N|N"),
    .init(name: "properties-in-expression", source: "{% assign r = (-1..3) %}{% if r.first < 0 and r.size == 5 %}Y{% endif %}{% case r.last %}{% when 3 %}Z{% endcase %}", contextJSON: "{}", partials: [:], expected: "YZ"),
    .init(name: "range-through-callback-free-alias", source: "{% assign r = (2..4) %}{% assign alias = r %}{{ alias.first }}|{{ alias.last }}|{{ alias.size }}", contextJSON: "{}", partials: [:], expected: "2|4|3"),
    .init(name: "nested-property-chain", source: "{% assign r = (1..5) %}{{ r.first.size }}|{{ r.last.size }}|{{ r.size.size }}", contextJSON: "{}", partials: [:], expected: "8|8|8"),
    .init(name: "dynamic-bracket-chain", source: "{% assign r = (1..5) %}{{ r[k].first | default: \"N\" }}|{{ r[k].last | default: \"N\" }}|{{ r[k].size | default: \"N\" }}", contextJSON: "{\"k\":\"first\"}", partials: [:], expected: "N|N|N")
]

private let rangePropertySource = "{% assign r = (lower..upper) %}{{ r.first }}|{{ r.last }}|{{ r.size }}"

@Suite("Range property commands", .timeLimit(.minutes(1)))
struct RangePropertyTests {
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func rangePropertiesMatchPinnedRubyAcrossPolicies(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        for control in rangePropertyControls {
            guard case .object(let context) = try LiquidValue(json: control.contextJSON) else {
                Issue.record("Expected an object context for \(control.name)")
                return
            }
            let parsed = try LiquidTemplate(control.source, syntaxMode: mode)
            let partials = try control.partials.mapValues { try LiquidTemplate($0, syntaxMode: mode) }
            let outputs = [
                try await engine.render(template: control.source, context: context, templates: control.partials, syntaxMode: mode),
                try await engine.render(parsed, context: context, templates: partials),
                try await engine.renderWithMetrics(template: control.source, context: context, templates: control.partials, syntaxMode: mode).output,
                try await engine.renderWithMetrics(parsed, context: context, templates: partials).output
            ]
            for output in outputs { #expect(output.utf8.elementsEqual(control.expected.utf8), "\(control.name)") }
            let recovered = [
                try await engine.renderWithDiagnostics(template: control.source, context: context, templates: control.partials, syntaxMode: mode),
                try await engine.renderWithDiagnostics(parsed, context: context, templates: partials)
            ]
            for result in recovered {
                #expect(result.output.utf8.elementsEqual(control.expected.utf8), "\(control.name)")
                #expect(result.diagnostics.isEmpty, "\(control.name)")
            }
            let measured = [
                try await engine.renderWithDiagnosticsAndMetrics(template: control.source, context: context, templates: control.partials, syntaxMode: mode),
                try await engine.renderWithDiagnosticsAndMetrics(parsed, context: context, templates: partials)
            ]
            for result in measured {
                #expect(result.output.utf8.elementsEqual(control.expected.utf8), "\(control.name)")
                #expect(result.diagnostics.isEmpty, "\(control.name)")
            }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func rangeCommandsPreserveRaisingAndRecoveredErrors(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let source = "{% assign r = (1..3) %}{{ r.first }}|{{ r.last }}|{{ r.size }};{{ 1 | divided_by: 0 }}Z"
        let parsed = try LiquidTemplate(source, syntaxMode: mode)
        await #expect(throws: LiquidError.self) { try await engine.render(template: source, syntaxMode: mode) }
        await #expect(throws: LiquidError.self) { try await engine.render(parsed) }
        await #expect(throws: LiquidError.self) { try await engine.renderWithMetrics(parsed) }
        let recovered = try await engine.renderWithDiagnostics(parsed)
        #expect(recovered.output.hasPrefix("1|3|3;") && recovered.output.hasSuffix("Z"))
        #expect(recovered.diagnostics.count == 1 && recovered.diagnostics[0].line == 1)
        let measured = try await engine.renderWithDiagnosticsAndMetrics(template: source, syntaxMode: mode)
        #expect(measured.output == recovered.output && measured.diagnostics == recovered.diagnostics)
        let root = try LiquidTemplate("{% render 'p' %}", syntaxMode: mode)
        let partial = try await engine.renderWithDiagnostics(root, templates: ["p": parsed])
        #expect(partial.output == "1|3|3;Liquid error (p line 1): \(recovered.diagnostics[0].message)Z")
        #expect(partial.diagnostics.count == 1)
        #expect(partial.diagnostics[0].templateName == "p")
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func rangePropertiesRetainFiniteAdmissionAndWork(mode: LiquidSyntaxMode) async throws {
        let parsed = try LiquidTemplate(rangePropertySource, syntaxMode: mode)
        let bounded = LiquidEngine(limits: .init(loopIterations: 3))
        #expect(try await bounded.render(parsed, context: ["lower": 1, "upper": 3]) == "1|3|3")
        await #expect(throws: LiquidError.self) { try await bounded.render(parsed, context: ["lower": 1, "upper": 4]) }
        // Descending ranges retain endpoints, but have no values to enumerate.
        let descending = try LiquidTemplate("{% assign r = (5..1) %}{{ r.first }}|{{ r.last }}|{{ r.size }};{% for n in r %}X{% else %}E{% endfor %}", syntaxMode: mode)
        #expect(try await LiquidEngine(limits: .init(loopIterations: 1)).render(descending) == "5|1|0;E")
        let result = try await LiquidEngine().renderWithMetrics(parsed, context: ["lower": 1, "upper": 3])
        #expect(result.metrics.loopIterations == 0)
        let noExtraCommand = try LiquidTemplate("{% assign r = (1..3) %}{{ r.count | default: 'N' }}|{{ r['count'] | default: 'N' }}|{{ r[key] | default: 'N' }}", syntaxMode: mode)
        #expect(try await LiquidEngine().render(noExtraCommand, context: ["key": "count"]) == "N|N|N")
        #expect(try await LiquidEngine(limits: .init(renderSteps: result.metrics.renderSteps)).render(parsed, context: ["lower": 1, "upper": 3]) == result.output)
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(renderSteps: result.metrics.renderSteps - 1)).renderWithDiagnostics(parsed, context: ["lower": 1, "upper": 3])
        }
        #expect(try await LiquidEngine(limits: .init(outputBytes: 5)).render(parsed, context: ["lower": 1, "upper": 3]) == "1|3|3")
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 4)).renderWithDiagnosticsAndMetrics(parsed, context: ["lower": 1, "upper": 3])
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func concurrentRendersKeepRangeCommandsImmutable(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let parsed = try LiquidTemplate(rangePropertySource, syntaxMode: mode)
        let inspection = try engine.inspect(parsed)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<24 {
                group.addTask { () async throws -> Void in
                    let lower = index - 12
                    let upper = index % 2 == 0 ? lower + 3 : lower - 1
                    let expected = "\(lower)|\(upper)|\(index % 2 == 0 ? 4 : 0)"
                    let context: LiquidObject = ["lower": .integer(lower), "upper": .integer(upper)]
                    #expect(try await engine.render(parsed, context: context) == expected)
                    #expect(try await engine.renderWithDiagnostics(parsed, context: context).output == expected)
                    #expect(try await engine.renderWithMetrics(parsed, context: context).output == expected)
                    #expect(try await engine.renderWithDiagnosticsAndMetrics(parsed, context: context).output == expected)
                    #expect(try engine.inspect(parsed) == inspection)
                }
            }
            try await group.waitForAll()
        }
        #expect(try engine.inspect(parsed) == inspection)
    }

    @Test(arguments: [false, true])
    func cancellationBeforeRangeCommandsPreservesSiblingReuse(recovering: Bool) async throws {
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for parsedInput in [false, true] {
                let gate = TestSuspensionGate()
                let engine = try LiquidEngine(filters: [LiquidFilter("range_pause") { value, _, _ in
                    await gate.enter()
                    return value
                }])
                let source = "{% assign r = (1..3) %}{{ '' | range_pause }}{{ r.first }}|{{ r.last }}|{{ r.size }}"
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                let worker = Task {
                    if parsedInput {
                        if recovering { return try await engine.renderWithDiagnostics(parsed).output }
                        return try await engine.render(parsed)
                    }
                    if recovering { return try await engine.renderWithDiagnostics(template: source, syntaxMode: mode).output }
                    return try await engine.render(template: source, syntaxMode: mode)
                }
                defer { worker.cancel() }
                try await gate.waitForEntry()
                #expect(try await engine.render(template: rangePropertySource, context: ["lower": 5, "upper": 1], syntaxMode: mode) == "5|1|0")
                worker.cancel()
                _ = try await gate.release()
                await #expect(throws: CancellationError.self) { try await worker.value }
                #expect(try await engine.render(parsed) == "1|3|3")
            }
        }
    }
}
