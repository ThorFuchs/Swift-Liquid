// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Quoted markup security boundary")
struct QuotedMarkupSecurityTests {
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func previouslyQuotedMarkupDoesNotInvokeHostCapabilities(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let cases: [(String, String)] = [
            (#"{{ "}}{% include 'probe' %}{{ value }}" }}"#, #"}}{% include 'probe' %}{{ value }}"#),
            (#"{{ nil | default: "}}{% include 'probe' %}" }}"#, #"}}{% include 'probe' %}"#),
            (#"{% echo "%}{{ value }}" %}"#, #"%}{{ value }}"#)
        ]
        for (source, expected) in cases {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            let output = try await engine.render(parsed, context: ["value": "HOST_VALUE"], partialSources: ["probe": "HOST_PARTIAL_EXECUTED"])
            #expect(output == expected)
            let inspection = try engine.inspect(parsed)
            #expect(inspection.literalPartialNames.isEmpty && inspection.variableRoots.isEmpty)
        }
        for source in [#"{{ 'a'b"}}{% include 'probe' %}" }}"#,
                       #"{{ 'a'b'}}{{ value | upcase }}"#] {
            #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
        }
    }
}
