// SPDX-License-Identifier: Apache-2.0
// Generated from README Swift fences; regenerate with Scripts/documentation_catalog.py.
import Liquid
import Foundation

@main
struct LiquidREADMEConsumer {
    static func main() async throws {
        do {
            let engine = LiquidEngine()
            let output = try await engine.render(
                template: "Hello, {{ name | upcase }}!",
                context: ["name": "Swift"]
            )
            print(output) // Hello, SWIFT!
        }

        do {
            let engine = LiquidEngine()
            let template = try LiquidTemplate("{% for item in items %}{{ item }} {% endfor %}")
            let output = try await engine.render(template, context: ["items": ["one", "two"]])
            print(output.trimmingCharacters(in: .whitespaces)) // one two
        }

        do {
            let output = try await LiquidEngine().render(
                template: "{% render 'card', title: title %}",
                context: ["title": "Swift & Liquid"],
                templates: ["card": "<h2>{{ title | escape }}</h2>"]
            )
            print(output) // <h2>Swift &amp; Liquid</h2>
        }

        do {
            let value = try LiquidValue(json: #"{"name":"Ada"}"#)
            if case .object(let context) = value {
                let engine = try LiquidEngine(filters: [
                    LiquidFilter("greet") { value, _, _ in
                        guard case .string(let name) = value else {
                            throw LiquidFilterFailure("Expected a name")
                        }
                        return .string("Hello, " + name)
                    }
                ])
                print(try await engine.render(template: "{{ name | greet | escape }}", context: context)) // Hello, Ada
            }
        }

        do {
            let engine = LiquidEngine()
            let summary = try engine.inspect(template: "{{ user[key] | escape }}{% render 'card' %}")
            print(summary.variableRoots.joined(separator: ",")) // key,user

            let graph = try engine.inspectDependencies(
                template: "{% include 'card' %}",
                templates: ["card": "{% include 'badge' %}"]
            )
            print(graph.nodes.count) // 2
            print(graph.missingReferences.map(\.requestedName).joined(separator: ",")) // badge
        }

        do {
            let measured = try await LiquidEngine().renderWithMetrics(
                template: "Hello, {{ name }}!", context: ["name": "Swift"]
            )
            print(measured.output) // Hello, Swift!
            print(measured.metrics.outputBytes) // 13
        }
    }
}
