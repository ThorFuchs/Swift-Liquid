// SPDX-License-Identifier: Apache-2.0
// Fixture data is MIT licensed; see Fixtures/LICENSE.
import Foundation
import Testing
import Liquid

private struct GoldenCase: Sendable, CustomTestStringConvertible {
    let object: LiquidObject
    var testDescription: String { string("name") ?? "Unnamed fixture" }
    func string(_ key: String) -> String? {
        guard case .string(let value) = object[key] else { return nil }
        return value
    }
}

private enum GoldenFixtures {
    static let loaded: Result<[GoldenCase], Error> = Result {
        guard let url = Bundle.module.url(forResource: "golden_liquid", withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let document = try LiquidValue(json: String(contentsOf: url, encoding: .utf8))
        guard case .object(let root) = document, case .array(let cases) = root["tests"] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try cases.map { value in
            guard case .object(let object) = value else { throw CocoaError(.fileReadCorruptFile) }
            return GoldenCase(object: object)
        }
    }
    static var cases: [GoldenCase] { (try? loaded.get()) ?? [] }
}

private enum CompatibilityProbes {
    static let loaded: Result<[GoldenCase], Error> = Result {
        guard let url = Bundle.module.url(forResource: "compatibility_probes", withExtension: "json", subdirectory: "Fixtures") else { throw CocoaError(.fileNoSuchFile) }
        let document = try LiquidValue(json: String(contentsOf: url, encoding: .utf8))
        guard case .object(let root) = document, case .array(let cases) = root["tests"] else { throw CocoaError(.fileReadCorruptFile) }
        return try cases.map { value in
            guard case .object(let object) = value else { throw CocoaError(.fileReadCorruptFile) }
            return GoldenCase(object: object)
        }
    }
    static var cases: [GoldenCase] { (try? loaded.get()) ?? [] }
}

@Test("Compatibility probe integrity")
func compatibilityProbeIntegrity() throws {
    #expect(try CompatibilityProbes.loaded.get().count == 63)
}

@Test("Native compatibility probes", arguments: CompatibilityProbes.cases)
private func nativeCompatibilityProbes(_ fixture: GoldenCase) async throws {
    try await goldenLiquid(fixture)
}

@Test("Golden fixture integrity")
func goldenFixtureIntegrity() throws {
    #expect(try GoldenFixtures.loaded.get().count == 1098)
}

@Test("Golden Liquid", arguments: GoldenFixtures.cases)
private func goldenLiquid(_ fixture: GoldenCase) async throws {
    let source = try #require(fixture.string("template"))
    let context: LiquidObject
    if case .object(let object) = fixture.object["data"] { context = object }
    else { context = [:] }
    var templates: [String: String] = [:]
    let syntaxMode: LiquidSyntaxMode
    if case .array(let tags) = fixture.object["tags"], tags.contains("strict2") { syntaxMode = .strict2 }
    else if case .array(let tags) = fixture.object["tags"], tags.contains("strict") { syntaxMode = .strict }
    else { syntaxMode = .lax }
    if case .object(let object) = fixture.object["templates"] {
        for entry in object.entries {
            if case .string(let source) = entry.value { templates[entry.key] = source }
        }
    }
    if fixture.object["invalid"] == .bool(true) {
        do {
            _ = try await LiquidEngine().render(template: source, context: context, templates: templates, syntaxMode: syntaxMode)
            Issue.record("Expected an error: \(fixture.testDescription)")
        } catch is CancellationError {
            throw CancellationError()
        } catch { }
    } else {
        let actual = try await LiquidEngine().render(template: source, context: context, templates: templates, syntaxMode: syntaxMode)
        if let expected = fixture.string("result") { #expect(actual == expected, "Actual: \(actual.debugDescription); expected: \(expected.debugDescription)") }
        else if case .array(let results) = fixture.object["results"] { #expect(results.contains(.string(actual))) }
        else { Issue.record("Fixture has no expected output") }
    }
}
