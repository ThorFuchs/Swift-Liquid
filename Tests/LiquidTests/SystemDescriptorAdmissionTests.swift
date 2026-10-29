// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Closed system descriptor admission")
struct SystemDescriptorAdmissionTests {
    @Test func fieldsKindsLimitsAndCancellation() async throws {
        typealias Descriptor = LiquidSystemDescriptor
        let fields: [Descriptor.Entry] = [
            .init("title", .text("Résumé")), .init("description", .text("A")),
            .init("type", .typeNames(["string", "null"])), .init("format", .text("date")),
            .init("required", .boolean(true)), .init("nullable", .boolean(false)),
            .init("deprecated", .boolean(false))
        ]
        let total = fields.reduce(0) { sum, entry in
            sum + entry.name.utf8.count + {
                switch entry.value {
                case .text(let value): value.utf8.count
                case .typeNames(let values): values.reduce(0) { $0 + $1.utf8.count }
                case .boolean: 0
                }
            }()
        }
        let exact = Descriptor.Limits(fields: 7, textBytes: total, typeNames: 2)
        #expect(try Descriptor(fields, limits: exact).entries == fields)
        #expect(try Descriptor([], limits: .init(fields: 0, textBytes: 0, typeNames: 0)).entries.isEmpty)
        #expect(throws: Descriptor.AdmissionError.limitExceeded("fields")) {
            try Descriptor(fields, limits: .init(fields: 6, textBytes: total, typeNames: 2))
        }
        #expect(throws: Descriptor.AdmissionError.limitExceeded("textBytes")) {
            try Descriptor(fields, limits: .init(fields: 7, textBytes: total - 1, typeNames: 2))
        }
        #expect(throws: Descriptor.AdmissionError.limitExceeded("typeNames")) {
            try Descriptor(fields, limits: .init(fields: 7, textBytes: total, typeNames: 1))
        }
        #expect(throws: Descriptor.AdmissionError.invalidLimits) {
            try Descriptor([], limits: .init(fields: -1))
        }
        #expect(throws: Descriptor.AdmissionError.unknownField) {
            try Descriptor([.init("raw_schema", .text("secret"))])
        }
        #expect(throws: Descriptor.AdmissionError.incorrectValueKind) {
            try Descriptor([.init("nullable", .text("false"))])
        }
        #expect(throws: Descriptor.AdmissionError.duplicateField) {
            try Descriptor([.init("title", .text("a")), .init("title", .text("b"))])
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try Descriptor(fields, limits: exact)
        }
        do { _ = try await task.value; Issue.record("Cancelled admission succeeded") }
        catch is CancellationError { }
    }
}
