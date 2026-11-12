// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Shopify filter string coercion")
struct FilterStringCoercionTests {
    @Test func compositeSortAndJoinSeparatorUseRubyStringCoercion() async throws {
        let engine = LiquidEngine()
        let input: LiquidObject = [
            "objects": [["foo": "bar"], ["foo": 123], ["foo": nil], ["foo": true], ["foo": ["foo", "bar"]]],
            "values": [["key1": "value1"], ["key2": "value2"]], "glue": ["lol": "wut"],
            "numbers": [9, 1111, 87]
        ]
        let cases = [
            ("{{ objects | sort_natural }}", "{\"foo\"=>\"bar\"}{\"foo\"=>123}{\"foo\"=>[\"foo\", \"bar\"]}{\"foo\"=>nil}{\"foo\"=>true}"),
            ("{{ values | join: glue }}", "{\"key1\"=>\"value1\"}{\"lol\"=>\"wut\"}{\"key2\"=>\"value2\"}"),
            ("{{ numbers | sort_natural | join: ',' }}", "1111,87,9")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                let actual = try await engine.render(parsed, context: input)
                #expect(actual == expected, "\(source)")
                let recovered = try await engine.renderWithDiagnostics(parsed, context: input)
                #expect(recovered.output == expected && recovered.diagnostics.isEmpty, "\(source)")
            }
        }
    }
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
    @Test func outputObjectsInspectNestedValuesAcrossRenderPaths() async throws {
        let engine = LiquidEngine()
        let object: LiquidValue = .object(["k": "v", "nested": [nil, true, "a\n"]])
        let input: LiquidObject = ["obj": object, "rows": [object, ["k": "x"]]]
        let inspected = "{\"k\"=>\"v\", \"nested\"=>[nil, true, \"a\\n\"]}"
        let cases: [(String, String)] = [
            ("{{ obj }}", inspected),
            ("before{{ obj }}after", "before" + inspected + "after"),
            ("{% if true %}{{ obj }}{% endif %}", inspected),
            ("{{ rows }}", inspected + "{\"k\"=>\"x\"}"),
            ("{{ rows | join: '|' }}", inspected + "|{\"k\"=>\"x\"}")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(template: source, context: input, syntaxMode: mode) == expected)
                #expect(try await engine.render(parsed, context: input) == expected)
                #expect(try await engine.renderWithDiagnostics(parsed, context: input).output == expected)
                #expect(try await engine.renderWithMetrics(parsed, context: input).output == expected)
            }
        }
        let tight = LiquidEngine(limits: .init(outputBytes: inspected.utf8.count - 1))
        await #expect(throws: LiquidError.self) { try await tight.render(template: "{{ obj }}", context: input) }
        let cancelled = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: "{{ obj }}", context: input)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

}
