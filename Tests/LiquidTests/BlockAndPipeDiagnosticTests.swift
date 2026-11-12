// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 unclosed blocks and trailing pipes")
struct BlockAndPipeDiagnosticTests {
    @Test func pinnedRejectionsRetainSourceAndReason() async throws {
        // Original templates and expectations from the pinned Shopify corpus.
        let cases: [(String, String, Int)] = [
            ("{% comment %}hello", "'comment' tag was never closed", 1),
            ("{% comment %}{% comment %}inner{% endcomment %}", "'comment' tag was never closed", 1),
            ("{% comment %}", "'comment' tag was never closed", 1),
            ("{%- comment -%}hello", "'comment' tag was never closed", 1),
            ("{% doc %}", "'doc' tag was never closed", 1),
            ("{% doc %}some content here", "'doc' tag was never closed", 1),
            ("{% doc %}{% if true %}hello{% endif %}", "'doc' tag was never closed", 1),
            ("{%- doc -%}content", "'doc' tag was never closed", 1),
            ("hello\n\n{% doc %}content", "'doc' tag was never closed", 3),
            ("{% doc %}a{% enddoc %}{% doc %}b", "'doc' tag was never closed", 1),
            ("{% if x and x | %}{% endif %}", "Expected end_of_string but found pipe", 1),
            ("{% if x | %}{% endif %}", "Expected end_of_string but found pipe", 1),
            ("{% include x | %}", "Expected end_of_string but found pipe", 1),
            ("{% raw %}", "'raw' tag was never closed", 1),
            ("{% raw %}some content", "'raw' tag was never closed", 1),
            ("{% raw %}{% if true %}{% endif %}", "'raw' tag was never closed", 1),
            ("{%- raw -%}content", "'raw' tag was never closed", 1),
            ("{% raw %}a{% endraw %}{% raw %}b", "'raw' tag was never closed", 1),
            ("hello\n\n{% raw %}content", "'raw' tag was never closed", 3),
            ("{% raw %}{% raw %}content", "'raw' tag was never closed", 1),
            ("{% render 'snippet' | %}", "Expected end_of_string but found pipe", 1),
            ("{% unless x and x | %}{% endunless %}", "Expected end_of_string but found pipe", 1),
            ("{% unless x | %}{% endunless %}", "Expected end_of_string but found pipe", 1),
            ("{% unless x || y %}{% endunless %}", "Expected end_of_string but found pipe", 1),
        ]
        let engine = LiquidEngine()
        for (source, expected, expectedLine) in cases + [
            ("{% comment %}{% raw %}hello{% endcomment %}", "'raw' tag was never closed", 1),
            ("{% comment %}{% raw %}hello", "'raw' tag was never closed", 1)
        ] {
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
                    #expect(message.contains(expected), "\(source), entry \(entry): \(message)")
                    #expect(line == expectedLine && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func validBlocksAndOtherModesStayBounded() async throws {
        let engine = LiquidEngine()
        #expect(try await engine.render(template: "{% raw %}{{ x }}{% endraw %}|{% comment %}hidden{% endcomment %}ok|{% doc %}note{% enddoc %}", syntaxMode: .strict2) == "{{ x }}|ok|")
        #expect(try await engine.render(template: "{% if true %}yes{% endif %}", syntaxMode: .strict2) == "yes")
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{% raw %}text", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: text()") }
            do { _ = try LiquidTemplate("{% doc %}text", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unclosed delimiter 'doc'") }
        }
        // Incomplete nested or argument-bearing doc boundaries remain unmapped.
        let ambiguous = "{% doc %}123{% enddoc xyz %}"
        do { _ = try LiquidTemplate(ambiguous, syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, let line, let column) {
            #expect(message == "Unclosed delimiter 'doc'" && line == nil && column == nil)
        }
        do { _ = try LiquidTemplate("{% doc %}{% doc %}content", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, _, _) {
            #expect(message == "Syntax Error in 'doc' - Nested doc tags are not allowed")
        }
        let worker = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: "{% raw %}text", syntaxMode: .strict2)
        }
        await #expect(throws: CancellationError.self) { try await worker.value }
    }
}
