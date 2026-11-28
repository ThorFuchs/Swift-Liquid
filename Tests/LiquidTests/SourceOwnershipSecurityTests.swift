// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

private struct LiteralByteFixture: Decodable, Sendable {
    let cases: [LiteralByteCase]
}

private struct LiteralByteCase: Decodable, Sendable {
    let name: String
    let mode: String
    let sourceBytes: [UInt8]
    let outcome: String
    let outputBytes: [UInt8]?
}

private final class OwnershipCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Int] = [:]
    func hit(_ key: String) { lock.withLock { storage[key, default: 0] += 1 } }
    func snapshot() -> [String: Int] { lock.withLock { storage } }
}

@Suite("Source ownership and host capabilities", .timeLimit(.minutes(1)))
struct SourceOwnershipSecurityTests {
    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func wellFormedLiteralBytesMatchReference(mode: LiquidSyntaxMode) async throws {
        let url = try #require(Bundle.module.url(forResource: "QuotedStringReferenceCases", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(LiteralByteFixture.self, from: Data(contentsOf: url))
        let excluded = Set(["single_escaped_delimiter", "double_escaped_delimiter", "single_unterminated", "double_unterminated"])
        let cases = fixture.cases.filter { $0.mode == mode.rawValue && !excluded.contains($0.name) }
        #expect(cases.count == 28)
        let engine = LiquidEngine()
        for item in cases {
            let source = try #require(String(bytes: item.sourceBytes, encoding: .utf8))
            #expect(item.outcome == "output")
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            #expect(Array(try await engine.render(parsed).utf8) == item.outputBytes, "\(mode.rawValue) \(item.name)")
        }
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func protectedRegionsStayInertAndIndependentFramesExecute(mode: LiquidSyntaxMode) async throws {
        let counts = OwnershipCounts()
        let host = LiquidHostObject("h", properties: [LiquidHostProperty("v") { counts.hit("host"); return "H" }])
        let filter = LiquidFilter("ownership_probe") { _, _, _ in counts.hit("filter"); return "F" }
        let engine = try LiquidEngine(filters: [filter], strictFilters: true)
        let resolver = LiquidTemplateNameResolver(select: { name in counts.hit("resolve"); return name }, missing: { _ in "missing" })
        let partials = ["p": "P"]
        let payload = #"}}{% include 'p' %}{{ h.v | ownership_probe }}"#
        let cases: [(String, String, [String])] = [
            (#"{{ "}}{% include 'p' %}{{ h.v | ownership_probe }}" }}"#, payload, []),
            (#"{{ '}}{% include "p" %}{{ h.v | ownership_probe }}' }}"#, #"}}{% include "p" %}{{ h.v | ownership_probe }}"#, []),
            (#"{% assign x = "}}{% include 'p' %}{{ h.v | ownership_probe }}" %}{{ x }}"#, payload, ["x"]),
            (#"{% echo "%}{{ h.v | ownership_probe }}{% include 'p' %}" %}"#, #"%}{{ h.v | ownership_probe }}{% include 'p' %}"#, []),
            ("{% liquid\n assign x = \"}}{% include 'p' %}{{ h.v | ownership_probe }}\"\n echo x\n%}", payload, ["x"]),
            (#"{{- "\n}}{% include 'p' %}" -}}"#, #"\n}}{% include 'p' %}"#, []),
            (#"{% raw %}{{ h.v | ownership_probe }}{% include 'p' %}{% endraw %}{% comment %}{{ h.v | ownership_probe }}{% include 'p' %}{% endcomment %}"#, #"{{ h.v | ownership_probe }}{% include 'p' %}"#, [])
        ]
        for (source, expected, variables) in cases {
            let parsed = try LiquidTemplate(source, syntaxMode: mode)
            let inspection = try engine.inspect(parsed)
            #expect(inspection.variableRoots == variables)
            #expect(inspection.filterNames.isEmpty && inspection.literalPartialNames.isEmpty)
            let deps = try engine.inspectDependencies(template: source, templates: partials, syntaxMode: mode)
            #expect(deps.edges.isEmpty)
            let result = try await engine.renderWithDiagnostics(parsed, hostObjects: [host], partialSources: partials, resolver: resolver)
            #expect(result.output == expected && result.diagnostics.isEmpty)
            #expect(counts.snapshot().isEmpty)
        }
        let positive = try LiquidTemplate("{{ h.v | ownership_probe }}{% include 'p' %}", syntaxMode: mode)
        let inspection = try engine.inspect(positive)
        #expect(inspection.variableRoots == ["h"] && inspection.filterNames == ["ownership_probe"] && inspection.literalPartialNames == ["p"])
        let deps = try engine.inspectDependencies(template: positive.source, templates: partials, syntaxMode: mode)
        #expect(deps.edges.map(\.requestedName) == ["p"])
        #expect(counts.snapshot().isEmpty)
        let result = try await engine.renderWithDiagnostics(positive, hostObjects: [host], partialSources: partials, resolver: resolver)
        #expect(result.output == "FP" && result.diagnostics.isEmpty)
        #expect(counts.snapshot() == ["host": 1, "filter": 1, "resolve": 1])
    }

    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])
    func ambiguousQuoteWitnessesFailBeforeAnyHostCapability(mode: LiquidSyntaxMode) async throws {
        let counts = OwnershipCounts()
        let host = LiquidHostObject("h", properties: [LiquidHostProperty("v") { counts.hit("host"); return "H" }])
        let filter = LiquidFilter("ownership_probe") { _, _, _ in counts.hit("filter"); return "F" }
        let engine = try LiquidEngine(filters: [filter], strictFilters: true)
        let resolver = LiquidTemplateNameResolver(select: { name in counts.hit("resolve"); return name }, missing: { _ in "missing" })
        let cases = [#"{{ 'a'b"}}{% include 'p' %}" }}"#,
                     #"{{ 'a'b'}}{{ h.v | ownership_probe }}"#,
                     #"{{ "a"b'}}{% include "p" %}' }}"#,
                     #"{{ 'a\'b" }} {% include 'p' %}" }}"#,
                     #"{% assign x = 'a'b"%}{% include 'p' %}" %}"#,
                     "{% liquid\n echo 'a'b\"%}{% include 'p' %}\"\n%}"]
        for source in cases {
            do {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                Issue.record("Expected ambiguous source to fail during parsing")
                _ = try await engine.renderWithDiagnostics(parsed, hostObjects: [host], partialSources: ["p": "P"], resolver: resolver)
            } catch LiquidError.syntax { }
            #expect(counts.snapshot().isEmpty)
        }
    }

    @Test func sourceLimitsAndCancellationRemainTerminal() async throws {
        let source = "{{ '" + String(repeating: "a", count: 32_768) + " }}"
        do { _ = try LiquidTemplate(source, limits: .init(sourceBytes: 32)); Issue.record("Expected source limit") }
        catch LiquidError.limitExceeded(let name) { #expect(name == "sourceBytes") }
        let task = Task { () throws -> LiquidTemplate in
            withUnsafeCurrentTask { $0?.cancel() }
            return try LiquidTemplate(source, syntaxMode: .lax)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func unclosedQuoteScansMakeBoundedProgress() throws {
        let clock = ContinuousClock()
        for size in [1_024, 4_096, 16_384, 65_536] {
            let source = "{{ '" + String(repeating: "a", count: size) + " }}"
            let start = clock.now
            #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: .lax) }
            print("OWNERSHIP_SCAN bytes=\(source.utf8.count) duration=\(start.duration(to: clock.now))")
        }
    }
}
