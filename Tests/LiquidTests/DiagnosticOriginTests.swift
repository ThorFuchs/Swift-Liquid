// SPDX-License-Identifier: Apache-2.0
@testable import Liquid
import Foundation
import Testing

private struct OriginControl: Decodable, Sendable {
    let name: String
    let source: String
    let expectedMessage: String
    let expectedLine: Int
    let expectedSwiftColumn: Int
    let referenceMessage: String
}
private struct OriginControls: Decodable {
    let cases: [OriginControl]
    let rubyPin: String
}
private func originControls() throws -> [OriginControl] {
    let url = try #require(Bundle.module.url(forResource: "DiagnosticOriginControls", withExtension: "json", subdirectory: "Fixtures"))
    let values = try JSONDecoder().decode(OriginControls.self, from: Data(contentsOf: url))
    #expect(values.rubyPin == "4e39ae4cc3da73921923c0669e0fc84a66b2f696")
    #expect(values.cases.count == 14)
    return values.cases
}

@Suite("Original-source unexpected-character diagnostics", .timeLimit(.minutes(1)))
struct DiagnosticOriginTests {
    // Native pinned Ruby strict2 reason/context/line evidence. All Swift modes
    // retain their original acceptance; this is not lax/strict Ruby acceptance parity.
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func unexpectedCharactersUsePinnedRubyContext(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        for control in try originControls() {
            for entry in 0..<4 {
                do {
                    switch entry {
                    case 0: _ = try LiquidTemplate(control.source, syntaxMode: mode)
                    case 1: _ = try await engine.render(template: control.source, syntaxMode: mode)
                    case 2: _ = try await engine.renderWithDiagnostics(template: control.source, syntaxMode: mode)
                    default: _ = try engine.inspect(template: control.source, syntaxMode: mode)
                    }
                    Issue.record("Invalid source accepted: \(control.name), entry \(entry)")
                } catch LiquidError.syntax(let message, let line, let column) {
                    #expect(message.utf8.elementsEqual(control.expectedMessage.utf8), "\(control.name)")
                    #expect(line == control.expectedLine && column == control.expectedSwiftColumn, "\(control.name)")
                    let reference = "Liquid syntax error (line \(control.expectedLine)): " + message
                    #expect(reference.utf8.elementsEqual(control.referenceMessage.utf8))
                }
            }
        }
    }

    @Test func originalBytePositionsKeepScalarAndLFPolicies() throws {
        let snapshot = DiagnosticSourceSnapshot(admittedUTF8: Array("a\r\n😀e\u{301}\tz\rQ".utf8), identity: .root)
        let expected = [(0,1,1), (1,1,2), (2,1,3), (3,2,1), (7,2,2), (8,2,3),
                        (10,2,4), (11,2,5), (12,2,6), (13,2,7), (14,2,8)]
        for (byte, line, column) in expected {
            #expect(try snapshot.position(at: byte) == .init(line: line, column: column))
        }
        for offset in [-1, 4, 9, 15, Int.max] { #expect(try snapshot.position(at: offset) == nil) }
        #expect(try DiagnosticSourceSnapshot(admittedUTF8: [], identity: .anonymous).position(at: 0) == .init(line: 1, column: 1))
    }

    @Test func originsKeepExactIdentityAndValidatedRanges() throws {
        let source = "{{ x& }}"
        let frame = DiagnosticSourceFrame(construct: 0..<8, markup: 2..<6, anchor: 0, presentation: .outputMarkup, header: nil, headerSpelling: nil)
        let first = DiagnosticSourceSnapshot(admittedUTF8: Array(source.utf8), identity: .partial(ScalarKey("é")))
        let second = DiagnosticSourceSnapshot(admittedUTF8: Array(source.utf8), identity: .partial(ScalarKey("e\u{301}")))
        guard case .resolved(let origin) = try first.unexpectedCharacter("&", at: 4, frame: frame),
              case .resolved(let other) = try second.unexpectedCharacter("&", at: 4, frame: frame) else {
            Issue.record("Original source origin was not resolved"); return
        }
        #expect(origin.sourceIdentity != other.sourceIdentity)
        #expect(origin.construct == 0..<8 && origin.markup == 2..<6 && origin.offending == 4..<5 && origin.anchor == 0)
        #expect(try first.unexpectedCharacter("@", at: 4, frame: frame) == .unmapped(.reasonDoesNotMatchOriginalScalar))
        #expect(try first.unexpectedCharacter("&", at: -1, frame: frame) == .unmapped(.invalidBoundary))
        #expect(try first.unexpectedCharacter("&", at: Int.max, frame: frame) == .unmapped(.invalidBoundary))
        let unpaired = DiagnosticSourceFrame(construct: 0..<8, markup: 2..<6, anchor: 0,
            presentation: .outputMarkup, header: nil, headerSpelling: "unproved")
        #expect(try first.unexpectedCharacter("&", at: 4, frame: unpaired) == .unmapped(.invalidBoundary))
        var origins: [DiagnosticSourceOrigin] = []
        for value in ["a\u{301}\u{323}", "a\u{323}\u{301}"] {
            do { _ = try Lexer("{{ '\(value)' & }}", sourceProvenance: .original(.anonymous)).tokenize() }
            catch let error as LexerError {
                guard case .unexpectedCharacter(_, _, .resolved(let origin)?) = error else { throw error }
                origins.append(origin)
            }
        }
        #expect(origins.count == 2 && origins[0] != origins[1])
    }

    @Test func unmappedFramesRetainTheActualTypedReason() throws {
        do { _ = try Lexer("{{ x & }}").tokenize(); Issue.record("Expected rejection") }
        catch let error as LexerError {
            guard case .unexpectedCharacter("&", _, .unmapped(.unspecifiedOrRewrittenSource)?) = error else { throw error }
            #expect(error.message == "Unexpected character '&'")
        }
        do {
            _ = try Lexer("{{ '}}' & }}", sourceProvenance: .original(.anonymous)).tokenize()
            Issue.record("Expected native rejection")
        } catch let error as LexerError {
            guard case .unexpectedCharacter("&", _, .unmapped(.incompleteOrAmbiguousConstruct)?) = error else { throw error }
        }
        // The existing inline-comment branch constructs a Character from a byte.
        // Preserve that reason rather than silently replacing it with the source scalar.
        do {
            _ = try Lexer("{% # ok\n 😀 %}", sourceProvenance: .original(.anonymous)).tokenize()
            Issue.record("Expected inline-comment rejection")
        } catch let error as LexerError {
            guard case .unexpectedCharacter(let character, _, .unmapped(let gap)?) = error else { throw error }
            #expect(gap == .incompleteOrAmbiguousConstruct)
            #expect(character != "😀")
        }
        // Invalid headers must not stringify a huge numeric token through Int.
        do {
            _ = try Lexer("{% 999999999999999999999999999999999999.0 & %}", sourceProvenance: .original(.anonymous)).tokenize()
            Issue.record("Expected malformed-header rejection")
        } catch let error as LexerError {
            guard case .unexpectedCharacter("&", _, .unmapped(.incompleteOrAmbiguousConstruct)?) = error else { throw error }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func otherFamiliesAndUnmappedLiquidKeepTheirBoundaries(mode: LiquidSyntaxMode) throws {
        for source in ["{{ 'unterminated }}", "{% liquid\n echo x &\n%}"] {
            do { _ = try LiquidTemplate(source, syntaxMode: mode); Issue.record("Expected syntax error") }
            catch LiquidError.syntax(let message, let line, let column) {
                #expect(line == nil && column == nil)
                #expect(message == (source.hasPrefix("{%") ? "Unexpected character '&'" : "Unterminated string literal"))
            }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func finiteSourceAdmissionAndPartialCoordinatesStayLocal(mode: LiquidSyntaxMode) async throws {
        let source = "partial\n{{ x & }}"
        let error = #expect(throws: LiquidError.self) {
            try LiquidTemplate(source, syntaxMode: mode, limits: .init(sourceBytes: source.utf8.count - 1))
        }
        if case .limitExceeded("sourceBytes")? = error {} else { Issue.record("Source admission must precede diagnostics") }
        let engine = LiquidEngine()
        for recovering in [false, true] {
            do {
                if recovering { _ = try await engine.renderWithDiagnostics(template: "root\n\n{% render 'p' %}", templates: ["p": source], syntaxMode: mode) }
                else { _ = try await engine.render(template: "root\n\n{% render 'p' %}", templates: ["p": source], syntaxMode: mode) }
                Issue.record("Invalid partial was admitted")
            } catch LiquidError.syntax(let message, let line, let column) {
                #expect(message == "Unexpected character & in \"{{ x & }}\"")
                #expect(line == 2 && column == 1) // Partial-local, never flattened to the root.
            }
        }
        let valid = try LiquidTemplate("{% raw %}{{ x & }}{% endraw %}", syntaxMode: mode)
        #expect(try await engine.render(valid) == "{{ x & }}")
        #expect(try await engine.renderWithDiagnostics(valid).diagnostics.isEmpty)
    }

    @Test func cancellationAtDiagnosticProviderEntryPreservesReuse() async throws {
        let snapshot = DiagnosticSourceSnapshot(admittedUTF8: Array("{{ x & }}".utf8), identity: .anonymous)
        let worker = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let frame = DiagnosticSourceFrame(construct: 0..<9, markup: 2..<7, anchor: 0, presentation: .outputMarkup, header: nil, headerSpelling: nil)
            return try snapshot.unexpectedCharacter("&", at: 5, frame: frame)
        }
        await #expect(throws: CancellationError.self) { try await worker.value }
        #expect(try snapshot.position(at: 0) == .init(line: 1, column: 1))
        let healthy = try LiquidTemplate("healthy")
        #expect(try await LiquidEngine().render(healthy) == "healthy")
    }

    @Test func concurrentRendersKeepDiagnosticOriginsInvocationOwned() async throws {
        let engine = LiquidEngine()
        let healthy = try LiquidTemplate("{{ value }}")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<24 {
                group.addTask {
                    let prefix = String(repeating: "\n", count: index)
                    do { _ = try await engine.renderWithDiagnostics(template: prefix + "{{ x & }}"); Issue.record("Expected syntax failure") }
                    catch LiquidError.syntax(let message, let line, let column) {
                        #expect(message == "Unexpected character & in \"{{ x & }}\"")
                        #expect(line == index + 1 && column == 1)
                    }
                    #expect(try await engine.render(healthy, context: ["value": .integer(index)]) == String(index))
                }
            }
            try await group.waitForAll()
        }
    }
}
