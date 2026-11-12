// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("System representation policy identity")
struct SystemPolicyIdentityTests {
    @Test func exactBytesContextsCapacitiesAndCancellation() async throws {
        typealias Identity = LiquidSystemPolicyIdentity
        let composed = Array("é".utf8)
        let decomposed = Array("e\u{301}".utf8)
        let a = try Identity(role: "content.html-v1", bytes: composed, context: .htmlTextV1)
        let b = try Identity(role: "content.html-v1", bytes: decomposed, context: .htmlTextV1)
        let otherContext = try Identity(role: "content.html-v1", bytes: composed, context: .htmlFlowFragmentV1)
        #expect(a != b)
        #expect(a != otherContext)
        #expect(a == (try Identity(role: "content.html-v1", bytes: composed, context: .htmlTextV1)))
        #expect(try Identity(role: String(repeating: "x", count: 64), bytes: Array(repeating: 0, count: 256), context: .htmlTextV1).bytes.count == 256)
        #expect(try Identity(role: "a", bytes: [], context: .htmlTextV1).bytes.isEmpty)
        #expect(throws: Identity.AdmissionError.invalidRole) {
            try Identity(role: String(repeating: "x", count: 65), bytes: [], context: .htmlTextV1)
        }
        #expect(throws: Identity.AdmissionError.invalidRole) {
            try Identity(role: "é", bytes: [], context: .htmlTextV1)
        }
        #expect(throws: Identity.AdmissionError.invalidRole) {
            try Identity(role: "", bytes: [], context: .htmlTextV1)
        }
        #expect(throws: Identity.AdmissionError.identityTooLong) {
            try Identity(role: "a", bytes: Array(repeating: 0, count: 257), context: .htmlTextV1)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try Identity(role: "a", bytes: [], context: .htmlTextV1)
        }
        do { _ = try await task.value; Issue.record("Cancelled identity admission succeeded") }
        catch is CancellationError { }
    }
}
