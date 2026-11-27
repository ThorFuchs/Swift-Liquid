// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

private struct QuotedStringReference: Decodable, Sendable {
    let cases: [QuotedStringReferenceCase]
}

private struct QuotedStringReferenceCase: Decodable, Sendable {
    let name: String
    let sourceBytes: [UInt8]
    let mode: String
    let phase: String
    let outcome: String
    let outputBytes: [UInt8]?
    let line: Int?
}

@Suite("Pinned Ruby quoted strings")
struct QuotedStringCompatibilityTests {
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func referenceBytesAndParsePhase(mode: LiquidSyntaxMode) async throws {
        let url = try #require(Bundle.module.url(forResource: "QuotedStringReferenceCases", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(QuotedStringReference.self, from: Data(contentsOf: url))
        let cases = reference.cases.filter { $0.mode == mode.rawValue }
        #expect(cases.count == 32)
        let engine = LiquidEngine()
        for item in cases {
            let source = try #require(String(bytes: item.sourceBytes, encoding: .utf8))
            let parsed: LiquidTemplate
            do {
                parsed = try LiquidTemplate(source, syntaxMode: mode)
            } catch LiquidError.syntax(let message, let line, let column) {
                print("QUOTED-STRING \(mode.rawValue) \(item.name) parse-error line=\(String(describing: line)) column=\(String(describing: column)) message=\(message)")
                #expect(item.outcome == "parse-error", "\(item.name): unexpected syntax error")
                continue
            } catch {
                Issue.record("\(item.name): operational parse error: \(error)")
                continue
            }
            if item.outcome == "parse-error" {
                Issue.record("\(item.name): expected a reference parse error, but Swift parsed the source")
                continue
            }
            do {
                let output = try await engine.render(parsed)
                let actual = Array(output.utf8)
                print("QUOTED-STRING \(mode.rawValue) \(item.name) output=\(actual)")
                #expect(item.outcome == "output", "\(item.name): reference did not produce output")
                #expect(actual == item.outputBytes, "\(item.name): output bytes differ from pinned Ruby")
            } catch {
                Issue.record("\(item.name): unexpected render failure: \(error)")
            }
        }
    }
}
