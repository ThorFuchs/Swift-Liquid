// SPDX-License-Identifier: Apache-2.0
import Liquid

private func hex(_ text: String) -> String {
    text.utf8.map { let value = String($0, radix: 16); return value.count == 1 ? "0" + value : value }.joined()
}
private struct Observation {
    let output: String
    let diagnostics: [LiquidDiagnostic]
    let metrics: LiquidRenderMetrics?
    init(_ output: String) { self.output = output; diagnostics = []; metrics = nil }
    init(_ result: LiquidRenderResult) { output = result.output; diagnostics = result.diagnostics; metrics = nil }
    init(_ result: LiquidMeasuredRenderResult) { output = result.output; diagnostics = result.diagnostics; metrics = result.metrics }
}
@main struct LiquidExactRegistryConsumer {
    private static func run(_ source: String, parsed: Bool, family: Int, engine: LiquidEngine,
                    registry: LiquidTemplateRegistry, context: LiquidObject = [:]) async throws -> Observation {
        if parsed {
            let root = try LiquidTemplate(source)
            switch family {
            case 0: return .init(try await engine.render(root, context: context, registry: registry))
            case 1: return .init(try await engine.renderWithDiagnostics(root, context: context, registry: registry))
            case 2: return .init(try await engine.renderWithMetrics(root, context: context, registry: registry))
            default: return .init(try await engine.renderWithDiagnosticsAndMetrics(root, context: context, registry: registry))
            }
        }
        switch family {
        case 0: return .init(try await engine.render(template: source, context: context, registry: registry))
        case 1: return .init(try await engine.renderWithDiagnostics(template: source, context: context, registry: registry))
        case 2: return .init(try await engine.renderWithMetrics(template: source, context: context, registry: registry))
        default: return .init(try await engine.renderWithDiagnosticsAndMetrics(template: source, context: context, registry: registry))
        }
    }

    static func main() async throws {
        let engine = LiquidEngine()
        let entries: [LiquidTemplateRegistry.Entry] = try [.init("é", .raw("A")), .init("e\u{301}", .parsed(LiquidTemplate("B"))),
            .init("K", .raw("C")), .init("K", .raw("D")), .init("card.liquid", .raw("E")),
            .init("double.liquid.liquid", .parsed(LiquidTemplate("F")))]
        let registry = try LiquidTemplateRegistry(entries)
        let requests = ["é", "e\u{301}", "K", "K", "card", "double.liquid"]
        for parsed in [false, true] {
            for family in 0..<4 {
                for (index, request) in requests.enumerated() {
                    let source = "{% include '\(request)' %}"
                    let result = try await run(source, parsed: parsed, family: family, engine: engine, registry: registry)
                    let expected = ["A", "B", "C", "D", "E", "F"][index]
                    precondition(result.output.utf8.elementsEqual(expected.utf8) && result.diagnostics.isEmpty)
                    guard let selected = try registry.resolve(request) else { preconditionFailure("Public resolution missing") }
                    precondition(selected.entryIndex == index)
                    print(["RUNTIME", parsed ? "parsed" : "raw", String(family), hex(request), String(index), String(selected.entryIndex), hex(selected.name), hex(expected), hex(result.output)].joined(separator: "\t"))
                }
            }
        }
        let nested = try LiquidTemplateRegistry([.init("é", .raw("A{% include 'e\u{301}' %}")), .init("e\u{301}", .raw("B{% render 'K' %}")), .init("K", .raw("C{% include 'K' %}")), .init("K", .raw("D"))])
        let nestedOutput = try await engine.render(template: "{% include selected %}", context: ["selected": "é"], registry: nested)
        precondition(nestedOutput == "ABCD")
        let allParsed = try LiquidTemplateRegistry([.init("p", .parsed(LiquidTemplate("π")))])
        let mixed = try LiquidTemplateRegistry([.init("p", .parsed(LiquidTemplate("π"))), .init("unused", .raw("z"))])
        let source = "L{% include 'p' %}"
        let root = try LiquidTemplate(source)
        let rawGraph = try engine.inspectDependencies(template: source, registry: allParsed)
        let parsedGraph = try engine.inspectDependencies(root, registry: allParsed)
        precondition(rawGraph == parsedGraph && rawGraph.nodes.count == 2 && rawGraph.edges.count == 1)
        precondition(rawGraph.edges[0].requestedName == "p" && rawGraph.edges[0].resolvedName == "p")
        print("U3_TWO_PUBLIC_GRAPH_APIS\tPASS")
        for (label, value, expectedParse, bytes) in [("all-parsed", allParsed, false, source.utf8.count + 2), ("mixed", mixed, true, source.utf8.count + 3)] {
            let result = try await engine.renderWithMetrics(root, registry: value)
            precondition(result.output == "Lπ" && result.metrics.sourceBytes == bytes && (result.metrics.parseDuration != nil) == expectedParse)
            print(["METRICS", label, String(bytes), String(result.metrics.sourceBytes), String(expectedParse), String(result.metrics.parseDuration != nil), hex(result.output), String(result.metrics.renderSteps), String(result.metrics.loopIterations), String(result.metrics.admittedValues), String(result.metrics.outputBytes)].joined(separator: "\t"))
        }
        let capacity = try LiquidTemplateRegistry([.init("p", .raw("P"))], limits: .init(nameUTF8Bytes: 1))
        do {
            _ = try await engine.renderWithDiagnosticsAndMetrics(template: "{% include alias %}", context: ["alias": "p"], registry: capacity)
            preconditionFailure("Capacity became fallback success")
        } catch LiquidTemplateRegistry.AdmissionError.limitExceeded(let value) {
            precondition(value == .nameUTF8Bytes); print("ERROR\tname-capacity\tTERMINAL")
        }
        let recover = try LiquidEngine(filters: [LiquidFilter("deny") { _, _, _ in throw LiquidFilterFailure("synthetic recoverable") }])
        let bad = try LiquidTemplateRegistry([.init("é.liquid", .raw("{{ '' | deny }}")), .init("e\u{301}", .raw("{{ '' | deny }}"))])
        let result = try await recover.renderWithDiagnosticsAndMetrics(template: "{% render 'é' %}{% render 'e\u{301}' %}", registry: bad)
        precondition(result.diagnostics.count == 2)
        for (diagnostic, expectedName) in zip(result.diagnostics, ["é.liquid", "e\u{301}"]) {
            precondition(diagnostic.templateName?.utf8.elementsEqual(expectedName.utf8) == true)
            print(["DIAGNOSTIC", hex(expectedName), hex(diagnostic.templateName ?? "")].joined(separator: "\t"))
        }
        let rawReference: @Sendable (String, LiquidObject, LiquidTemplateRegistry, LiquidSyntaxMode) async throws -> String = engine.render(template:context:registry:syntaxMode:)
        let parsedReference: @Sendable (LiquidTemplate, LiquidObject, LiquidTemplateRegistry, LiquidSyntaxMode) async throws -> String = engine.render(_:context:registry:syntaxMode:)
        let rawOutput = try await rawReference("{% include 'é' %}", [:], registry, .strict2)
        precondition(rawOutput == "A")
        let parsedOutput = try await parsedReference(LiquidTemplate("{% include 'é' %}"), [:], registry, .strict2)
        precondition(parsedOutput == "A")
        let legacy = try await engine.render(template: "{{ value }}", context: ["value": "legacy"])
        precondition(legacy == "legacy")
        print("U2_EIGHT_PUBLIC_APIS\tPASS")
    }
}
