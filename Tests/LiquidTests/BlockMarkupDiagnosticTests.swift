// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Strict2 block markup diagnostics")
struct BlockMarkupDiagnosticTests {
    @Test func pinnedMarkupAndNestingRejections() async throws {
        // Exact original templates and reference reasons from the pinned corpus.
        let cases: [(String, String, Int)] = [
            ("{% doc foo %}{% enddoc %}", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{% doc foo bar %}{% enddoc %}", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{% doc 123 %}{% enddoc %}", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{% doc 'hello' %}{% enddoc %}", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{% doc == %}{% enddoc %}", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{% doc | %}{% enddoc %}", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{% doc @#$ %}{% enddoc %}", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{%- doc foo -%}{%- enddoc -%}", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{% doc foo %}{% enddoc %}", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{% doc foo %}some content", "Syntax Error in 'doc' - Valid syntax: {% doc %}{% enddoc %}", 1),
            ("{% doc %}{% doc %}{% enddoc %}{% enddoc %}", "Syntax Error in 'doc' - Nested doc tags are not allowed", 1),
            ("{% doc %}hello{% doc %}world{% enddoc %}{% enddoc %}", "Syntax Error in 'doc' - Nested doc tags are not allowed", 1),
            ("{% doc %}{% doc %}{% enddoc %}", "Syntax Error in 'doc' - Nested doc tags are not allowed", 1),
            ("{% doc %}{% doc %}content", "Syntax Error in 'doc' - Nested doc tags are not allowed", 1),
            ("{% doc %}{% doc %}{% doc %}{% enddoc %}", "Syntax Error in 'doc' - Nested doc tags are not allowed", 1),
            ("{% doc %}{% doc foo %}{% enddoc %}", "Syntax Error in 'doc' - Nested doc tags are not allowed", 1),
            ("{% raw foo %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw foo bar %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw 123 %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw 'hello' %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw == %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw | %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw @#$ %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw . %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw : %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw x = 1 %}{% endraw %}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{%- raw foo -%}{%- endraw -%}", "Syntax Error in 'raw' - Valid syntax: raw", 1),
            ("{% raw foo %}content", "Syntax Error in 'raw' - Valid syntax: raw", 1),
        ]
        let engine = LiquidEngine()
        for (source, expected, expectedLine) in cases {
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
                    #expect(message == expected, "\(source), entry \(entry): \(message)")
                    #expect(line == expectedLine && column != nil, "\(source), entry \(entry)")
                }
            }
        }
    }

    @Test func validBlocksOtherModesAndAdmissionRemainStable() async throws {
        let engine = LiquidEngine()
        #expect(try await engine.render(template: "{% doc %}text{% enddoc %}{% raw %}{{x}}{% endraw %}", syntaxMode: .strict2) == "{{x}}")
        for mode in [LiquidSyntaxMode.lax, .strict] {
            do { _ = try LiquidTemplate("{% raw x %}{% endraw %}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected token: identifier(x)") }
            do { _ = try LiquidTemplate("{% doc %}{% doc %}{% enddoc %}", syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, _, _) { #expect(message == "Unclosed delimiter 'nested doc'") }
        }
        // A nested tag missing its own terminator is not a proven nested doc.
        do { _ = try LiquidTemplate("{% doc %}{% doc ", syntaxMode: .strict2); Issue.record("Expected rejection") }
        catch LiquidError.syntax(let message, let line, let column) {
            #expect(message == "Unclosed delimiter 'doc'" && line == nil && column == nil)
        }
        let source = "{% doc x %}{% enddoc %}"
        let error = #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: .strict2, limits: .init(sourceBytes: source.utf8.count - 1)) }
        if case .limitExceeded("sourceBytes")? = error {} else { Issue.record("Source admission must precede diagnostics") }
        let worker = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: source, syntaxMode: .strict2)
        }
        await #expect(throws: CancellationError.self) { try await worker.value }
    }
}
