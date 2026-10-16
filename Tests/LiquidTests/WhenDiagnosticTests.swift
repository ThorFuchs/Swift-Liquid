// SPDX-License-Identifier: Apache-2.0
@testable import Liquid
import Foundation
import Testing

private struct WhenDiagnosticControl: Decodable, Sendable {
    let name: String
    let source: String
    let expectedMessage: String
    let expectedBare: Bool
    let referenceMessage: String
    let referenceLine: Int
    let expectedSwiftLine: Int
    let expectedSwiftColumn: Int
}

private func whenDiagnosticControls() throws -> [WhenDiagnosticControl] {
    struct Controls: Decodable { let rubyPin: String; let cases: [WhenDiagnosticControl] }
    let url = try #require(Bundle.module.url(forResource: "WhenDiagnosticControls", withExtension: "json", subdirectory: "Fixtures"))
    let controls = try JSONDecoder().decode(Controls.self, from: Data(contentsOf: url))
    #expect(controls.rubyPin == "4e39ae4cc3da73921923c0669e0fc84a66b2f696")
    #expect(controls.cases.count == 20)
    return controls.cases
}

@Suite("When lexical diagnostic presentation", .timeLimit(.minutes(1)))
struct WhenDiagnosticTests {
    // Reference strings come from native pinned Ruby strict2. Swift's existing
    // lax/strict rejections remain rejections even when Ruby accepts the source.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func whenReasonsAndNeighborContextsMatchPinnedRuby(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        for control in try whenDiagnosticControls() {
            for entry in 0..<4 {
                do {
                    switch entry {
                    case 0: _ = try LiquidTemplate(control.source, syntaxMode: mode)
                    case 1: _ = try await engine.render(template: control.source, syntaxMode: mode)
                    case 2: _ = try await engine.renderWithDiagnostics(template: control.source, syntaxMode: mode)
                    default: _ = try engine.inspect(template: control.source, syntaxMode: mode)
                    }
                    Issue.record("Existing rejection was lost: \(control.name), entry \(entry)")
                } catch LiquidError.syntax(let message, let line, let column) {
                    #expect(message.utf8.elementsEqual(control.expectedMessage.utf8), "\(control.name)")
                    #expect(line == control.expectedSwiftLine && column == control.expectedSwiftColumn)
                    #expect(line == control.referenceLine)
                    let reference = "Liquid syntax error (line \(control.referenceLine)): " + message
                    #expect(reference.utf8.elementsEqual(control.referenceMessage.utf8))
                }
            }
        }
    }

    @Test func bareWhenReasonsRetainValidatedOriginalFrames() throws {
        for control in try whenDiagnosticControls() {
            do {
                _ = try Lexer(control.source, sourceProvenance: .original(.anonymous)).tokenize()
                Issue.record("Expected native lexical rejection: \(control.name)")
            } catch let error as LexerError {
                guard case .unexpectedCharacter(let character, let offset, .resolved(let origin)?) = error else { throw error }
                #expect((origin.presentation == .reasonOnly) == control.expectedBare)
                #expect(origin.sourceIdentity == .anonymous)
                #expect(origin.position.line == control.expectedSwiftLine && origin.position.column == control.expectedSwiftColumn)
                #expect(origin.offending.lowerBound == offset && error.position == offset)
                let bytes = Array(control.source.utf8)
                #expect(bytes[origin.offending].elementsEqual(character.utf8))
                #expect(bytes[origin.markup].elementsEqual(origin.contextText.utf8))
                #expect(!origin.contextText.isEmpty)
                #expect(error.message.utf8.elementsEqual(control.expectedMessage.utf8))
            }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func whenFailuresPreserveAdmissionAndPartialPositions(mode: LiquidSyntaxMode) async throws {
        let source = "partial\n{% case x %}{% when & %}{% endcase %}"
        let failure = #expect(throws: LiquidError.self) {
            try LiquidTemplate(source, syntaxMode: mode, limits: .init(sourceBytes: source.utf8.count - 1))
        }
        if case .limitExceeded("sourceBytes")? = failure {} else { Issue.record("Admission must precede diagnostic formatting") }
        let engine = LiquidEngine()
        for recovering in [false, true] {
            do {
                if recovering {
                    _ = try await engine.renderWithDiagnostics(template: "root\n\n{% render 'p' %}", templates: ["p": source], syntaxMode: mode)
                } else {
                    _ = try await engine.render(template: "root\n\n{% render 'p' %}", templates: ["p": source], syntaxMode: mode)
                }
                Issue.record("Invalid partial became a successful render")
            } catch LiquidError.syntax(let message, let line, let column) {
                #expect(message == "Unexpected character &")
                #expect(line == 2 && column == 21)
            }
        }
        let healthy = try LiquidTemplate("{{ when_value }}|{% raw %}{% when & %}{% endraw %}", syntaxMode: mode)
        #expect(try await engine.render(healthy, context: ["when_value": "when"]) == "when|{% when & %}")
        #expect(try await engine.renderWithDiagnostics(healthy, context: ["when_value": "when"]).diagnostics.isEmpty)
    }
}
