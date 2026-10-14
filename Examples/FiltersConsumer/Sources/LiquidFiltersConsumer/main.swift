// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid

@main
struct Consumer {
    static func main() async throws {
        let label = LiquidFilter("label") { input, arguments, named in
            guard case .string(let text) = input else { throw LiquidFilterFailure("Expected text") }
            let separator: String
            if case .string(let value) = named["separator"] { separator = value } else { separator = ": " }
            guard case .string(let prefix) = arguments.first else { throw LiquidFilterFailure("Expected a prefix") }
            return .string(prefix + separator + text)
        }
        let engine = try LiquidEngine(filters: [label], strictFilters: true)
        let template = try LiquidTemplate("{{ title | label: 'Topic', separator: ' — ' | escape }}")
        let output = try await engine.render(template, context: ["title": "Swift & Liquid"])
        precondition(output == "Topic — Swift &amp; Liquid")
        let invalid = try await engine.renderWithDiagnostics(template: "{% assign title = 1 | label: 'Topic' %}")
        precondition(invalid.output.isEmpty && invalid.diagnostics.count == 1)
        precondition(invalid.diagnostics.first?.message == "Filter 'label' failed: Expected text")
        // Keep parsed roots/partials in the application; map domain values explicitly.
        let page = try LiquidTemplate("{% render 'card', article: article %}", syntaxMode: .strict2)
        let partials = ["card": try LiquidTemplate("<h2>{{ article.title | label: 'Topic' | escape }}</h2>", syntaxMode: .strict2)]
        for article in [Article(title: "Swift & Liquid"), Article(title: "Reusable templates")] {
            let context: LiquidObject = ["article": article.liquidValue, "published": true]
            precondition(context.entries.map(\.key) == ["article", "published"])
            let rendered = try await engine.render(page, context: context, templates: partials)
            let title = article.title.replacingOccurrences(of: "&", with: "&amp;")
            precondition(rendered == "<h2>Topic: " + title + "</h2>")
        }
        print("Public custom-filter consumer examples passed.")
    }
}

private struct Article: Sendable {
    let title: String
    var liquidValue: LiquidValue { .object(["title": .string(title)]) }
}
