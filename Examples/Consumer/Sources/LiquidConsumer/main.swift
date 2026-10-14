// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid

@main
struct Consumer {
    static func main() async throws {
        let engine = LiquidEngine()
        let greeting = try await engine.render(template: "Hello, {{ name | upcase }}!", context: ["name": "Swift"])
        precondition(greeting == "Hello, SWIFT!")
        let template = try LiquidTemplate("{% for item in items %}{{ item }} {% endfor %}")
        let result = try await engine.render(template, context: ["items": ["one", "two"]])
        precondition(result == "one two ")
        let page = try await engine.render(template: "{% render 'card', title: title %}", context: ["title": "Liquid in Swift"],
                                           templates: ["card": "<h2>{{ title | escape }}</h2>"])
        precondition(page == "<h2>Liquid in Swift</h2>")
        let value = try LiquidValue(json: #"{"name":"Ada","roles":["author","editor"]}"#)
        guard case .object(let context) = value else { preconditionFailure("Expected context object") }
        let author = try await engine.render(template: "{{ name }}", context: context)
        precondition(author == "Ada")
        let deterministic = LiquidEngine(referenceTime: Date(timeIntervalSince1970: 1_007_044_400))
        let partialDate = try await deterministic.render(template: "{{ 'Aug 31' | date: '%F' }}")
        precondition(partialDate == "2001-08-31")
        let recovered = try await deterministic.renderWithDiagnostics(
            template: "A{% assign b = items | reject: missing %}B", context: ["items": ["x"]])
        precondition(recovered.output == "AB" && recovered.diagnostics.count == 1)
        precondition(recovered.diagnostics.first?.line == 1)
        print("Public consumer examples passed.")
    }
}
