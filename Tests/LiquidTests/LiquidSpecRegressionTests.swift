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
    // Provenance: liquid-spec 84bf25e, parser_errors/assign.yml:314 and
    // liquid_ruby/bare_bracket_access.yml; Ruby parser.rb#expression.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func bareBracketRequiresReceiverOnlyInStrict2(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let source = "é\n{{ ['x'] }}"
        if mode == .strict2 {
            let error = #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
            if case .syntax(let message, let line, let column)? = error {
                #expect(message.contains("Bare bracket access is not allowed"))
                #expect(line == 2 && column == 4)
            } else { Issue.record("Bare brackets must fail during parsing") }
            await #expect(throws: LiquidError.self) {
                try await engine.renderWithDiagnostics(template: source, context: ["x": "ok"], syntaxMode: mode)
            }
            #expect(throws: LiquidError.self) {
                try LiquidTemplate("{% assign value = 'a' | append: ['x'] %}", syntaxMode: mode)
            }
        } else {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            #expect(try await engine.render(parsed, context: ["x": "ok"]) == "é\nok")
            #expect(try await engine.render(template: source, context: ["x": "ok"], syntaxMode: mode) == "é\nok")
        }
        let property = try LiquidTemplate("{{ obj['x'] }}|{{ '[x]' }}", syntaxMode: mode)
        #expect(try await engine.render(property, context: ["obj": ["x": "ok"]]) == "ok|[x]")
        // Receiver syntax remains accepted; root `self` resolution is a separate
        // known evaluator difference, not silently bundled into this repair.
        _ = try LiquidTemplate("{{ self['x'] }}", syntaxMode: mode)
    }

}
