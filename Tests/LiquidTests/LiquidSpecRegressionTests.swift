// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Independent liquid-spec regressions", .timeLimit(.minutes(1)))
struct LiquidSpecRegressionTests {
    // Provenance: Shopify/liquid-spec 84bf25e, basics/filter-edge-cases.yml:282,
    // truncate_zero_length. Additional cases protect the general rule and quotas.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func truncateRetainsEndingAtNonpositiveLength(mode: LiquidSyntaxMode) async throws {
        let source = "{{ text | truncate: length, ending }}"
        let parsed = try LiquidTemplate(source, syntaxMode: mode)
        let engine = LiquidEngine()
        let cases: [(String, Int, String, String)] = [
            ("hello", 0, "...", "..."), ("", 0, "...", ""),
            ("", -1, "...", "..."), ("hello", Int.min, "...", "..."),
            ("é", 1, "...", "é"), ("e\u{301}", 1, "...", "..."),
            ("hello", 0, "✨", "✨"), ("hello", 0, "", "")
        ]
        for (text, length, ending, expected) in cases {
            let context: LiquidObject = ["text": .string(text), "length": .integer(length), "ending": .string(ending)]
            #expect(try await engine.render(template: source, context: context, syntaxMode: mode).utf8.elementsEqual(expected.utf8))
            #expect(try await engine.render(parsed, context: context).utf8.elementsEqual(expected.utf8))
            let recovered = try await engine.renderWithDiagnostics(parsed, context: context)
            #expect(recovered.output.utf8.elementsEqual(expected.utf8) && recovered.diagnostics.isEmpty)
        }
        let error = await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 2)).renderWithDiagnostics(parsed,
                context: ["text": "hello", "length": 0, "ending": "..."])
        }
        if case .limitExceeded("outputBytes")? = error { } else { Issue.record("Truncation must retain output admission") }
    }
}
