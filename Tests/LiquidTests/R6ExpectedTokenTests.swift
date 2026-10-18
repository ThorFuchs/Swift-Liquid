// SPDX-License-Identifier: Apache-2.0
@testable import Liquid
import Foundation
import Testing

private struct R6Case: Decodable, Sendable {
    let caseID: String
    let source: String
    let parserMode: String
    let renderMode: String
    let inputUTF8SHA256: String
    let expectedNativeMessage: String
    let expectedSwiftLine: Int
    let expectedSwiftColumn: Int
}

private func r6Cases() throws -> [R6Case] {
    struct Fixture: Decodable { let specPin: String; let rubyPin: String; let cases: [R6Case] }
    let url = try #require(Bundle.module.url(forResource: "R6ExpectedTokenCases", withExtension: "json", subdirectory: "Fixtures"))
    let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    #expect(f.specPin == "84bf25e0edbca5f7e530574788b0f875ab331f50")
    #expect(f.rubyPin == "4e39ae4cc3da73921923c0669e0fc84a66b2f696")
    #expect(f.cases.count == 19 && Set(f.cases.map(\.caseID)).count == 19)
    return f.cases
}

@Suite("R6 typed expected-token diagnostics", .timeLimit(.minutes(1)))
struct R6ExpectedTokenTests {
    @Test(arguments: Array(0..<19))
    func originalNineteenMatchPinnedTypedPresentation(index: Int) async throws {
        let c = try r6Cases()[index]
        #expect(c.parserMode == "strict2" && c.renderMode == "raise")
        let engine = LiquidEngine()
        for entry in 0..<4 {
            do {
                switch entry {
                case 0: _ = try LiquidTemplate(c.source, syntaxMode: .strict2)
                case 1: _ = try await engine.render(template: c.source, syntaxMode: .strict2)
                case 2: _ = try await engine.renderWithDiagnostics(template: c.source, syntaxMode: .strict2)
                default: _ = try engine.inspect(template: c.source, syntaxMode: .strict2)
                }
                Issue.record("Original rejection lost: \(c.caseID), entry \(entry)")
            } catch LiquidError.syntax(let message, let line, let column) {
                #expect(message.utf8.elementsEqual(c.expectedNativeMessage.utf8), "\(c.caseID), entry \(entry)")
                #expect(line == c.expectedSwiftLine && column == c.expectedSwiftColumn, "\(c.caseID)")
            }
        }
    }

    // These mode/policy controls are supplementary, not extra corpus identities.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func presentationAcrossModesAndEntryPoints(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        for c in try r6Cases() {
            for recovering in [false, true] {
                do {
                    if recovering { _ = try await engine.renderWithDiagnostics(template: c.source, syntaxMode: mode) }
                    else { _ = try await engine.render(template: c.source, syntaxMode: mode) }
                    Issue.record("Existing rejection became recovery: \(c.caseID)")
                } catch LiquidError.syntax(let message, let line, let column) {
                    #expect(message.utf8.elementsEqual(c.expectedNativeMessage.utf8))
                    #expect(line == c.expectedSwiftLine && column == c.expectedSwiftColumn)
                }
            }
        }
        // Omitted mode keeps the existing default, independently of Ruby lax acceptance.
        do { _ = try LiquidTemplate("{{ x[0 }}"); Issue.record("Default acceptance changed") }
        catch LiquidError.syntax(let message, _, _) {
            #expect(message == "Expected close_square but found end_of_string in \"{{ x[0 }}\"")
        }
    }

    @Test func positionsAndMarkupRetainExactAdmittedBytes() throws {
        let controls: [(String, String, Int, Int)] = [
            ("é{{ x[0 }}", "{{ x[0 }}", 1, 2),
            ("e\u{301}{{ x[0 }}", "{{ x[0 }}", 1, 3),
            ("😀\t{{ x[0 }}", "{{ x[0 }}", 1, 3),
            ("\r{{ x[0 }}", "{{ x[0 }}", 1, 2),
            ("\r\n{{ x[0 }}", "{{ x[0 }}", 2, 1),
            ("\n{{- x[0 -}}", "{{ x[0 }}", 2, 1),
            ("{% assign\n x = x[0 %}", "x = x[0", 2, 2),
            ("{% assign\r\n x = x[0 %}", "x = x[0", 2, 2),
            ("{% assign\r x = x[0 %}", "x = x[0", 1, 12),
            ("{%- echo x[0 -%}", "{{x[0 }}", 1, 10)
        ]
        for (source, context, line, column) in controls {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, let actualLine, let actualColumn) {
                #expect(message.utf8.elementsEqual(("Expected close_square but found end_of_string in \"" + context + "\"").utf8), "\(source)")
                #expect(actualLine == line && actualColumn == column, "\(source)")
            }
        }
    }

    @Test func fallbacksKeepTypedRejectionWithoutGuessedOrigins() throws {
        let sources = ["{{ '}}' | plus: x[0 }}", "{% assign x = '%}' | default: x[0 %}",
                       "{% liquid\n assign x = x[0\n%}"]
        for source in sources {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, let line, let column) {
                #expect(message == (source.hasPrefix("{{") ? "Expected ] but found }}" : "Expected ] but found %}"))
                #expect(line == nil && column == nil)
            }
        }
        // Native equality tokens collapse more than one source spelling. Keep
        // unsupported comparison/string bodies unmapped, rather than guessing.
        for (source, expected) in [("{{ x[0 = }}", "Expected ] but found =="),
                                   ("{{ x[0 'bad' }}", "Expected ] but found string(bad)")] {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, let line, let column) {
                #expect(message == expected && line == nil && column == nil)
            }
        }
        let source = "{{ x[0 }}"
        let tokens = try Lexer(source).tokenize()
        // A source string alone is no assertion of original provenance.
        do { _ = try Parser(consuming: tokens, source: source).parse(); Issue.record("Expected rejection") }
        catch let e as ParserError {
            guard case .expectedToken(.rightBracket, got: .variableEnd, origin: .unmapped(.unspecifiedOrRewrittenSource)?) = e else { throw e }
            #expect(e.message == "Expected ] but found }}" && e.sourceLocation == nil)
        }
        let frame = DiagnosticSourceFrame(construct: 0..<9, markup: 2..<7, anchor: 0,
            presentation: .outputMarkup, header: nil, headerSpelling: nil)
        for identity in [DiagnosticSourceIdentity.anonymous, .root, .partial(ScalarKey("é")), .partial(ScalarKey("e\u{301}"))] {
            let snapshot = DiagnosticSourceSnapshot(admittedUTF8: Array(source.utf8), identity: identity)
            guard case .resolved(let origin) = try snapshot.expectedToken("}}", at: 7, frame: frame, atMarkupEnd: true) else {
                Issue.record("Validated origin missing"); continue
            }
            #expect(origin.sourceIdentity == identity && origin.position == .init(line: 1, column: 1))
            #expect(try snapshot.expectedToken("]", at: 7, frame: frame, atMarkupEnd: true) == .unmapped(.reasonDoesNotMatchOriginalToken))
            #expect(try snapshot.expectedToken("}}", at: Int.max, frame: frame, atMarkupEnd: true) == .unmapped(.invalidBoundary))
            #expect(try snapshot.expectedToken("}}", at: -1, frame: frame, atMarkupEnd: true) == .unmapped(.invalidBoundary))
        }
    }

    @Test func typedVocabularyPreservesFirstRejection() throws {
        for (source, reason) in [("{{ x[0 foo }}", "Expected close_square but found id"),
                                 ("{{ x[0) }}", "Expected close_square but found close_round")] {
            do { _ = try LiquidTemplate(source, syntaxMode: .strict2); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let message, let line, let column) {
                #expect(message == reason + " in \"" + source + "\"")
                #expect(line == 1 && column == 1)
            }
        }
        // The lexer still rejects first, before the parser presentation helper.
        do { _ = try LiquidTemplate("{{ x[0 & }}"); Issue.record("Expected lexical rejection") }
        catch LiquidError.syntax(let message, _, _) { #expect(message == "Unexpected character & in \"{{ x[0 & }}\"") }
        do { _ = try LiquidTemplate("{{ x. }}", syntaxMode: .strict2); Issue.record("Expected existing generic rejection") }
        catch LiquidError.syntax(let message, let line, let column) {
            #expect(message == "Unexpected token: }}" && line == 1 && column == 7)
        }
        #expect(TokenType.rightBracket.description == "]" && TokenType.variableEnd.description == "}}")
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func sourceDepthAndPartialAdmissionStayOperational(mode: LiquidSyntaxMode) async throws {
        let source = "{{ x[0 }}"
        let error = #expect(throws: LiquidError.self) {
            try LiquidTemplate(source, syntaxMode: mode, limits: .init(sourceBytes: source.utf8.count - 1))
        }
        if case .limitExceeded("sourceBytes")? = error {} else { Issue.record("Byte admission must precede diagnostics") }
        let depth = #expect(throws: LiquidError.self) {
            try LiquidTemplate("{% if true %}{{ x[0 }}{% endif %}", syntaxMode: mode, limits: .init(nestingDepth: 1))
        }
        if case .limitExceeded("nestingDepth")? = depth {} else { Issue.record("Depth rejection must stay operational") }
        let engine = LiquidEngine()
        for recovering in [false, true] {
            do {
                if recovering { _ = try await engine.renderWithDiagnostics(template: "root\n\nhealthy", templates: ["unused": "partial\n" + source], syntaxMode: mode) }
                else { _ = try await engine.render(template: "root\n\nhealthy", templates: ["unused": "partial\n" + source], syntaxMode: mode) }
                Issue.record("Eager partial rejection changed")
            } catch LiquidError.syntax(let message, let line, let column) {
                #expect(message == "Expected close_square but found end_of_string in \"{{ x[0 }}\"")
                #expect(line == 2 && column == 1) // Partial-local, with no invented template name.
            }
        }
    }

    @Test func cancellationAtExpectedTokenProviderEntryKeepsReuseHealthy() async throws {
        let snapshot = DiagnosticSourceSnapshot(admittedUTF8: Array("{{ x[0 }}".utf8), identity: .anonymous)
        let frame = DiagnosticSourceFrame(construct: 0..<9, markup: 2..<7, anchor: 0,
            presentation: .outputMarkup, header: nil, headerSpelling: nil)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try snapshot.expectedToken("}}", at: 7, frame: frame, atMarkupEnd: true)
        }
        do { _ = try await task.value; Issue.record("Provider swallowed cancellation") }
        catch is CancellationError {}
        let engine = LiquidEngine()
        let sibling = try LiquidTemplate("{{ value }}")
        #expect(try await engine.render(sibling, context: ["value": "healthy"]) == "healthy")
    }

    @Test func concurrentRendersKeepExpectedTokenOriginsInvocationOwned() async throws {
        let engine = LiquidEngine()
        let healthy = try LiquidTemplate("{{ value }}")
        let cases = try r6Cases()
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for i in 0..<38 {
                let c = cases[i % cases.count]
                group.addTask {
                    do { _ = try await engine.renderWithDiagnostics(template: c.source, syntaxMode: .strict2); return false }
                    catch LiquidError.syntax(let message, let line, let column) {
                        guard message.utf8.elementsEqual(c.expectedNativeMessage.utf8), line == c.expectedSwiftLine, column == c.expectedSwiftColumn else { return false }
                    }
                    return try await engine.render(healthy, context: ["value": "healthy"]) == "healthy"
                }
            }
            for try await result in group { #expect(result) }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func validInputsAndWhenDistinctionStayStable(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        #expect(try await engine.render(template: "{{ x[0] }}|{{ '}}' }}", context: ["x": [7]], syntaxMode: mode) == "7|}}")
        #expect(try await engine.renderWithDiagnostics(template: "{% assign x = 7 %}{{ x }}", syntaxMode: mode).output == "7")
        for (source, message) in [
            ("{% case x[0 %}{% endcase %}", "Expected close_square but found end_of_string in \"x[0\""),
            ("{% case x %}{% when x[0 %}{% endcase %}", "Expected close_square but found end_of_string"),
            ("{% case x %}{% when & %}{% endcase %}", "Unexpected character &")
        ] {
            do { _ = try LiquidTemplate(source, syntaxMode: mode); Issue.record("Expected rejection") }
            catch LiquidError.syntax(let actual, _, _) { #expect(actual == message) }
        }
    }
}
