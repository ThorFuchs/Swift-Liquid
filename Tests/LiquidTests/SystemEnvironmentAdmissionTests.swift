// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("System environment admission")
struct SystemEnvironmentAdmissionTests {
    @Test func residentTreesAndFiniteOccurrenceLimits() async throws {
        typealias E = LiquidSystemEnvironment
        typealias V = LiquidSystemValue
        let child = V.decorated(.init(primary: .ordinary(.string("x"))))
        let entries: [V.Entry] = [.init("root", .array([child, child]))]
        let valid = try E(entries, limits: .init(nodes: 5, depth: 3, representationSlots: 0))
        #expect(valid.entries.count == 1)
        #expect(throws: E.AdmissionError.limitExceeded("systemNodes")) {
            try E(entries, limits: .init(nodes: 4, depth: 3, representationSlots: 0))
        }
        #expect(throws: E.AdmissionError.limitExceeded("systemDepth")) {
            try E(entries, limits: .init(nodes: 5, depth: 2, representationSlots: 0))
        }
        #expect(try E(entries, limits: .init(retainedBytes: 358)).entries.count == 1)
        #expect(throws: E.AdmissionError.limitExceeded("systemRetainedBytes")) {
            try E(entries, limits: .init(retainedBytes: 357))
        }
        #expect(throws: E.AdmissionError.duplicateName) {
            try E([.init("a", .ordinary(.null)), .init("a", .ordinary(.null))])
        }
        #expect(try E([.init("é", .ordinary(.null)), .init("e\u{301}", .ordinary(.null))]).entries.count == 2)
        #expect(throws: E.AdmissionError.invalidNumber) {
            try E([.init("x", .ordinary(.number(.infinity)))])
        }
        #expect(throws: E.AdmissionError.nestedDecoration) {
            try E([.init("x", .decorated(.init(primary: child)))])
        }
        #expect(throws: E.AdmissionError.invalidLimits) { try E([], limits: .init(nodes: -1)) }
        #expect(try E([], limits: .init(nodes: 0, depth: 0, textBytes: 0, descriptorFields: 0, descriptorBytes: 0, representationSlots: 0, representationBytes: 0, identityBytes: 0, reasonBytes: 0, work: 0)).entries.isEmpty)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try E(entries)
        }
        do { _ = try await task.value; Issue.record("Cancelled admission succeeded") }
        catch is CancellationError { }
    }

    @Test func representationsAreResidentBoundedAndContextSpecific() throws {
        typealias E = LiquidSystemEnvironment
        typealias V = LiquidSystemValue
        let textIdentity = try LiquidSystemPolicyIdentity(role: "content", bytes: [1, 2], context: .htmlTextV1)
        let node = V.decorated(.init(primary: .ordinary(.string("a")), plain: .qualified("plain"), htmlText: .qualified("&amp;", textIdentity)))
        #expect(try E([.init("x", node)], limits: .init(representationSlots: 2, representationBytes: 10, identityBytes: 9)).entries.count == 1)
        #expect(throws: E.AdmissionError.limitExceeded("systemRepresentationSlots")) {
            try E([.init("x", node)], limits: .init(representationSlots: 1))
        }
        #expect(throws: E.AdmissionError.limitExceeded("systemRepresentationBytes")) {
            try E([.init("x", node)], limits: .init(representationBytes: 9))
        }
        #expect(throws: E.AdmissionError.limitExceeded("systemIdentityBytes")) {
            try E([.init("x", node)], limits: .init(identityBytes: 8))
        }
        #expect(throws: E.AdmissionError.invalidRepresentationContext) {
            try E([.init("x", .decorated(.init(primary: .ordinary(.null), html: .qualified("x", textIdentity))))])
        }
        #expect(throws: E.AdmissionError.limitExceeded("systemReasonBytes")) {
            try E([.init("x", .decorated(.init(primary: .ordinary(.null), plain: .unavailable("large"))))], limits: .init(reasonBytes: 4))
        }
    }
}
