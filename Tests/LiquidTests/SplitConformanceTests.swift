// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Split conformance")
struct SplitConformanceTests {
    // The first two inputs reproduce pinned liquid-spec cases. The other
    // examples were separately checked against the pinned Ruby implementation.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func trailingEmptyFieldsMatchRubyWithoutRemovingInteriorFields(mode: LiquidSyntaxMode) async throws {
        let cases: [(String, String, String, Int)] = [
            ("abc", "c", "ab", 1), ("banana", "a", "b#n#n", 3),
            ("abc", "a", "#bc", 2), ("a,,b,,", ",", "a##b", 3),
            (",,", ",", "", 0), ("", ",", "", 0), ("abc", "X", "abc", 1),
            (",a", ",", "#a", 2), ("éλé", "é", "#λ", 2),
            ("α|β||", "|", "α#β", 2), ("a::b::", "::", "a#b", 2),
            ("abc", "", "a#b#c", 3)
        ]
        let source = "{% assign parts = text | split: separator %}{{ parts | join: '#' }}|{{ parts | size }}"
        let template = try LiquidTemplate(source, syntaxMode: mode)
        let engine = LiquidEngine()
        for (text, separator, output, count) in cases {
            let context: LiquidObject = ["text": .string(text), "separator": .string(separator)]
            #expect(try await engine.render(template, context: context) == "\(output)|\(count)")
            #expect(try await engine.render(template: source, context: context, syntaxMode: mode) == "\(output)|\(count)")
        }
    }

    @Test func splitKeepsOutputLimitsAndCancellation() async throws {
        let template = try LiquidTemplate("{{ text | split: 'c' | join: '-' }}")
        let context: LiquidObject = ["text": .string("abc")]
        #expect(try await LiquidEngine().render(template, context: context) == "ab")
        await #expect(throws: LiquidError.self) {
            try await LiquidEngine(limits: .init(outputBytes: 1)).render(template, context: context)
        }
        let task = Task { () throws -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LiquidEngine().render(template, context: context)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await LiquidEngine().render(template, context: context) == "ab")
    }
}
