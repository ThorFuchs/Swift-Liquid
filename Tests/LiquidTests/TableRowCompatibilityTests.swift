// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify table row attributes")
struct TableRowCompatibilityTests {
    @Test func attributeScanningMatchesShopifyModes() async throws {
        let engine = LiquidEngine()
        let body = "{{ x }}{% endtablerow %}"
        let five = "<tr class=\"row1\">\n" + (1...5).map { "<td class=\"col\($0)\">\($0)</td>" }.joined() + "</tr>\n"
        for mode in [LiquidSyntaxMode.lax, .strict] {
            let unknown = "{% tablerow x in (1..5) unknown: 10 %}" + body
            #expect(try await engine.render(template: unknown, syntaxMode: mode) == five)
            let incomplete = "{% tablerow x in (1..5) limit: foo=>bar %}" + body
            #expect(try await engine.render(template: incomplete, syntaxMode: mode) == "<tr class=\"row1\">\n</tr>\n")
        }
        let separated = "{% tablerow x in (1..10) cols: 2, limit: 4, offset: 1 %}" + body
        let rows = "<tr class=\"row1\">\n<td class=\"col1\">2</td><td class=\"col2\">3</td></tr>\n<tr class=\"row2\"><td class=\"col1\">4</td><td class=\"col2\">5</td></tr>\n"
        #expect(try await engine.render(template: separated, syntaxMode: .strict2) == rows)
        let range = "{% tablerow x in (1..3) range: (1..10) %}" + body
        #expect(try await engine.render(template: range, syntaxMode: .strict2) == "<tr class=\"row1\">\n<td class=\"col1\">1</td><td class=\"col2\">2</td><td class=\"col3\">3</td></tr>\n")
        #expect(throws: LiquidError.self) { try LiquidTemplate("{% tablerow x in (1..3) unknown: 1 %}" + body, syntaxMode: .strict2) }
    }

    @Test func emptyAndCoercedAttributesMatchRuby() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let empty = "<tr class=\"row1\">\n</tr>\n"
            for source in ["{% tablerow x in items %}{{ x }}{% endtablerow %}",
                           "{% tablerow x in (1..3) limit: nil %}{{ x }}{% endtablerow %}",
                           "{% tablerow x in (1..3) limit: count %}{{ x }}{% endtablerow %}"] {
                let context: LiquidObject = ["items": [], "count": "bad"]
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: context) == empty)
                let recovered = try await engine.renderWithDiagnostics(parsed, context: context)
                #expect(recovered.output == empty && recovered.diagnostics.isEmpty)
            }
            let source = "{% tablerow x in (1..3) cols: sizes.n %}{{ x }}={{ tablerowloop.col_last }};{% endtablerow %}"
            #expect(try engine.inspect(template: source, syntaxMode: mode).variableRoots.contains("sizes"))
            let expected = "<tr class=\"row1\">\n<td class=\"col1\">1=false;</td><td class=\"col2\">2=true;</td></tr>\n<tr class=\"row2\"><td class=\"col1\">3=false;</td></tr>\n"
            #expect(try await engine.render(template: source, context: ["sizes": ["n": 2]], syntaxMode: mode) == expected)
            let zero = "{% tablerow x in (1..3) cols: c %}{{ tablerowloop.col_last }}{% endtablerow %}"
            let zeroOutput = "<tr class=\"row1\">\n<td class=\"col1\">false</td><td class=\"col2\">false</td><td class=\"col3\">false</td></tr>\n"
            #expect(try await engine.render(template: zero, context: ["c": "bad"], syntaxMode: mode) == zeroOutput)
            let stringSource = "{% tablerow x in word offset: 5 limit: 0 %}{{ x }}{% endtablerow %}"
            #expect(try await engine.render(template: stringSource, context: ["word": "abc"], syntaxMode: mode) == "<tr class=\"row1\">\n<td class=\"col1\">abc</td></tr>\n")
            #expect(try await engine.render(template: "{% tablerow x in missing %}x{% endtablerow %}", syntaxMode: mode) == "")
        }
    }

    @Test func invalidAttributesQuotaAndCancellationRemainErrors() async throws {
        let source = "{% tablerow x in (1..3) limit: flag %}{{ x }}{% endtablerow %}"
        let recovered = try await LiquidEngine().renderWithDiagnostics(template: source, context: ["flag": true])
        #expect(recovered.diagnostics.map(\.message) == ["invalid integer"])
        await #expect(throws: LiquidError.self) { try await LiquidEngine().render(template: source, context: ["flag": true]) }
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 2)).render(template: "{% tablerow x in items %}{% endtablerow %}", context: ["items": []]) }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiquidEngine().render(template: source, context: ["flag": 1])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
