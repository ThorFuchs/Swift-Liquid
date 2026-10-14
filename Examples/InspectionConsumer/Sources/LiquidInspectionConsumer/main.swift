// SPDX-License-Identifier: Apache-2.0
import Liquid

let source = "{{ user[key] | host | escape }}{% render 'card', title: title %}{% include selected %}"
let engine = try LiquidEngine(filters: [LiquidFilter("host") { _, _, _ in
    fatalError("Inspection must not invoke application code")
}], strictFilters: true)
let parsed = try LiquidTemplate(source, syntaxMode: .strict2)
let summary = try engine.inspect(parsed)
precondition(summary.variableRoots == ["key", "selected", "title", "user"])
precondition(summary.filterNames == ["escape", "host"])
precondition(summary.literalPartialNames == ["card"])
precondition(summary.hasDynamicPartials)
let fromSource = try engine.inspect(template: source, syntaxMode: .strict2)
precondition(summary == fromSource)
func requireSendable<T: Sendable>(_ value: T) {}
requireSendable(summary)
print("Public inspection consumer passed.")
