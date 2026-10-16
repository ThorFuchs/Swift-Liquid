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

    // Provenance: liquid-spec 84bf25e, parser_errors/adversarial_boundaries.yml:52;
    // pinned Ruby tags/for.rb#strict_parse and #lax_parse.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func forModifiersPrecedeNamedAttributes(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["xs": [1, 2, 3]]
        for suffix in ["reversed limit: 2", "reversed limit: 2, offset: 0"] {
            let source = "{% for x in xs \(suffix) %}{{ x }}{% endfor %}"
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            #expect(try await engine.render(parsed, context: context) == "21")
            #expect(try await engine.render(template: source, context: context, syntaxMode: mode) == "21")
        }
        for (suffix, laxOutput) in [("limit: 2 reversed", "12"), (", reversed", "123"),
                                    ("reversed reversed", "321"), ("limit: 2,", "12"), (",", "123")] {
            let source = "{% for x in xs \(suffix) %}{{ x }}{% endfor %}"
            if mode == .lax {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: context) == laxOutput)
                let recovered = try await engine.renderWithDiagnostics(template: source, context: context, syntaxMode: mode)
                #expect(recovered.output == laxOutput && recovered.diagnostics.isEmpty)
            } else {
                let error = #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
                if case .syntax(let message, let line, _)? = error {
                    #expect(message.contains("Invalid attribute in for loop")); #expect(line == 1)
                } else { Issue.record("Invalid attribute order must fail while parsing") }
                await #expect(throws: LiquidError.self) {
                    try await engine.renderWithDiagnostics(template: source, context: context, syntaxMode: mode)
                }
            }
        }
    }

    // Provenance: liquid-spec 84bf25e, basics/cycle.yml:55 and :66;
    // pinned Ruby tags/cycle.rb#maybe_dup_lookup. No mutable AST state.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func unnamedVariableCyclesUseParsedSiteIdentity(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["x": "1", "obj": ["x": "1"]]
        for (source, expected) in [
            ("{% cycle x, '2' %}{% cycle x, '2' %}", "11"),
            ("{% for i in (1..3) %}{% cycle x, '2' %}{% cycle x, '2' %}{% endfor %}", "112211"),
            ("{% cycle obj.x, '2' %}{% cycle obj.x, '2' %}", "11"),
            ("{% cycle 'a', 'b' %}{% cycle 'a', 'b' %}{% cycle 'a', 'b' %}", "aba"),
            ("{% cycle 'named': x, '2' %}{% cycle 'named': x, '2' %}", "12")
        ] {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            for _ in 0..<2 {
                #expect(try await engine.render(parsed, context: context) == expected)
                #expect(try await engine.render(template: source, context: context, syntaxMode: mode) == expected)
                let recovered = try await engine.renderWithDiagnostics(parsed, context: context)
                #expect(recovered.output == expected && recovered.diagnostics.isEmpty)
            }
        }
        // Include reuses the same parsed partial site; render isolates/restores it.
        let root = try LiquidTemplate("{% include 'a' %}{% include 'a' %}{% include 'b' %}{% render 'a', x: x %}{% include 'a' %}", syntaxMode: mode)
        let partials = try ["a": LiquidTemplate("{% cycle x, '2' %}", syntaxMode: mode),
                            "b": LiquidTemplate("{% cycle x, '2' %}", syntaxMode: mode)]
        #expect(try await engine.render(root, context: context, templates: partials) == "12111")
    }

    @Test func concurrentRendersKeepCycleSitesImmutable() async throws {
        let engine = LiquidEngine()
        let parsed = try LiquidTemplate("{% for i in (1..3) %}{% cycle x, '2' %}{% cycle x, '2' %}{% endfor %}")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<32 {
                group.addTask { () async throws -> Void in
                    let x = String(index)
                    let context: LiquidObject = ["x": .string(x)]
                    let expected = x + x + "22" + x + x
                    #expect(try await engine.render(parsed, context: context) == expected)
                    #expect(try await engine.renderWithDiagnostics(parsed, context: context).output == expected)
                }
            }
            try await group.waitForAll()
        }
    }

}
