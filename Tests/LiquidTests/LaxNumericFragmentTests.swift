// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Lax numeric fragments")
struct LaxNumericFragmentTests {
    @Test func dotsFollowReferenceWithoutChangingRanges() async throws {
        let engine = LiquidEngine()
        #expect(try await engine.render(template: "{{ 1..3 }}", syntaxMode: .lax) == "1.0")
        #expect(try await engine.render(template: "{% if expected == 0.....5 %}yes{% endif %}", context: ["expected": 0.0], syntaxMode: .lax) == "yes")
        #expect(try await engine.render(template: "{% if expected == -0..1 %}yes{% endif %}", context: ["expected": 0.0], syntaxMode: .lax) == "yes")
        #expect(try await engine.render(template: "{% for i in (1...5) %}{{ i }}{% endfor %}", syntaxMode: .lax) == "12345")
        for mode in [LiquidSyntaxMode.strict, .strict2] {
            #expect(throws: LiquidError.self) { try LiquidTemplate("{% for i in (1...5) %}{{ i }}{% endfor %}", syntaxMode: mode) }
        }
    }
}
