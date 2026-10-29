// SPDX-License-Identifier: Apache-2.0
import Liquid

private func hex(_ value: String) -> String {
    let digits = Array("0123456789abcdef")
    return value.utf8.reduce(into: "") { result, byte in
        result.append(digits[Int(byte >> 4)])
        result.append(digits[Int(byte & 15)])
    }
}

private enum ConsumerFailure: Error { case assertion(String) }

@main struct LiquidRegistryConsumer {
    static func main() async throws {
        let parsed = try LiquidTemplate("{{ retained }}", syntaxMode: .strict2)
        let registry = try LiquidTemplateRegistry([
            .init("é", .raw("A")), .init("e\u{301}", .raw("B")),
            .init("K", .raw("C")), .init("\u{212A}", .raw("D")),
            .init("card.liquid", .parsed(parsed)), .init("opaque", .raw("{% if %}"))
        ])
        // Independent literal byte/index oracle; output is TSV, not an engine JSON bridge.
        let controls: [(String, Int, String, String)] = [
            ("é", 0, "c3a9", "A"), ("e\u{301}", 1, "65cc81", "B"),
            ("K", 2, "4b", "C"), ("\u{212A}", 3, "e284aa", "D"),
            ("card", 4, "636172642e6c6971756964", "{{ retained }}"),
            ("opaque", 5, "6f7061717565", "{% if %}")
        ]
        for (request, expectedIndex, expectedName, expectedSource) in controls {
            guard let resolved = try registry.resolve(request) else { throw ConsumerFailure.assertion("missing") }
            let source: String
            switch resolved.content {
            case .raw(let raw): source = raw
            case .parsed(let template): source = template.source
            }
            guard resolved.entryIndex == expectedIndex, hex(resolved.name) == expectedName,
                  source.utf8.elementsEqual(expectedSource.utf8) else {
                throw ConsumerFailure.assertion("identity")
            }
            print("IDENTITY\t\(hex(request))\t\(expectedIndex)\t\(resolved.entryIndex)\t\(expectedName)\t\(hex(resolved.name))\t\(hex(expectedSource))\t\(hex(source))")
        }
        guard try registry.resolve("missing") == nil else { throw ConsumerFailure.assertion("unexpected hit") }
        do {
            _ = try registry.resolve(String(repeating: "a", count: 1_025))
            throw ConsumerFailure.assertion("overlong request accepted")
        } catch LiquidTemplateRegistry.AdmissionError.limitExceeded(.nameUTF8Bytes) {
            print("CAPACITY\tnameUTF8Bytes\tPASS")
        }
        let count = try await withThrowingTaskGroup(of: Int.self, returning: Int.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    guard try registry.resolve("e\u{301}")?.entryIndex == 1 else {
                        throw ConsumerFailure.assertion("concurrent identity")
                    }
                    return 1
                }
            }
            var total = 0
            for try await result in group { total += result }
            return total
        }
        guard count == 16 else { throw ConsumerFailure.assertion("task count") }
        print("CONCURRENT\t16\tPASS")
        print("U1_REGISTRY_ONLY\tPASS")
    }
}
