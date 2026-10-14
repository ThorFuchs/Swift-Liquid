// SPDX-License-Identifier: Apache-2.0
// Upstream date inputs and their source are BSD-2-Clause; see Licenses/RubyDate.
import Foundation
import Testing
@testable import Liquid

private struct DateCase: Sendable, CustomTestStringConvertible {
    let object: LiquidObject
    var testDescription: String { string("name") ?? "Unnamed date case" }
    func string(_ key: String) -> String? {
        if case .string(let value) = object[key] { return value }; return nil
    }
}

private enum DateCases {
    static func load(_ name: String) throws -> [DateCase] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              case .object(let root) = try LiquidValue(json: String(contentsOf: url, encoding: .utf8)),
              case .array(let cases) = root["tests"] else { throw CocoaError(.fileReadCorruptFile) }
        return try cases.map { value in
            guard case .object(let object) = value else { throw CocoaError(.fileReadCorruptFile) }
            return DateCase(object: object)
        }
    }
    static let grammar: Result<[DateCase], Error> = Result { try load("ruby_date_cases") }
    static let filters: Result<[DateCase], Error> = Result { try load("date_filter_cases") }
}

@Test func dateFixtureIntegrity() throws {
    #expect(try DateCases.grammar.get().count == 337)
    #expect(try DateCases.filters.get().count == 376)
}

@Test("Ruby date grammar", arguments: (try? DateCases.grammar.get()) ?? [])
private func rubyDateGrammar(_ fixture: DateCase) throws {
    var parser = try RubyDateParser(try #require(fixture.string("input")), completeYear: fixture.object["completeYear"] == true)
    let fields = try parser.parse()
    var actual: [String: LiquidValue] = [:]
    let numbers: [(String, Int?)] = [("year", fields.year), ("mon", fields.month), ("mday", fields.day), ("yday", fields.ordinal), ("hour", fields.hour), ("min", fields.minute), ("sec", fields.second)]
    for (key, value) in numbers { if let value { actual[key] = .integer(value) } }
    if let zone = fields.zone { actual["zone"] = .string(zone) }
    if var fraction = fields.fraction {
        while fraction.last == "0" { fraction.removeLast() }
        actual["fraction"] = .string(fraction)
    }
    guard case .object(let expected) = fixture.object["fields"] else { Issue.record("Missing expected date fields"); return }
    #expect(Set(actual.keys) == Set(expected.entries.map(\.key)))
    for entry in expected.entries { #expect(actual[entry.key] == entry.value, "Field \(entry.key)") }
}

@Test("Public date parsing", arguments: (try? DateCases.filters.get()) ?? [])
private func publicDateParsing(_ fixture: DateCase) async throws {
    guard case .integer(let seconds) = fixture.object["referenceTime"], case .object(let data) = fixture.object["data"] else { Issue.record("Missing date context or base clock"); return }
    let engine = LiquidEngine(referenceTime: Date(timeIntervalSince1970: Double(seconds)))
    let source = try #require(fixture.string("template"))
    if fixture.object["outsideYearDomain"] == true {
        let error = await #expect(throws: LiquidError.self) { try await engine.render(template: source, context: data, syntaxMode: .strict) }
        guard case .invalidValue? = error else { Issue.record("Expected an explicit supported-year failure"); return }
    } else {
        let result = try await engine.renderWithDiagnostics(template: source, context: data, syntaxMode: .strict)
        #expect(result.diagnostics.isEmpty)
        let expected = try #require(fixture.string("result"))
        #expect(result.output.utf8.elementsEqual(expected.utf8), "Actual: \(result.output.debugDescription); expected: \(expected.debugDescription)")
        let direct = try await engine.render(template: source, context: data, syntaxMode: .strict)
        #expect(direct.utf8.elementsEqual(expected.utf8))
    }
}
