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

private enum RecoveredErrors {
    static let loaded: Result<LiquidObject, Error> = Result {
        guard let url = Bundle.module.url(forResource: "recovered_errors", withExtension: "json", subdirectory: "Fixtures"),
              case .object(let root) = try LiquidValue(json: String(contentsOf: url, encoding: .utf8)),
              case .object(let tests) = root["tests"] else { throw CocoaError(.fileReadCorruptFile) }
        return tests
    }
}

@Test("Compatibility probe integrity")
func compatibilityProbeIntegrity() throws {
    #expect(try CompatibilityProbes.loaded.get().count == 221)
}

@Test("Native compatibility probes", arguments: CompatibilityProbes.cases)
private func nativeCompatibilityProbes(_ fixture: GoldenCase) async throws {
    try await goldenLiquid(fixture)
}

@Test("Golden fixture integrity")
func goldenFixtureIntegrity() throws {
    #expect(try GoldenFixtures.loaded.get().count == 1098)
    #expect(try RecoveredErrors.loaded.get().entries.count == 1)
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
        } catch let error as LiquidError {
            switch error {
            case .syntax, .rendering: break
            case .limitExceeded, .invalidValue:
                Issue.record("Operational failure cannot qualify an invalid fixture: \(error)")
            }
        } catch {
            Issue.record("Expected a Liquid language error, received \(error)")
        }
    } else {
        let result = try await LiquidEngine().renderWithDiagnostics(template: source, context: context, templates: templates, syntaxMode: syntaxMode)
        let actual = result.output
        let expectedErrors = try RecoveredErrors.loaded.get()[fixture.string("name") ?? ""] ?? fixture.object["diagnostics"] ?? .array([])
        let observedErrors = LiquidValue.array(result.diagnostics.map { diagnostic in
            var entries: [LiquidObject.Entry] = [
                .init("message", .string(diagnostic.message)),
                .init("line", diagnostic.line.map(LiquidValue.integer) ?? .null)
            ]
            if let name = diagnostic.templateName { entries.append(.init("templateName", .string(name))) }
            return .object(LiquidObject(entries))
        })
        #expect(observedErrors == expectedErrors)
        if case .array(let errors) = expectedErrors, errors.isEmpty {
            let direct = try await LiquidEngine().render(template: source, context: context, templates: templates, syntaxMode: syntaxMode)
            #expect(direct.utf8.elementsEqual(actual.utf8), "Raising and diagnostic render paths disagree")
        } else {
            let failure = await #expect(throws: LiquidError.self) {
                try await LiquidEngine().render(template: source, context: context, templates: templates, syntaxMode: syntaxMode)
            }
            guard case .rendering? = failure else { Issue.record("Expected a runtime failure from the raising API"); return }
        }
        if let expected = fixture.string("result") { #expect(actual.utf8.elementsEqual(expected.utf8), "Actual: \(actual.debugDescription); expected: \(expected.debugDescription)") }
        else if case .array(let results) = fixture.object["results"] {
            #expect(results.contains { value in
                if case .string(let expected) = value { return actual.utf8.elementsEqual(expected.utf8) }
                return false
            })
        }
        else { Issue.record("Fixture has no expected output") }
    }
}
