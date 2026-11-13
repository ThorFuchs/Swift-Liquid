// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Where and loop lookup compatibility")
struct WhereAndLoopLookupTests {
    @Test func rangeBracketKeysDoNotBecomeStringsOrSlices() async throws {
        let engine = LiquidEngine()
        let source = "{{ object[(1..3)] }}|{{ values[(1..3)] }}|{{ object['1..3'] }}|{{ values[1] }}"
        let context: LiquidObject = ["object": ["1..3": "range"], "values": [0, 1, 2, 3, 4]]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            #expect(try await engine.render(parsed, context: context) == "||range|1")
            let recovered = try await engine.renderWithDiagnostics(parsed, context: context)
            #expect(recovered.output == "||range|1" && recovered.diagnostics.isEmpty)
            let access = "{{ values.first }}|{{ values['first'] }}|{{ values.last }}|{{ values[key] }}|{{ obj.first }}|{{ obj['first'] }}|{{ keyed['first'] }}"
            let keys: LiquidObject = ["values": [1, 2], "key": "last", "obj": ["x": "a"], "keyed": ["first": "actual"]]
            #expect(try await engine.render(template: access, context: keys, syntaxMode: mode) == "1||2||xa||actual")
        }
    }
    @Test func whereSupportsStringsAndObjectInputs() async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["words": ["alpha", "beta", "gamma"], "obj": ["a": "ok"],
                                     "rows": [["a": ""], ["a": "ok"]]]
        let cases = [
            ("{{ words | where: '' | join: ' ' }}", "alpha beta gamma"),
            ("{{ words | where: 'be' | join: ' ' }}", "beta"),
            ("{{ obj | where: 'a', 'ok' }}", "{\"a\"=>\"ok\"}"),
            ("{{ obj | where: 'a', 'bad' }}", ""),
            ("{{ rows | where: 'a', '' | size }}", "1")
        ]
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            for (source, expected) in cases {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed, context: context) == expected, "\(source)")
                let result = try await engine.renderWithDiagnostics(parsed, context: context)
                #expect(result.output == expected && result.diagnostics.isEmpty)
            }
        }
    }

    @Test func dottedAndIndexedBoundsAreEvaluatedPerInvocation() async throws {
        let source = "{% for x in items limit: bounds.count offset: offsets[0] %}{{ x }}{% endfor %}"
        let context: LiquidObject = ["items": ["a", "b", "c", "d"], "bounds": ["count": 2], "offsets": [1]]
        let engine = LiquidEngine()
        for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            #expect(try await engine.render(parsed, context: context) == "bc")
            #expect(try await engine.renderWithDiagnostics(parsed, context: context).output == "bc")
            let roots = try engine.inspect(parsed).variableRoots
            #expect(roots.contains("bounds") && roots.contains("offsets"))
            let duplicateCases = [
                ("offset:continue offset:3", "a|d"),
                ("offset:3 offset:continue", "a|bcd"),
                ("offset: bounds.count offset:1", "a|bcd"),
                ("offset:1 offset: bounds.count", "a|cd"),
                ("limit: bounds.count limit:1", "a|a"),
                ("limit:1 limit: bounds.count", "a|ab")
            ]
            for (attributes, expected) in duplicateCases {
                let repeated = "{% for x in items limit:1 %}{{ x }}{% endfor %}|{% for x in items \(attributes) %}{{ x }}{% endfor %}"
                #expect(try await engine.render(template: repeated, context: context, syntaxMode: mode) == expected, "\(attributes)")
            }
        }
        await #expect(throws: LiquidError.self) { try await LiquidEngine(limits: .init(outputBytes: 1)).render(template: source, context: context) }
        let task = Task { () async throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.render(template: source, context: context)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
