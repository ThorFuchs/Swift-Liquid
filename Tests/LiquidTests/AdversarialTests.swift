// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
import Testing

private struct AdversarialInput {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
        return Int((state >> 32) % UInt64(bound))
    }
    mutating func text() -> String {
        let alphabet = ["a", "\0", "\n", "\r", "\t", "é", "e\u{301}", "👩‍💻", "🇩🇪", "\"", "'", "&", "<", ">", "\\", "}}", "%}"]
        return (0..<next(12)).map { _ in alphabet[next(alphabet.count)] }.joined()
    }
}

@Suite("Adversarial public boundaries", .timeLimit(.minutes(1)))
struct AdversarialTests {
    @Test(arguments: [UInt64(0), 1, 0xc0ffee, .max])
    func unicodeOperationsUseScalarsWithoutNormalizing(seed: UInt64) async throws {
        var input = AdversarialInput(state: seed)
        let engine = LiquidEngine()
        for index in 0..<32 {
            let text = input.text()
            let scalars = text.unicodeScalars.map(String.init)
            let start = input.next(scalars.count + 1)
            let length = input.next(5)
            let context: LiquidObject = ["text": .string(text), "start": .integer(start), "length": .integer(length)]
            let source = "{{ text | size }}|{{ text.first }}|{{ text.last }}|{{ text | slice: start, length }}|{{ text | split: '' | join: '·' }}"
            let expected = "\(scalars.count)|\(scalars.first ?? "")|\(scalars.last ?? "")|" + scalars.dropFirst(start).prefix(length).joined() + "|" + scalars.joined(separator: "·")
            let actual = try await engine.render(template: source, context: context)
            #expect(actual.utf8.elementsEqual(expected.utf8), "seed=\(seed), case=\(index), text=\(String(reflecting: text))")
        }
        // Minimized canonical-equivalence boundary: Swift String equality alone misses this.
        #expect(try await engine.render(template: "{% if a == b %}same{% else %}different{% endif %}",
            context: ["a": "é", "b": "e\u{301}"]) == "different")
    }

    @Test(arguments: [UInt64(0), 1, 0xc0ffee, .max])
    func jsonEscapesAndTruncatedContainersRetainByteEvidence(seed: UInt64) throws {
        var input = AdversarialInput(state: seed)
        for index in 0..<24 {
            let text = input.text()
            // Encode every UTF-16 unit explicitly, including surrogate pairs and controls.
            let escaped = text.utf16.map { String(format: "\\u%04X", $0) }.joined()
            let document = "[\"" + escaped + "\",{\"é\":1,\"e\\u0301\":2}]"
            guard case .array(let values) = try LiquidValue(json: document),
                  case .string(let decoded) = values[0], case .object(let object) = values[1] else {
                Issue.record("Unexpected JSON shape, seed=\(seed), case=\(index)"); continue
            }
            #expect(decoded.utf8.elementsEqual(text.utf8))
            #expect(object["é"] == 1 && object["e\u{301}"] == 2 && object.entries.count == 2)
            // Every proper scalar prefix is an incomplete outer container, never a success.
            for end in document.indices {
                let prefix = String(document[..<end])
                let error = #expect(throws: LiquidJSONError.self) { try LiquidValue(json: prefix) }
                if let error { #expect((0...prefix.utf8.count).contains(error.byteOffset)) }
            }
        }
        for malformed in [#""\uDC00""#, #""\uD800x""#, #""\uD800\u0041""#, #"{"é":0,"\u00e9":1}"#, "[1e+]", "[00]", "[NaN]", "[\"\u{1}\"]"] {
            #expect(throws: LiquidJSONError.self) { try LiquidValue(json: malformed) }
        }
    }

    @Test func jsonNestingHasAnExactPublicBoundary() throws {
        for shape in 0..<3 {
            let objectLevels = (0..<128).map { shape == 1 || (shape == 2 && $0.isMultiple(of: 2)) }
            let admitted = objectLevels.map { $0 ? "{\"x\":" : "[" }.joined() + "0"
                + objectLevels.reversed().map { $0 ? "}" : "]" }.joined()
            var value = try LiquidValue(json: admitted)
            for isObject in objectLevels {
                if isObject, case .object(let object) = value {
                    #expect(object.entries.count == 1)
                    value = try #require(object["x"])
                } else if !isObject, case .array(let array) = value {
                    #expect(array.count == 1)
                    value = try #require(array.first)
                } else { Issue.record("Unexpected nested JSON shape"); break }
            }
            #expect(value == 0)
            #expect(throws: LiquidJSONError.self) { try LiquidValue(json: "[" + admitted + "]") }
        }
    }

    @Test(arguments: [UInt64(0), 1, 0xc0ffee, .max])
    func quotedDelimitersAndOpaqueBlocksDoNotBecomeExecutable(seed: UInt64) async throws {
        var input = AdversarialInput(state: seed)
        let engine = LiquidEngine()
        for index in 0..<24 {
            let depth = input.next(8) + 1
            let literal = ["}}", "%}", "[a,b] | missing: 9", "é", "e\u{301}"][input.next(5)]
            let opaque = "{{ missing | unknown }}{% include 'absent' %}"
            let source = String(repeating: "{% if true %}", count: depth)
                + "{{ '\(literal)' }}{% comment %}" + opaque + "{% endcomment %}{% raw %}" + opaque + "{% endraw %}"
                + String(repeating: "{% endif %}", count: depth)
            let expected = literal + opaque
            for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
                let parsed = try LiquidTemplate(source, syntaxMode: mode)
                #expect(try await engine.render(parsed).utf8.elementsEqual(expected.utf8), "seed=\(seed), case=\(index), mode=\(mode)")
                #expect(try engine.inspect(parsed).filterNames.isEmpty)
            }
        }
        for source in ["{{", "{% if true %}", "{% raw %}", "{% comment %}", "{% unsupported_tag %}"] {
            for mode in [LiquidSyntaxMode.lax, .strict, .strict2] {
                let error = #expect(throws: LiquidError.self) { try LiquidTemplate(source, syntaxMode: mode) }
                if case .syntax? = error { } else { Issue.record("Expected syntax error for \(source), mode=\(mode)") }
            }
        }
    }

    @Test(arguments: [UInt64(0), 1, 0xc0ffee, .max])
    func utf8CapacitiesRejectOneByteBelowWithoutRecovery(seed: UInt64) async throws {
        var input = AdversarialInput(state: seed)
        for _ in 0..<24 {
            let text = "é" + input.text()
            let bytes = text.utf8.count
            let source = "{{ text }}"
            let parsed = try LiquidTemplate(source)
            let context: LiquidObject = ["text": .string(text)]
            let exact = LiquidEngine(limits: .init(outputBytes: bytes))
            #expect(try await exact.render(parsed, context: context).utf8.elementsEqual(text.utf8))
            let bounded = LiquidEngine(limits: .init(outputBytes: bytes - 1))
            let error = await #expect(throws: LiquidError.self) {
                try await bounded.renderWithDiagnosticsAndMetrics(parsed, context: context)
            }
            if case .limitExceeded("outputBytes")? = error { } else { Issue.record("Expected outputBytes, seed=\(seed)") }
            // Unused supplied partials still consume the cumulative source capacity.
            let total = source.utf8.count + text.utf8.count
            let admitted = LiquidEngine(limits: .init(sourceBytes: total))
            #expect(try await admitted.render(template: source, context: context, templates: ["unused": text]).utf8.elementsEqual(text.utf8))
            let rejected = LiquidEngine(limits: .init(sourceBytes: total - 1))
            let sourceError = await #expect(throws: LiquidError.self) {
                try await rejected.renderWithDiagnostics(template: source, context: context, templates: ["unused": text])
            }
            if case .limitExceeded("sourceBytes")? = sourceError { } else { Issue.record("Expected sourceBytes, seed=\(seed)") }
        }
    }
}
