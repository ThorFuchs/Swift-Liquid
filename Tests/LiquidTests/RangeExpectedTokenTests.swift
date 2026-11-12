// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 range expected-token diagnostics")
struct RangeExpectedTokenTests {
    @Test func pinnedRangeErrorsUseValidatedExpectedTokens() async throws {
        // Original templates from the pinned liquid-spec parser_errors corpus.
        let cases: [(String, String)] = [
            ("{% assign x = x | x : (1, 5) %}", "Expected dotdot but found comma"),
            ("{% case x %}{% when (1, 5) %}{% endcase %}", "Expected dotdot but found comma"),
            ("{% echo x | x : (1, 5) %}", "Expected dotdot but found comma"),
            ("{% if x == (1, 5) %}{% endif %}", "Expected dotdot but found comma"),
            ("{{ (1, 5) }}", "Expected dotdot but found comma"),
            ("{% assign x = (1..5 %}", "Expected close_round but found end_of_string"),
            ("{% cycle x : (1..5 %}", "Expected close_round but found end_of_string"),
            ("{% echo (1..5 %}", "Expected close_round but found end_of_string"),
            ("{% if (1..5 %}{% endif %}", "Expected close_round but found end_of_string"),
            ("{% render 'snippet' for (1..5 %}", "Expected close_round but found end_of_string"),
            ("{{ (1..5 }}", "Expected close_round but found end_of_string")
        ]
        let engine = LiquidEngine()
        for (source, reason) in cases {
            for entry in 0..<4 {
                do {
                    switch entry {
                    case 0: _ = try LiquidTemplate(source, syntaxMode: .strict2)
                    case 1: _ = try await engine.render(template: source, syntaxMode: .strict2)
                    case 2: _ = try await engine.renderWithDiagnostics(template: source, syntaxMode: .strict2)
                    default: _ = try engine.inspect(template: source, syntaxMode: .strict2)
                    }
                    Issue.record("Expected rejection: \(source)")
                } catch LiquidError.syntax(let message, let line, let column) {
                    #expect(message.contains(reason), "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func sourceOriginsModesAndValidRangesRemainBounded() async throws {
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ (1, 5) }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: ,") }
        }
        let engine = LiquidEngine()
        #expect(try await engine.render(template: "{% for x in (1..3) %}{{ x }}{% endfor %}", syntaxMode: .strict2) == "123")
        do {
            _ = try await engine.render(template: "{% render 'p' %}", templates: ["p": "é\n{{ (1, 5) }}"], syntaxMode: .strict2)
            Issue.record("Expected partial rejection")
        } catch LiquidError.syntax(let message, let line, let column) {
            #expect(message.contains("Expected dotdot but found comma"))
            #expect(line == 2 && column == 1)
        }
        let source = "{{ (1, 5) }}"
        #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: .strict2, limits: .init(sourceBytes: source.utf8.count - 1)) }
        let worker = Task { () throws -> LiquidTemplate in
            withUnsafeCurrentTask { $0?.cancel() }
            return try LiquidTemplate(source, syntaxMode: .strict2)
        }
        await #expect(throws: CancellationError.self) { try await worker.value }
    }
}
