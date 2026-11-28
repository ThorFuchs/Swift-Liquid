// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

private struct ReviewedRawMatrix: Decodable, Sendable {
    let cases: [ReviewedRawCase]
}
private struct ReviewedRawCase: Decodable, Sendable {
    let name: String
    let mode: String
    let sourceBytes: [UInt8]
    let phase: String
    let outcome: String
    let outputBytes: [UInt8]?
    let errorClass: String?
    let message: String?
    let line: Int?
    var observation: ReviewedReference {
        .init(phase: phase, outcome: outcome, outputBytes: outputBytes, errorClass: errorClass, message: message, line: line)
    }
}
private struct ReviewedReference: Codable, Sendable, Equatable {
    let phase: String
    let outcome: String
    let outputBytes: [UInt8]?
    let errorClass: String?
    let message: String?
    let line: Int?
}
private struct ReviewedSwift: Decodable, Sendable {
    let phase: String
    let outcome: String
    let outputBytes: [UInt8]?
    let message: String?
    let line: Int?
    let column: Int?
}
private struct ReviewedPolicy: Decodable, Sendable {
    let schemaVersion: Int
    let status: String
    let rows: [ReviewedPolicyRow]
}
private struct ReviewedPolicyRow: Decodable, Sendable {
    let profile: String
    let id: String
    let context: String
    let sourceBytes: [UInt8]
    let reference: ReviewedReference
    let swift: ReviewedSwift
    let disposition: String
    var identity: String { profile + "/" + id }
}
private final class ReviewedCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Int] = [:]
    func hit(_ name: String) { lock.withLock { storage[name, default: 0] += 1 } }
    func snapshot() -> [String: Int] { lock.withLock { storage } }
}

@Suite("Reviewed narrow quoted-literal profile")
struct QuotedLiteralReviewedTests {
    private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func hostJSONRawAndExplicitEscapingRemainIndependent(mode: LiquidSyntaxMode) async throws {
        let host = try LiquidValue(json: #""a\\nb\nc""#)
        let source = #"{{ value }}|{% raw %}{{ host }}\n{% endraw %}|{{ '<&>' | escape }}|{{ 'a b' | url_encode }}"#
        let expected = "a\\nb\nc|" + #"{{ host }}\n|&lt;&amp;&gt;|a+b"#
        #expect(try await LiquidEngine().render(template: source, context: ["value": host], syntaxMode: mode) == expected)
    }

    @Test(arguments: ["original", "expanded"], [LiquidSyntaxMode.lax, .strict, .strict2])
    func allRawAndReviewedObservations(profile: String, mode: LiquidSyntaxMode) async throws {
        let filename = profile == "original" ? "QuotedStringReferenceCases" : "LaxQuoteRecoveryCases"
        let raw = try load(filename, as: ReviewedRawMatrix.self)
        let policy = try load("SL21-02A4-ReviewedPolicy", as: ReviewedPolicy.self)
        #expect(policy.schemaVersion == 1 && policy.status == "APPROVED_NARROW_SCOPE")
        let rows = policy.rows.filter { $0.profile == profile && $0.id.hasPrefix(mode.rawValue + "/") }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byID.count == rows.count)
        var seen = Set<String>()
        let cases = raw.cases.filter { $0.mode == mode.rawValue }
        #expect(cases.count == (profile == "original" ? 32 : 25))
        let counts = ReviewedCounters()
        let host = LiquidHostObject("h", properties: [LiquidHostProperty("v") { counts.hit("host"); return "host" }])
        let filter = LiquidFilter("review_probe") { _, _, _ in counts.hit("filter"); return "host" }
        let engine = try LiquidEngine(filters: [filter], strictFilters: true)
        let resolver = LiquidTemplateNameResolver(select: { value in counts.hit("resolve"); return value }, missing: { _ in "missing" })
        let context: LiquidObject = profile == "original" ? [:] : ["unterminated": "FOUND", "a": ["n": "NESTED"], "value": "ok"]
        for item in cases {
            let id = mode.rawValue + "/" + item.name
            #expect(seen.insert(id).inserted, "duplicate \(profile)/\(id)")
            let reviewed = byID[id]
            if let reviewed {
                #expect(reviewed.sourceBytes == item.sourceBytes && reviewed.reference == item.observation, "stale policy \(profile)/\(id)")
                #expect(reviewed.context == (profile == "original" ? "empty" : "fixed_lookup_context"))
                #expect(["APPROVED_INERT_FRAMING", "DEFERRED_RECOVERY"].contains(reviewed.disposition))
                if reviewed.disposition == "DEFERRED_RECOVERY" {
                    #expect(reviewed.swift.phase == "parse" && reviewed.swift.outcome == "syntax-error")
                    #expect(item.outcome != "parse-error", "reviewed case is no longer a raw difference")
                } else {
                    #expect(profile == "expanded" && reviewed.swift.phase == "render" && reviewed.swift.outcome == "output")
                    #expect(item.outcome != "output" || item.outputBytes != reviewed.swift.outputBytes, "approved divergence is no longer different")
                }
            }
            let source = try #require(String(bytes: item.sourceBytes, encoding: .utf8))
            let parsed: LiquidTemplate
            do {
                parsed = try LiquidTemplate(source, syntaxMode: mode)
            } catch LiquidError.syntax(let message, let line, let column) {
                if let reviewed {
                    #expect(reviewed.disposition == "DEFERRED_RECOVERY")
                    #expect(message == reviewed.swift.message && line == reviewed.swift.line && column == reviewed.swift.column, "changed syntax \(profile)/\(id)")
                    do { _ = try engine.inspect(template: source, syntaxMode: mode); Issue.record("inspect accepted deferred \(id)") }
                    catch LiquidError.syntax { } catch { Issue.record("inspect operational error \(id): \(error)") }
                    do { _ = try engine.inspectDependencies(template: source, templates: ["p": "P"], syntaxMode: mode); Issue.record("dependencies accepted deferred \(id)") }
                    catch LiquidError.syntax { } catch { Issue.record("dependency operational error \(id): \(error)") }
                } else {
                    #expect(item.phase == "parse" && item.outcome == "parse-error", "unexpected parse error \(profile)/\(id)")
                }
                #expect(counts.snapshot().isEmpty)
                print("QUOTED_REVIEW \(profile) \(id) \(reviewed?.disposition ?? "RAW_MATCH") syntax")
                continue
            } catch {
                Issue.record("operational parse error \(profile)/\(id): \(error)")
                continue
            }
            if reviewed?.disposition == "DEFERRED_RECOVERY" {
                Issue.record("deferred source parsed unexpectedly \(profile)/\(id)")
                continue
            }
            if reviewed == nil && item.outcome != "output" {
                Issue.record("reference expected non-output \(profile)/\(id)")
                continue
            }
            do {
                if reviewed?.disposition == "APPROVED_INERT_FRAMING" {
                    let inspection = try engine.inspect(parsed)
                    #expect(inspection.variableRoots.isEmpty && inspection.filterNames.isEmpty && inspection.literalPartialNames.isEmpty)
                    let dependencies = try engine.inspectDependencies(template: source, templates: ["p": "P"], syntaxMode: mode)
                    #expect(dependencies.edges.isEmpty)
                }
                let result = try await engine.renderWithDiagnostics(parsed, context: context, hostObjects: [host], partialSources: ["p": "P"], resolver: resolver)
                let expected = reviewed?.swift.outputBytes ?? item.outputBytes
                #expect(Array(result.output.utf8) == expected && result.diagnostics.isEmpty, "changed output \(profile)/\(id)")
                #expect(counts.snapshot().isEmpty, "unexpected host capability \(profile)/\(id)")
                print("QUOTED_REVIEW \(profile) \(id) \(reviewed?.disposition ?? "RAW_MATCH") output=\(Array(result.output.utf8))")
            } catch {
                Issue.record("unexpected render or operational error \(profile)/\(id): \(error)")
            }
        }
        #expect(Set(byID.keys).isSubset(of: seen), "missing reviewed case")
    }
}
