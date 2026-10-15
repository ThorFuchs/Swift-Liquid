// SPDX-License-Identifier: Apache-2.0
import Liquid

@main
struct MetricsConsumer {
    static func checked<T: Sendable>(_ value: T) -> T { value }
    static func main() async throws {
        let engine = LiquidEngine()
        let source = "{{ name }}{% render 'part' %}"
        let partials = ["part": "{% for i in (1..2) %}!{% endfor %}"]
        let measured = checked(try await engine.renderWithMetrics(template: source, context: ["name": "Swift"], templates: partials))
        precondition(measured.output == "Swift!!" && measured.diagnostics.isEmpty)
        let metrics = checked(measured.metrics)
        precondition(metrics.parseDuration != nil && metrics.totalDuration >= metrics.parseDuration!)
        precondition(metrics.outputBytes == 7 && metrics.loopIterations == 2 && metrics.admittedValues == 1)
        let root = checked(try LiquidTemplate(source))
        let parsedPartials = try partials.mapValues { try LiquidTemplate($0) }
        let reused = try await engine.renderWithMetrics(root, context: ["name": "Swift"], templates: parsedPartials)
        precondition(reused.metrics.parseDuration == nil && reused.metrics.renderSteps == metrics.renderSteps)
        let host = try LiquidEngine(filters: [LiquidFilter("fail") { _, _, _ in throw LiquidFilterFailure("expected") }])
        let recovered = try await host.renderWithDiagnosticsAndMetrics(template: "{% assign x = '' | fail %}")
        precondition(recovered.output.isEmpty && recovered.diagnostics.count == 1 && recovered.metrics.admittedValues == 1)
        let parsedFailure = try LiquidTemplate("{% assign x = '' | fail %}")
        let same = try await host.renderWithDiagnosticsAndMetrics(parsedFailure)
        precondition(same.diagnostics == recovered.diagnostics && same.metrics.parseDuration == nil)
        print("Public metrics consumer passed.")
    }
}
