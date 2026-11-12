// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Standard filter boundary behavior")
struct StandardFilterBoundaryTests {
    @Test func splitAritySortAndHTMLMatchReference() async throws {
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let missing = try await engine.renderWithDiagnostics(template: "{{ 'a-b' | split }}", syntaxMode: mode)
            #expect(missing.output.contains("wrong number of arguments (given 1, expected 2)"))
            let mixed = try await engine.renderWithDiagnostics(template: "{{ values | sort | join: ',' }}", context: ["values": [1, "a", true]], syntaxMode: mode)
            #expect(mixed.output.contains("cannot sort values of incompatible types"))
            #expect(try await engine.render(template: "{{ values | sort | join: ',' }}", context: ["values": [2, 1.5, 1]], syntaxMode: mode) == "1,1.5,2")
            #expect(try await engine.render(template: "{{ input | strip_html }}", context: ["input": "<<<script </script>script>foo;</script>"], syntaxMode: mode) == "foo;")
            #expect(try await engine.render(template: "{{ input | strip_html }}", context: ["input": "<SCRIPT>x</SCRIPT><>\n<b>y</b>"], syntaxMode: mode) == "x\ny")
        }
    }
}
