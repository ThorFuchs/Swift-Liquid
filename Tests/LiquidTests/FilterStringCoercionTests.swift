// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify filter string coercion")
struct FilterStringCoercionTests {
    @Test func compositeInputsUseRubyInspectionAtPublicEntryPoints() async throws {
        let engine = LiquidEngine()
        let input: LiquidObject = ["a": ["foo", "bar"], "b": ["foo": "bar", "nested": ["a", nil, true]]]
        let cases: [(String, String)] = [
            ("{{ a }}|{{ a | upcase }}", "foobar|[\"FOO\", \"BAR\"]"),
            ("{{ b | downcase }}", "{\"foo\"=>\"bar\", \"nested\"=>[\"a\", nil, true]}"),
            ("{{ a | base64_encode }}", "WyJmb28iLCAiYmFyIl0="),
            ("{{ b | escape }}", "{&quot;foo&quot;=&gt;&quot;bar&quot;, &quot;nested&quot;=&gt;[&quot;a&quot;, nil, true]}")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, expected) in cases {
                #expect(try await engine.render(template: source, context: input, syntaxMode: mode) == expected, "\(source)")
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: input) == expected, "\(source)")
            }
        }
    }

    @Test func escapedNestedStringsAndCapacityRemainCorrect() async throws {
        let input: LiquidObject = ["a": ["é\n\t\u{1B}\u{7F}", "a\"\\b", "#{x}"]]
        let source = "{{ a | append: '' }}"
        let expected = "[\"é\\n\\t\\e\\u007F\", \"a\\\"\\\\b\", \"\\#{x}\"]"
        #expect(try await LiquidEngine().render(template: source, context: input, syntaxMode: .strict2) == expected)
        let tiny = LiquidEngine(limits: .init(outputBytes: 3))
        await #expect(throws: LiquidError.self) { try await tiny.render(template: source, context: input, syntaxMode: .strict2) }
        let worker = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiquidEngine().render(template: source, context: input, syntaxMode: .strict2)
        }
        await #expect(throws: CancellationError.self) { try await worker.value }
    }
}
