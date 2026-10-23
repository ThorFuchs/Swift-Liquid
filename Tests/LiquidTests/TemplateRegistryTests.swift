// SPDX-License-Identifier: Apache-2.0
@testable import Liquid
import Testing

private typealias Registry = LiquidTemplateRegistry

private func expectCapacity(_ capacity: Registry.Capacity, _ work: () throws -> Void) {
    do { try work(); Issue.record("Expected registry capacity \(capacity.rawValue)") }
    catch Registry.AdmissionError.limitExceeded(let actual) { #expect(actual.rawValue == capacity.rawValue) }
    catch { Issue.record("Unexpected error: \(error)") }
}

private func raw(_ match: Registry.Resolved?) -> String? {
    guard let match, case .raw(let source) = match.content else { return nil }
    return source
}

@Suite struct TemplateRegistryTests {
    @Test func emptyAndZeroProfiles() throws {
        let empty = try Registry([])
        #expect(empty.count == 0 && empty.entries.isEmpty)
        #expect(try empty.resolve("missing") == nil)
        #expect(Registry.Limits.default.entryCount == 4_096)
        #expect(Registry.Limits.default.totalNameUTF8Bytes == 262_144)
        #expect(Registry.Limits.default.nameUTF8Bytes == 1_024)
        let zero = Registry.Limits(entryCount: 0, totalNameUTF8Bytes: 0, nameUTF8Bytes: 0)
        #expect(try Registry([], limits: zero).resolve("") == nil)
        expectCapacity(.entryCount) { _ = try Registry([.init("", .raw(""))], limits: zero) }
        let blank = try Registry([.init("", .raw("blank"))],
                                 limits: .init(entryCount: 1, totalNameUTF8Bytes: 0, nameUTF8Bytes: 0))
        #expect(raw(try blank.resolve("")) == "blank")
        expectCapacity(.nameUTF8Bytes) { _ = try blank.resolve("a") }
        expectCapacity(.totalNameUTF8Bytes) {
            _ = try Registry([.init("a", .raw(""))], limits: .init(totalNameUTF8Bytes: 0))
        }
    }

    @Test(arguments: [0, 1, 2])
    func negativeLimitsPrecedeEntryChecks(component: Int) {
        let limits = Registry.Limits(entryCount: component == 0 ? -1 : 0,
                                     totalNameUTF8Bytes: component == 1 ? -1 : 0,
                                     nameUTF8Bytes: component == 2 ? -1 : 0)
        do { _ = try Registry([.init("long", .raw(""))], limits: limits); Issue.record("Negative accepted") }
        catch Registry.AdmissionError.invalidLimits {}
        catch { Issue.record("Wrong error: \(error)") }
    }

    @Test(arguments: ["é", "e\u{301}", "K", "\u{212A}"])
    func duplicateBytesAndPrecedence(name: String) {
        do {
            _ = try Registry([.init(name, .raw("first")), .init(name, .raw("second"))])
            Issue.record("Duplicate accepted")
        } catch Registry.AdmissionError.duplicateName(let actual) {
            #expect(actual.utf8.elementsEqual(name.utf8))
        } catch { Issue.record("Wrong error: \(error)") }
        let entries: [Registry.Entry] = [.init(name, .raw("1")), .init(name, .raw("2"))]
        expectCapacity(.entryCount) { _ = try Registry(entries, limits: .init(entryCount: 1, nameUTF8Bytes: 0)) }
        expectCapacity(.nameUTF8Bytes) {
            _ = try Registry(entries, limits: .init(totalNameUTF8Bytes: 0, nameUTF8Bytes: 0))
        }
        expectCapacity(.totalNameUTF8Bytes) {
            _ = try Registry(entries, limits: .init(totalNameUTF8Bytes: name.utf8.count))
        }
    }

    @Test(arguments: [false, true])
    func canonicalSiblingsStayDistinct(kelvin: Bool) throws {
        let a = kelvin ? "K" : "é"
        let b = kelvin ? "\u{212A}" : "e\u{301}"
        #expect(a == b && !a.utf8.elementsEqual(b.utf8))
        let registry = try Registry([.init(a, .raw("A")), .init(b, .raw("B"))])
        #expect(registry.count == 2)
        let first = try #require(try registry.resolve(a))
        let second = try #require(try registry.resolve(b))
        #expect(first.entryIndex == 0 && second.entryIndex == 1)
        #expect(first.name.utf8.elementsEqual(a.utf8))
        #expect(second.name.utf8.elementsEqual(b.utf8))
        #expect(raw(first) == "A" && raw(second) == "B")
        #expect(try Registry([.init(a, .raw("A"))]).resolve(b) == nil)
        #expect(try Registry([.init(b, .raw("B"))]).resolve(a) == nil)
    }

    @Test func exactBaseSuffixAndStoredSpelling() throws {
        let registry = try Registry([.init("x.liquid", .raw("suffix")), .init("x", .raw("base")),
                                     .init("x.liquid.liquid", .raw("double"))])
        #expect(raw(try registry.resolve("x")) == "base")
        #expect(raw(try registry.resolve("x.liquid")) == "suffix")
        let fallback = try #require(try Registry([.init("other", .raw("0")), .init("x.liquid", .raw("stored"))]).resolve("x"))
        #expect(fallback.entryIndex == 1 && fallback.name.utf8.elementsEqual("x.liquid".utf8))
        #expect(raw(fallback) == "stored")
        #expect(raw(try Registry([.init("x.liquid.liquid", .raw("double"))]).resolve("x.liquid")) == "double")
        let unicode = try Registry([.init("e\u{301}", .raw("wrong")), .init("é.liquid", .raw("right"))])
        #expect(raw(try unicode.resolve("é")) == "right")
        #expect(try Registry([.init("e\u{301}.liquid", .raw("wrong"))]).resolve("é") == nil)
    }

    @Test func orderedSnapshotsAndMixedContentDoNotParseRaw() throws {
        let parsed = try LiquidTemplate("{{ value }}", syntaxMode: .strict2)
        var input: [Registry.Entry] = [.init("z", .raw("{% if %}")), .init("é", .parsed(parsed))]
        let registry = try Registry(input)
        input[0] = .init("changed", .raw("replacement"))
        var output = registry.entries
        output.removeAll()
        let copy = registry
        #expect(copy.count == 2 && registry.entries[0].name == "z")
        #expect(raw(try copy.resolve("z")) == "{% if %}")
        #expect(try copy.resolve("changed") == nil)
        guard case .parsed(let retained) = try #require(try registry.resolve("é")).content else {
            Issue.record("Parsed content changed kind"); return
        }
        #expect(retained.source.utf8.elementsEqual(parsed.source.utf8))
        #expect(try LiquidEngine().inspect(retained) == LiquidEngine().inspect(parsed))
        // Huge/malformed raw source is intentionally not source-admitted or parsed here.
        let source = String(repeating: "x", count: 1_048_577)
        #expect(raw(try Registry([.init("huge", .raw(source))]).resolve("huge"))?.utf8.count == 1_048_577)
    }

    @Test func exactNameCountAndAggregateBoundaries() throws {
        for name in ["a", "é", "e\u{301}", "😀"] {
            let size = name.utf8.count
            let entry = Registry.Entry(name, .raw(""))
            #expect(try Registry([entry], limits: .init(entryCount: 1, totalNameUTF8Bytes: size,
                                                       nameUTF8Bytes: size)).count == 1)
            expectCapacity(.nameUTF8Bytes) {
                _ = try Registry([entry], limits: .init(nameUTF8Bytes: size - 1))
            }
            expectCapacity(.totalNameUTF8Bytes) {
                _ = try Registry([entry], limits: .init(totalNameUTF8Bytes: size - 1))
            }
        }
        let siblings: [Registry.Entry] = [.init("é", .raw("")), .init("e\u{301}", .raw("unused"))]
        #expect(try Registry(siblings, limits: .init(entryCount: 2, totalNameUTF8Bytes: 5)).count == 2)
        expectCapacity(.entryCount) { _ = try Registry(siblings, limits: .init(entryCount: 1)) }
        expectCapacity(.totalNameUTF8Bytes) { _ = try Registry(siblings, limits: .init(totalNameUTF8Bytes: 4)) }
    }

    @Test func lookupBoundsAndIntMaxDoNotOverflow() throws {
        let maximum = Registry.Limits(entryCount: .max, totalNameUTF8Bytes: .max, nameUTF8Bytes: .max)
        let registry = try Registry([.init("", .raw("empty")), .init("x.liquid", .raw("suffix"))], limits: maximum)
        #expect(raw(try registry.resolve("")) == "empty")
        #expect(raw(try registry.resolve("x")) == "suffix")
        #expect(try registry.resolve("missing") == nil)
        let bounded = try Registry([], limits: .init(nameUTF8Bytes: 3))
        #expect(try bounded.resolve("abc") == nil)
        expectCapacity(.nameUTF8Bytes) { _ = try bounded.resolve("abcd") }
        let huge = String(repeating: "a", count: 1_048_576)
        expectCapacity(.nameUTF8Bytes) { _ = try Registry([]).resolve(huge) }
        expectCapacity(.nameUTF8Bytes) { _ = try Registry([.init(huge, .raw(""))]) }
        // Suffix length is seven; an impossible candidate is a miss, not overflow/capacity.
        #expect(try Registry([], limits: .init(nameUTF8Bytes: 0)).resolve("") == nil)
        #expect(try Registry([], limits: .init(nameUTF8Bytes: 7)).resolve("a") == nil)
    }

    @Test func boundedScanStopsAtFirstExcessByte() throws {
        let visits = RegistryVisits()
        let bytes = CountingRegistryBytes(count: 1_048_576, visits: visits)
        expectCapacity(.nameUTF8Bytes) { _ = try Registry.admittedNameBytes(bytes, maximum: 1_024) }
        #expect(visits.value == 1_025)
        #expect(try Registry.admittedNameBytes([UInt8](), maximum: .max) == 0)
        #expect(try Registry.admittedNameBytes([1, 2, 3], maximum: .max) == 3)
        #expect(try Registry.admittedNameBytes([1, 2, 3], maximum: .max - 1) == 3)
    }

    @Test func cancellationPrecedesAllAdmissionFailures() async throws {
        let registry = try Registry([])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            for action in 0..<3 {
                do {
                    switch action {
                    case 0: _ = try Registry([], limits: .init(entryCount: -1))
                    case 1: _ = try Registry([.init("x", .raw(""))], limits: .init(entryCount: 0))
                    default: _ = try registry.resolve(String(repeating: "x", count: 1_025))
                    }
                    Issue.record("Cancellation returned success")
                } catch is CancellationError {}
                catch { Issue.record("Cancellation hidden: \(error)") }
            }
        }
        await task.value
        #expect(try registry.resolve("healthy") == nil)
    }

    @Test func cancellationDuringAdmissionAndByteScanIsTerminal() async {
        let task = Task {
            let visits = RegistryVisits()
            let source = (0..<128).map { Registry.Entry("entry-\($0)", .raw("")) }
            let entries = CancellingRegistryEntries(source: source, cancelAt: 64, visits: visits)
            do {
                _ = try Registry.admittedIndex(entries, limits: .default)
                Issue.record("Partial admission returned an index")
            } catch is CancellationError {}
            catch { Issue.record("Wrong admission error: \(error)") }
            #expect(visits.value == 65)
        }
        await task.value
        let scanning = Task {
            let visits = RegistryVisits()
            let bytes = CountingRegistryBytes(count: 1_000_000, visits: visits, cancelAt: 65)
            do { _ = try Registry.admittedNameBytes(bytes, maximum: .max); Issue.record("Scan ignored cancellation") }
            catch is CancellationError {}
            catch { Issue.record("Wrong scan error: \(error)") }
            #expect(visits.value == 65)
        }
        await scanning.value
    }

    @Test func concurrentRendersAndRegistryResolutionShareOnlyImmutableInputs() async throws {
        let registry = try Registry([.init("é", .raw("A")), .init("e\u{301}", .raw("B")),
                                     .init("K", .raw("C")), .init("\u{212A}", .raw("D"))])
        let engine = LiquidEngine()
        let template = try LiquidTemplate("{{ marker }}")
        try await withThrowingTaskGroup(of: Int.self) { group in
            for taskIndex in 0..<16 {
                group.addTask {
                    for _ in 0..<32 {
                        let marker = "u1-task-\(taskIndex)"
                        #expect(try await engine.render(template, context: ["marker": .string(marker)]) == marker)
                        for (index, name) in ["é", "e\u{301}", "K", "\u{212A}"].enumerated() {
                            let resolved = try #require(try registry.resolve(name))
                            #expect(resolved.entryIndex == index && resolved.name.utf8.elementsEqual(name.utf8))
                        }
                    }
                    return 1
                }
            }
            var completed = 0
            for try await count in group { completed += count }
            #expect(completed == 16)
        }
    }

    @Test func legacyDictionaryAndEngineLookupAreUnchanged() async throws {
        let first = try LiquidTemplate("A")
        let last = try LiquidTemplate("B")
        var dictionary: [String: LiquidTemplate] = [:]
        dictionary["é"] = first
        dictionary["e\u{301}"] = last
        #expect(dictionary.count == 1)
        #expect(try await LiquidEngine().render(try LiquidTemplate("{% include 'é' %}"), templates: dictionary) == "B")
        let graph = try LiquidEngine().inspectDependencies(template: "{% include 'e\u{301}' %}", templates: ["é": "A"])
        #expect(graph.missingReferences.isEmpty && graph.nodes.count == 2)
        var kelvin: [String: Int] = [:]
        kelvin["K"] = 1; kelvin["\u{212A}"] = 2
        #expect(kelvin.count == 1 && kelvin["K"] == 2)
    }

    @Test func namesAreOpaqueIdentityNotPathsOrAuthorization() throws {
        let names = ["../relative", "/absolute", "a\\b", "a\0b", "%2e%2e", "Case", "case"]
        let registry = try Registry(names.map { .init($0, .raw("{% broken %}")) })
        for (index, name) in names.enumerated() {
            let match = try #require(try registry.resolve(name))
            #expect(match.entryIndex == index && match.name.utf8.elementsEqual(name.utf8))
        }
        #expect(try registry.resolve("relative") == nil)
        #expect(try registry.resolve("CASE") == nil)
    }
}

private struct CountingRegistryBytes: Sequence {
    let count: Int
    let visits: RegistryVisits
    var cancelAt: Int? = nil
    func makeIterator() -> Iterator { Iterator(count: count, visits: visits, cancelAt: cancelAt) }
    struct Iterator: IteratorProtocol {
        var count: Int
        let visits: RegistryVisits
        let cancelAt: Int?
        mutating func next() -> UInt8? {
            guard count > 0 else { return nil }
            count -= 1
            let n = visits.next()
            if n == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
            return 65
        }
    }
}

private struct CancellingRegistryEntries: RandomAccessCollection {
    let source: [Registry.Entry]
    let cancelAt: Int
    let visits: RegistryVisits
    var startIndex: Int { source.startIndex }
    var endIndex: Int { source.endIndex }
    func index(after index: Int) -> Int { index + 1 }
    func index(before index: Int) -> Int { index - 1 }
    subscript(index: Int) -> Registry.Entry {
        _ = visits.next()
        if index == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
        return source[index]
    }
}

// These probes are confined to one synchronous iterator in one task; they are
// deliberately non-Sendable and never shared by the concurrent-reader test.
private final class RegistryVisits {
    var value = 0
    func next() -> Int { value += 1; return value }
}
