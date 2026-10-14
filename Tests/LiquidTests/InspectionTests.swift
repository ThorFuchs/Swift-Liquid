// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

private struct InspectionCase: Sendable, CustomTestStringConvertible {
    let name: String
    let source: String
    let variables: [String]
    let filters: [String]
    let partials: [String]
    let dynamic: Bool
    var testDescription: String { name }
}

private let inspectionCases: [InspectionCase] = [
    .init(name: "raw, comments and whitespace control", source: "{% raw %}{{ fake | wrong }}{% include 'hidden' %}{% endraw %}{% comment %}{{ secret }}{% endcomment %}{% # ignored %}{% doc %}{{ documented }}{% enddoc %}{{- visible | escape -}}", variables: ["visible"], filters: ["escape"], partials: [], dynamic: false),
    .init(name: "multiline liquid, assignments and capture", source: "{% liquid\nassign local = input | strip\ncapture captured\necho local | upcase\nendcapture\necho captured\n%}", variables: ["captured", "input", "local"], filters: ["strip", "upcase"], partials: [], dynamic: false),
    .init(name: "nested loops, range, limits and bracket access", source: "{% for item in items limit: maximum offset: start %}{% for index in (lower..upper) %}{{ item[keys[index]].title }}{{ forloop.index }}{% endfor %}{% else %}{{ fallback }}{% endfor %}", variables: ["fallback", "forloop", "index", "item", "items", "keys", "lower", "maximum", "start", "upper"], filters: [], partials: [], dynamic: false),
    .init(name: "conditions, case and unreachable paths", source: "{% if ready and user.active %}{{ a }}{% elsif pending %}{{ b }}{% else %}{{ c }}{% endif %}{% unless hidden %}{{ d }}{% else %}{{ e }}{% endunless %}{% case choice %}{% when expected %}{{ f }}{% else %}{{ g }}{% endcase %}{% if false %}{{ unreachable }}{% endif %}", variables: ["a", "b", "c", "choice", "d", "e", "expected", "f", "g", "hidden", "pending", "ready", "unreachable", "user"], filters: [], partials: [], dynamic: false),
    .init(name: "filter values, labels and literal property names", source: "{{ user['first.name'] | host: prefix, separator: config[key], suffix: ending | escape }}{{ array[0] | host }}", variables: ["array", "config", "ending", "key", "prefix", "user"], filters: ["escape", "host"], partials: [], dynamic: false),
    .init(name: "literal and dynamic include sharing spelling", source: "{% include 'card', title: title %}{% include card with product as local %}{% render 'folder/card.liquid' for products as item %}{% render 'card' %}", variables: ["card", "product", "products", "title"], filters: [], partials: ["card", "folder/card.liquid"], dynamic: true),
    .init(name: "cycle, tablerow, ifchanged and counters", source: "{% cycle group: first, second %}{% tablerow row in rows cols: 2 limit: 4 offset: 1 %}{% ifchanged %}{{ row.title }}{% endifchanged %}{% endtablerow %}{% increment counter %}{% decrement other %}{% assign target = source %}{% capture output %}text{% endcapture %}", variables: ["first", "group", "row", "rows", "second", "source"], filters: [], partials: [], dynamic: false),
    .init(name: "empty template", source: "", variables: [], filters: [], partials: [], dynamic: false)
]

@Suite("Read-only template inspection")
struct InspectionTests {
    @Test("AST inspection cases", arguments: inspectionCases)
    fileprivate func astReferences(_ fixture: InspectionCase) throws {
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let engine = LiquidEngine()
            let parsed = try LiquidTemplate(fixture.source, syntaxMode: mode)
            let result = try engine.inspect(parsed)
            #expect(try result == engine.inspect(template: fixture.source, syntaxMode: mode))
            #expect(result.variableRoots == fixture.variables)
            #expect(result.filterNames == fixture.filters)
            #expect(result.literalPartialNames == fixture.partials)
            #expect(result.hasDynamicPartials == fixture.dynamic)
        }
    }

    @Test func exactScalarSpellingAndOrdering() throws {
        let composed = "caf\u{e9}"
        let decomposed = "cafe\u{301}"
        let source = "{{ \(composed) | \(composed) }}{{ \(decomposed) | \(decomposed) }}{{ \(composed) }}{% include '\(composed)' %}{% include '\(decomposed)' %}"
        let result = try LiquidEngine().inspect(template: source)
        for names in [result.variableRoots, result.filterNames, result.literalPartialNames] {
            #expect(names.count == 2)
            #expect(names[0].utf8.elementsEqual(decomposed.utf8))
            #expect(names[1].utf8.elementsEqual(composed.utf8))
        }
        let first = try LiquidEngine().inspect(template: "{{ \(composed) }}")
        let second = try LiquidEngine().inspect(template: "{{ \(decomposed) }}")
        #expect(first != second)
    }

    @Test func inspectionDoesNotEvaluateCallbacksOrLoadPartials() throws {
        let engine = try LiquidEngine(filters: [LiquidFilter("explode") { _, _, _ in
            Issue.record("Inspection invoked a host callback")
            throw LiquidFilterFailure("Must remain unevaluated")
        }], strictFilters: true)
        let source = "{{ input | explode | unknown }}{% include missing %}{% render 'absent' %}"
        let result = try engine.inspect(template: source)
        #expect(result.filterNames == ["explode", "unknown"])
        #expect(result.literalPartialNames == ["absent"])
        #expect(result.hasDynamicPartials)
        #expect(try result == LiquidEngine().inspect(template: source))
    }

    @Test func parsingModesAndFailuresMatchTemplateParsing() throws {
        let source = "{% if name | ignored: hidden %}{{ shown }}{% endif %}"
        #expect(try LiquidEngine().inspect(template: source, syntaxMode: .lax).variableRoots == ["name", "shown"])
        for mode in [LiquidSyntaxMode.strict, .strict2] {
            #expect(throws: LiquidError.self) { try LiquidEngine().inspect(template: source, syntaxMode: mode) }
        }
        for source in ["{% if %}", "{% render dynamic %}", "{% unknown %}"] {
            #expect(throws: LiquidError.self) { try LiquidEngine().inspect(template: source) }
        }
    }

    @Test func sourceAndReusedTemplatesRespectCapacities() throws {
        let source = "{% if ready %}{{ object[key] }}{% endif %}"
        let parsed = try LiquidTemplate(source)
        for limits in [LiquidLimits(sourceBytes: source.utf8.count - 1), LiquidLimits(nestingDepth: 2)] {
            let engine = LiquidEngine(limits: limits)
            #expect(throws: LiquidError.self) { try engine.inspect(template: source) }
            #expect(throws: LiquidError.self) { try engine.inspect(parsed) }
        }
        #expect(throws: LiquidError.self) { try LiquidEngine(limits: .init(renderSteps: 0)).inspect(parsed) }
        let tinyRenderBudget = LiquidEngine(limits: .init(outputBytes: 1, loopIterations: 1, renderSteps: 1, contextValues: 1))
        #expect(try tinyRenderBudget.inspect(parsed).variableRoots == ["key", "object", "ready"])
    }

    @Test func cancellationAtEntry() async throws {
        let parsed = try LiquidTemplate("{{ name }}")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try LiquidEngine().inspect(parsed) }
            #expect(throws: CancellationError.self) { try LiquidEngine().inspect(template: "{{ name }}") }
        }
        await task.value
    }

    @Test func concurrentRendersAndInspectionShareOnlyImmutableTemplates() async throws {
        let engine = LiquidEngine()
        let parsed = try LiquidTemplate("{{ name | upcase }}{% render 'card' %}")
        let partial = try LiquidTemplate("{{ name }}")
        let expected = try engine.inspect(parsed)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    #expect(try engine.inspect(parsed) == expected)
                    let output = try await engine.render(parsed, context: ["name": .string("n\(index)")], templates: ["card": partial])
                    #expect(output == "N\(index)")
                    #expect(try engine.inspect(parsed) == expected)
                }
            }
            try await group.waitForAll()
        }
    }
}
