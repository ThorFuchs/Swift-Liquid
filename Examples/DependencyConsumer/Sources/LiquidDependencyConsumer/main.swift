// SPDX-License-Identifier: Apache-2.0
import Liquid

let engine = try LiquidEngine(filters: [LiquidFilter("host") { _, _, _ in
    fatalError("Dependency inspection must not invoke callbacks")
}])
let source = "{{ input | host }}{% include 'a' %}{% include selected %}"
let partials = ["a": "{% include 'b' %}", "b.liquid": "{% include 'a' %}{% include 'missing' %}"]
let report = try engine.inspectDependencies(template: source, templates: partials, syntaxMode: .strict2,
    analysisLimits: LiquidDependencyLimits(templates: 3, nameBytes: 9, edges: 4))
let parsed = try partials.mapValues { try LiquidTemplate($0, syntaxMode: .strict2) }
let reused = try engine.inspectDependencies(LiquidTemplate(source, syntaxMode: .strict2), templates: parsed)
precondition(reused == report)
precondition(report.nodes.map(\.id) == [.root, .partial("a"), .partial("b.liquid")])
precondition(report.cycles == [[.partial("a"), .partial("b.liquid")]])
precondition(report.missingReferences.map(\.requestedName) == ["missing"])
precondition(report.dynamicReferences == [.root])
func requireSendable<T: Sendable>(_ value: T) {}
requireSendable(report); requireSendable(LiquidDependencyLimits.default)
requireSendable(report.nodes); requireSendable(report.edges); requireSendable(report.cycles)
print("Public dependency consumer passed.")
