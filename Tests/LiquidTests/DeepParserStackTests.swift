// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Deep parser stack safety")
struct DeepParserStackTests {
    private func nested(_ depth: Int) -> String {
        String(repeating: "{% if true %}", count: depth) + "x" + String(repeating: "{% endif %}", count: depth)
    }

    @Test func admittedDefaultDepth() throws {
        _ = try LiquidTemplate(nested(60))
    }

    @Test func admittedExplicitDepth() throws {
        _ = try LiquidTemplate(nested(100), limits: LiquidLimits(nestingDepth: 128))
    }

    @Test func overLimitReportsCapacity() throws {
        let error = #expect(throws: LiquidError.self) { try LiquidTemplate(nested(200)) }
        guard case .limitExceeded("nestingDepth")? = error else { Issue.record("Expected nesting depth error"); return }
    }

    @Test func admittedNestedFor() throws {
        let source = String(repeating: "{% for x in (1..1) %}", count: 100) + "x" + String(repeating: "{% endfor %}", count: 100)
        _ = try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128))
    }

    @Test func admittedNestedUnless() throws {
        let source = String(repeating: "{% unless false %}", count: 100) + "x" + String(repeating: "{% endunless %}", count: 100)
        _ = try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128))
    }

    @Test func admittedMixedBlocks() throws {
        let source = String(repeating: "{% if true %}{% for x in (1..1) %}", count: 50) + "x" + String(repeating: "{% endfor %}{% endif %}", count: 50)
        _ = try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128))
    }

    @Test func admittedNestedCapture() throws {
        let source = String(repeating: "{% capture x %}", count: 100) + "x" + String(repeating: "{% endcapture %}", count: 100)
        _ = try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128))
    }

    @Test func admittedNestedTableRow() throws {
        let source = String(repeating: "{% tablerow x in (1..1) %}", count: 100) + "x" + String(repeating: "{% endtablerow %}", count: 100)
        _ = try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128))
    }

    @Test func admittedNestedCase() throws {
        let source = String(repeating: "{% case x %}{% when 1 %}", count: 100) + "x" + String(repeating: "{% endcase %}", count: 100)
        _ = try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128))
    }

    @Test func admittedNestedIfChanged() throws {
        let source = String(repeating: "{% ifchanged %}", count: 100) + "x" + String(repeating: "{% endifchanged %}", count: 100)
        _ = try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128))
    }

    @Test func admittedNestedExpression() throws {
        let source = "{{ " + String(repeating: "x[", count: 100) + "'key'" + String(repeating: "]", count: 100) + " }}"
        _ = try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128))
    }

    @Test func admittedNestedLiquidTag() throws {
        let source = "{% liquid\n" + String(repeating: "if true\n", count: 100) + "echo 'x'\n" + String(repeating: "endif\n", count: 100) + "%}"
        _ = try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128))
        let tooDeep = "{% liquid\n" + String(repeating: "if true\n", count: 200) + String(repeating: "endif\n", count: 200) + "%}"
        let error = #expect(throws: LiquidError.self) { try LiquidTemplate(tooDeep) }
        guard case .limitExceeded("nestingDepth")? = error else { Issue.record("Expected nesting depth error"); return }
    }

    @Test func unsupportedNestedCallsRejectSafely() throws {
        let source = "{{ " + String(repeating: "f(", count: 100) + "x" + String(repeating: ")", count: 100) + " }}"
        #expect(throws: LiquidError.self) { try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 128)) }
    }

    @Test func nestedAccessPreservesLookupAndLimits() async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["x": ["selected": ["value": "ok"]], "key": "selected"]
        #expect(try await engine.render(template: "{{ x[key].value }}", context: context, syntaxMode: .strict2) == "ok")
        let source = "{{ " + String(repeating: "x[", count: 12) + "'key'" + String(repeating: "]", count: 12) + " }}"
        let error = #expect(throws: LiquidError.self) { try LiquidTemplate(source, limits: LiquidLimits(nestingDepth: 8)) }
        guard case .limitExceeded("nestingDepth")? = error else { Issue.record("Expected nesting depth error"); return }
    }

    @Test func nearMaximumAndBranches() async throws {
        _ = try LiquidTemplate(nested(126), limits: LiquidLimits(nestingDepth: 128))
        let source = "{% for n in (1..2) %}{% case n %}{% when 1 %}{% if true %}A{% else %}bad{% endif %}{% else %}{% unless false %}B{% endunless %}{% endcase %}{% endfor %}"
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            #expect(try await LiquidEngine().render(template: source, syntaxMode: mode) == "AB")
            let liquid = "{% liquid\nfor n in (1..2)\ncase n\nwhen 1\necho 'A'\nelse\nunless false\necho 'B'\nendunless\nendcase\nendfor\n%}"
            #expect(try await LiquidEngine().render(template: liquid, syntaxMode: mode) == "AB")
        }
        let task = Task { () throws -> LiquidTemplate in
            withUnsafeCurrentTask { $0?.cancel() }
            return try LiquidTemplate(nested(100), limits: LiquidLimits(nestingDepth: 128))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
