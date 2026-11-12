// SPDX-License-Identifier: Apache-2.0
import Liquid
import Testing

@Suite("Reconciled system and core behavior")
struct ReconciledSystemCompatibilityTests {
    @Test func multilineAndNestedSystemSelectionKeepScope() async throws {
        let descriptor = try LiquidSystemDescriptor([.init("title", .text("kept"))])
        let child: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("value")), descriptor: descriptor))
        let root: LiquidSystemValue = .object([.init("child", child)])
        let environment = try LiquidSystemEnvironment([.init("article", root), .init("host", .ordinary(.string("host")))])
        let partial = try LiquidTemplate("{{ host }}|{{ article.child.$descriptor.title }}|{{ local }}", syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        let registry = try LiquidTemplateRegistry([.init("p", .parsed(partial))])
        let source = "{% liquid\nassign local = 'caller'\nif true\nrender 'p'\nendif\n%}"
        let parsed = try LiquidTemplate(source, syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        #expect(try await LiquidEngine().render(parsed, environment: environment, registry: registry) == "host|kept|")
        #expect(throws: LiquidError.self) { try LiquidTemplate("{{ article.child.$descriptor.title }}", syntaxMode: .strict2) }
    }

    @Test func systemSelectionAndLaxFilterScanningStayDistinct() async throws {
        let descriptor = try LiquidSystemDescriptor([.init("title", .text("kept"))])
        let child: LiquidSystemValue = .decorated(.init(primary: .ordinary(.string("abc")), descriptor: descriptor))
        let environment = try LiquidSystemEnvironment([.init("items", .array([child]))])
        let template = try LiquidTemplate("{{ items[0].$descriptor.title }}|{{ 'hi there' | split$$$: ' ' | first }}", syntaxMode: .lax, extensionProfile: .closedSystemV1)
        #expect(try await LiquidEngine().render(template, environment: environment, registry: LiquidTemplateRegistry([])) == "kept|hi")
        let selected = try LiquidTemplate("{% assign found = items | where: 'b' | first %}{{ found.$descriptor.title }}", syntaxMode: .strict2, extensionProfile: .closedSystemV1)
        #expect(try await LiquidEngine().render(selected, environment: environment, registry: LiquidTemplateRegistry([])) == "kept")
    }
}
