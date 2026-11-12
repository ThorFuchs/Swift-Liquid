// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Lax incomplete root lookup")
struct LaxIncompleteLookupTests {
    @Test func terminalBracketRecoveryMatchesRuby() async throws {
        let engine = LiquidEngine()
        let context: LiquidObject = ["foo": "bar", "bar": "B"]
        for source in ["{{['foo'}}", "{{[['foo']}}", "{{[foo}}"] {
            #expect(try await engine.render(template: source, context: context, syntaxMode: .lax) == "bar")
            #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: .strict) }
            #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: .strict2) }
        }
        #expect(try await engine.render(template: "{{[['foo']]}}", context: context, syntaxMode: .lax) == "B")
        let key = String(repeating: "1234567890", count: 100)
        #expect(try await engine.render(template: "{{[['\(key)']}}", context: [key: "ok"], syntaxMode: .lax) == "ok")
        #expect(throws: LiquidError.self) { try LiquidTemplate("{{['foo' | upcase }}", syntaxMode: .lax) }
    }
}
