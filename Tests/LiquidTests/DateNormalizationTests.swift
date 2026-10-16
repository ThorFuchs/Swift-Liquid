// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

@Suite("Public date normalization", .timeLimit(.minutes(1)))
struct DateNormalizationTests {
    @Test(arguments: [false, true], 0..<4)
    func normalizationRetainsBytesAndInputBoundary(parsedInput: Bool, policy: Int) async throws {
        let stamp = "2024-02-03T04:05:06Z"
        let utc = "2024-02-03 04:05:06 +00:00 000000000"
        let offset = "2024-02-03 04:05:06 +05:30 000000000"
        let asciiBoundary = String(repeating: "!", count: 108) + stamp
        let unicodeBoundary = "😀" + String(repeating: "!", count: 104) + stamp
        #expect(asciiBoundary.utf8.count == 128 && unicodeBoundary.utf8.count == 128)
        let expandedBoundary = "İ" + String(repeating: "!", count: 106) + stamp
        #expect(expandedBoundary.utf8.count == 128 && expandedBoundary.lowercased().utf8.count == 129)
        let invalid = "\0not\t a date!?_"
        let vectors: [(String, String)] = [
            ("2024-02-03T04:05:06.123456789+05:30", "2024-02-03 04:05:06 +05:30 123456789"),
            ("Sat, 03 Feb 2024 04:05:06 +0530", offset),
            ("!_\0\tSat,\r\n03 Feb   2024 04:05:06 +0530!?_", offset),
            ("2024-02-03\t04:05:06Z", utc),
            ("\u{7f}!" + stamp + "!?_", utc),
            ("é😀\t" + stamp, utc),
            ("e\u{301}😀\u{a0}" + stamp, utc),
            (invalid, invalid),
            (asciiBoundary, utc),
            (asciiBoundary + "!", asciiBoundary + "!"),
            (unicodeBoundary, utc),
            (unicodeBoundary + "!", unicodeBoundary + "!"),
            (expandedBoundary, expandedBoundary),
        ]
        let engine = LiquidEngine(referenceTime: Date(timeIntervalSince1970: 1_007_044_400))
        let source = "{{ stamp | date: '%F %T %:z %N' }}"
        let parsed = try LiquidTemplate(source)
        for (input, expected) in vectors {
            let context: LiquidObject = ["stamp": .string(input)]
            let output: String
            switch policy {
            case 0:
                output = try await parsedInput ? engine.render(parsed, context: context) : engine.render(template: source, context: context)
            case 1:
                let result = try await parsedInput ? engine.renderWithDiagnostics(parsed, context: context) : engine.renderWithDiagnostics(template: source, context: context)
                #expect(result.diagnostics.isEmpty)
                output = result.output
            default:
                let result = try await policy == 2
                    ? (parsedInput ? engine.renderWithMetrics(parsed, context: context) : engine.renderWithMetrics(template: source, context: context))
                    : (parsedInput ? engine.renderWithDiagnosticsAndMetrics(parsed, context: context) : engine.renderWithDiagnosticsAndMetrics(template: source, context: context))
                #expect(result.diagnostics.isEmpty && result.metrics.outputBytes == expected.utf8.count)
                output = result.output
            }
            #expect(output.utf8.elementsEqual(expected.utf8), "Date input: \(input.debugDescription)")
        }
    }
}
