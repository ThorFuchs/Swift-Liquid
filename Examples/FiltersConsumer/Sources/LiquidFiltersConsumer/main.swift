// SPDX-License-Identifier: Apache-2.0
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
        print("Public custom-filter consumer examples passed.")
    }
}
