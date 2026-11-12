// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Filter argument boundaries")
struct FilterArgumentBoundaryTests {
    @Test func emptyAndTrailingArgumentsFollowSyntaxMode() async throws {
        let engine = LiquidEngine()
        let examples = [
            ("{{ 'test' | upcase: }}", "TEST"),
            ("{{ 'hello' | append: 'world', }}", "helloworld"),
            ("{{ 'test' | append: 'x', | upcase: }}", "TESTX"),
            ("{% assign x = 'a' | append: 'b', %}{{ x }}", "ab")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict2] {
            for (source, expected) in examples {
                #expect(try await engine.render(template: source, syntaxMode: mode) == expected)
                let result = try await engine.renderWithDiagnostics(template: source, syntaxMode: mode)
                #expect(result.output == expected && result.diagnostics.isEmpty)
            }
        }
        for (source, _) in examples {
            #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: .strict) }
        }
        #expect(throws: LiquidError.self) { try LiquidTemplate("{{ x | append: , }}", syntaxMode: .strict2) }
        #expect(throws: LiquidError.self) { try LiquidTemplate("{{ x | append: 'a',, }}", syntaxMode: .strict2) }
    }
}
