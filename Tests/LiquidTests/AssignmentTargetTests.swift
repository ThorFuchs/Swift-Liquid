// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

private struct AssignmentCase: Decodable, Sendable {
    let name: String
    let original: Bool
    let source: String
    let mode: String
    let parsed: Bool
    let output: String?
}

private func assignmentCases(original: Bool) throws -> [AssignmentCase] {
    let url = try #require(Bundle.module.url(forResource: "AssignmentTargetCases", withExtension: "json", subdirectory: "Fixtures"))
    let rows = try JSONDecoder().decode([AssignmentCase].self, from: Data(contentsOf: url))
    #expect(rows.count == 141)
    return rows.filter { $0.original == original }
}

@Suite("Assignment target admission", .timeLimit(.minutes(1)))
struct AssignmentTargetTests {
    // Exact original twenty identities, each expanded to all three public modes.
    @Test(arguments: 0..<60)
    func originalTwentyRejectBeforeRendering(index: Int) async throws {
        let row = try assignmentCases(original: true)[index]
        let mode = try #require(LiquidSyntaxMode(rawValue: row.mode))
        #expect(!row.parsed)
        do {
            _ = try LiquidTemplate(row.source, syntaxMode: mode)
            Issue.record("Accepted original assignment: \(row.name)")
        } catch LiquidError.syntax(let message, _, _) {
            #expect(message.contains("Syntax Error in 'assign'"))
        }
        for recovering in [false, true] {
            do {
                let engine = LiquidEngine()
                if recovering { _ = try await engine.renderWithDiagnostics(template: row.source, syntaxMode: mode) }
                else { _ = try await engine.render(template: row.source, syntaxMode: mode) }
                Issue.record("Rendering accepted malformed assignment: \(row.name)")
            } catch LiquidError.syntax { }
        }
    }

    // Fresh, separately attributed 27-target x 3-mode reference controls, including
    // the R2 unanchored-prefix, dotted, numeric, hyphen and Unicode boundaries.
    @Test(arguments: 0..<81)
    func supplementaryTargetsMatchPinnedRuby(index: Int) async throws {
        let row = try assignmentCases(original: false)[index]
        let mode = try #require(LiquidSyntaxMode(rawValue: row.mode))
        if row.parsed {
            let parsed = try LiquidTemplate(row.source, syntaxMode: mode)
            let engine = LiquidEngine()
            let expected = try #require(row.output)
            #expect(try await engine.render(template: row.source, context: ["x": "V"], syntaxMode: mode) == expected)
            #expect(try await engine.render(parsed, context: ["x": "V"]) == expected)
            let recovered = try await engine.renderWithDiagnostics(parsed, context: ["x": "V"])
            #expect(recovered.output == expected && recovered.diagnostics.isEmpty)
        } else {
            do {
                _ = try LiquidTemplate(row.source, syntaxMode: mode)
                Issue.record("Accepted reference rejection: \(row.name) / \(row.mode)")
            } catch LiquidError.syntax { }
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func assignmentBoundariesPreserveOpaqueTextAndSource(mode: LiquidSyntaxMode) async throws {
        let engine = LiquidEngine()
        for source in ["{% raw %}{% assign & = x %}{% endraw %}", "{% comment %}{% assign & = x %}{% endcomment %}"] {
            let expected = source.contains("raw") ? "{% assign & = x %}" : ""
            #expect(try await engine.render(template: source, syntaxMode: mode) == expected)
        }
        let source = "α\n{%- assign @foo = 'V' -%}{{ foo }}"
        let parsed = try LiquidTemplate(source, syntaxMode: mode)
        #expect(parsed.source == source)
        #expect(try await engine.render(parsed) == "αV")
        #expect(try await engine.render(template: "{% liquid\nassign foo = 'V'\necho foo\n%}", syntaxMode: mode) == "V")
    }

    @Test func longTargetsRetainSourceLimitsAndCancellation() async throws {
        let source = "{% assign " + String(repeating: "a", count: 8192) + " = 'V' %}"
        let exact = LiquidEngine(limits: .init(sourceBytes: source.utf8.count))
        #expect(try await exact.render(template: source, syntaxMode: .strict2) == "")
        let bounded = LiquidEngine(limits: .init(sourceBytes: source.utf8.count - 1))
        let error = await #expect(throws: LiquidError.self) {
            try await bounded.renderWithDiagnostics(template: source, syntaxMode: .strict2)
        }
        if case .limitExceeded("sourceBytes")? = error { }
        else { Issue.record("Source limit must remain operational") }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try LiquidTemplate(source, syntaxMode: .strict2)
        }
        do { _ = try await cancelled.value; Issue.record("Cancelled parsing succeeded") }
        catch is CancellationError { }
        #expect(try await exact.render(template: source, syntaxMode: .strict2) == "")
    }
}
