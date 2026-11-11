// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Recovered strict2 diagnostics")
struct RecoveredDiagnosticTests {
    private func check(_ sources: [String], message expected: String) async throws {
        let engine = LiquidEngine()
        for source in sources {
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
                    #expect(message == expected, "\(source), entry \(entry)")
                    #expect(line == 1 && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func trailingIdentifiersKeepTheirRejection() async throws {
        try await check(["{% assign x = x extra %}", "{% capture x extra %}{% endcapture %}",
                         "{% case x extra %}{% endcase %}", "{% cycle x extra %}",
                         "{% decrement x extra %}", "{% echo x extra %}", "{% increment x extra %}",
                         "{% if x and x x == [0] %}{% endif %}", "{{ x extra }}"],
                        message: "Expected end_of_string but found id")
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{{ x extra }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: identifier(extra)") }
        }
    }

    @Test func partialAttributeCommaKeepsItsRejection() async throws {
        try await check(["{% include x step , x %}", "{% include x step , %}",
                         "{% render 'snippet' step , x %}", "{% render 'snippet' step , %}"],
                        message: "Expected colon but found comma")
        let source = "{% render 'snippet', step: 'ok' %}|{% include 'snippet', step: 'ok' %}"
        #expect(try await LiquidEngine().render(template: source, templates: ["snippet": "{{ step }}"], syntaxMode: .strict2) == "ok|ok")
    }

    @Test func missingExpressionAtMarkupEndKeepsItsRejection() async throws {
        try await check(["{% assign x = x [ %}", "{% case  %}{% endcase %}",
                         "{% case x %}{% when x , %}{% endcase %}", "{% cycle x : %}",
                         "{% echo x [ %}", "{% for x in %}{% endfor %}",
                         "{% if x and x == %}{% endif %}", "{% unless x and %}{% endunless %}",
                         "{% tablerow x in %}{% endtablerow %}", "{{ x [ }}"],
                        message: "[:end_of_string] is not a valid expression")
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{% if x == %}{% endif %}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: %}") }
        }
    }
    @Test func missingIdentifierRetainsExistingRejection() async throws {
        try await check(["{% assign x = x . %}", "{% assign x = x | %}",
            "{% capture %}{% endcapture %}", "{% case x. %}{% endcase %}",
            "{% cycle x. %}", "{% decrement %}", "{% increment %}", "{% echo x. %}",
            "{% for x in x. %}{% endfor %}", "{% if x. %}{% endif %}",
            "{% unless x. %}{% endunless %}", "{% tablerow x in x. %}{% endtablerow %}",
            "{{ x | x: x. }}", "{{ x | }}"], message: "Expected id but found end_of_string")
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            do { _ = try LiquidTemplate("{{ x. }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: }}") }
        }
    }

    @Test func validatedUnclosedQuotesPreserveOriginsAndAdmission() async throws {
        let cases = ["{% assign x = x | x : x , , \"hello %}",
                     "{% echo x | x : x , , 'hello %}", "{{ x | x : x , , 'hello }}"]
        let engine = LiquidEngine()
        for source in cases {
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
                    #expect(message.contains("Unexpected character"))
                    #expect(line == 1 && column != nil)
                }
            }
        }
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            do { _ = try LiquidTemplate("{{ 'unterminated }}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, let line, let column) {
                if mode == .strict2 {
                    #expect(message == "Unexpected character ' in \"{{ 'unterminated }}\"")
                    #expect(line == 1 && column == 1)
                } else {
                    #expect(message == "Unterminated string literal" && line == nil && column == nil)
                }
            }
        }
        let valid = try LiquidTemplate("{{ '}}' }}", syntaxMode: .strict2)
        #expect(try await engine.render(valid) == "}}")
    }

}
