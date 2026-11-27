// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

private struct RecoveryReference: Decodable, Sendable {
    let cases: [RecoveryCase]
}

private struct RecoveryCase: Decodable, Sendable {
    let name: String
    let sourceBytes: [UInt8]
    let mode: String
    let phase: String
    let outcome: String
    let outputBytes: [UInt8]?
    let line: Int?
}

@Suite("Pinned Ruby quote recovery controls")
struct LaxQuoteRecoveryReferenceTests {
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func recoveryPhaseAndBytes(mode: LiquidSyntaxMode) async throws {
        let url = try #require(Bundle.module.url(forResource: "LaxQuoteRecoveryCases", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(RecoveryReference.self, from: Data(contentsOf: url))
        let cases = reference.cases.filter { $0.mode == mode.rawValue }
        #expect(cases.count == 25)
        let engine = LiquidEngine(strictFilters: true)
        let context: LiquidObject = ["unterminated": "FOUND", "a": ["n": "NESTED"], "value": "ok"]
        for item in cases {
            let source = try #require(String(bytes: item.sourceBytes, encoding: .utf8))
            let parsed: LiquidTemplate
            do {
                parsed = try LiquidTemplate(source, syntaxMode: mode)
            } catch LiquidError.syntax(let message, let line, let column) {
                print("RECOVERY \(mode.rawValue) \(item.name) parse-error line=\(String(describing: line)) column=\(String(describing: column)) message=\(message)")
                #expect(item.outcome == "parse-error", "\(item.name): unexpected syntax error")
                continue
            } catch {
                Issue.record("\(item.name): operational parse error: \(error)")
                continue
            }
            if item.outcome == "parse-error" {
                Issue.record("\(item.name): expected reference parse error")
                continue
            }
            do {
                let output = try await engine.render(parsed, context: context)
                let bytes = Array(output.utf8)
                print("RECOVERY \(mode.rawValue) \(item.name) output=\(bytes)")
                #expect(item.outcome == "output", "\(item.name): expected a language render error")
                #expect(bytes == item.outputBytes, "\(item.name): output bytes differ")
            } catch LiquidError.rendering(let message) {
                print("RECOVERY \(mode.rawValue) \(item.name) render-error=\(message)")
                #expect(item.outcome == "render-error", "\(item.name): unexpected language render error")
            } catch {
                Issue.record("\(item.name): operational or unexpected render error: \(error)")
            }
        }
    }
}
