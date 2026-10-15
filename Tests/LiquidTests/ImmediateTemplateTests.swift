// SPDX-License-Identifier: Apache-2.0
@testable import Liquid
import Foundation
import Testing

private struct RenderSnapshot: Equatable {
    let output: String?
    let error: String?
    let diagnostics: [LiquidDiagnostic]
    let steps: Int
    let iterations: Int
    let values: Int
    let depth: Int
    let assigned: String?
}

private struct CancellingDescription: CustomStringConvertible, Sendable {
    let output: String
    var description: String {
        withUnsafeCurrentTask { $0?.cancel() }
        return output
    }
}

@Suite("Small template execution", .timeLimit(.minutes(1)))
struct ImmediateTemplateTests {
    @Test(arguments: [false, true], [
        "", "plain", "{{ value }}", "A{{ value }}", "{{ value }}B", "A{{ value }}B",
        "{{ value }}{{ missing }}", "{{ value }}{{ missing }}!", "{{ value }}|{{ value }}|",
        "{% raw %}raw{% endraw %}{{ value }}", "{{ value | upcase }}",
        "{{ value }}{% assign value = 'changed' %}{{ value }}",
        "{{ value }}{{ value | missing_filter }}!",
    ])
    func generalRendererBudgetParity(recovering: Bool, source: String) async throws {
        let template = try LiquidTemplate(source)
        let profiles: [LiquidLimits] = [
            .default, .init(renderSteps: 1), .init(renderSteps: 2), .init(renderSteps: 3),
            .init(outputBytes: 1), .init(outputBytes: 5), .init(nestingDepth: 1), .init(nestingDepth: 2),
        ]
        for limits in profiles {
            func snapshot(general: Bool) async -> RenderSnapshot {
                let renderer = Renderer(configuration: .init(strictMode: true), limits: limits,
                                        recoveryEnabled: recovering)
                let variables: RuntimeVariables = ["value": "Swift"]
                renderer.context.setVariables(variables)
                let output: String?
                let failure: String?
                do {
                    if general { output = try await renderer.renderNode(template.ast) }
                    else { output = try await renderer.render(template.ast, with: variables) }
                    failure = nil
                } catch { output = nil; failure = String(describing: error) }
                return RenderSnapshot(output: output, error: failure, diagnostics: renderer.diagnostics,
                    steps: renderer.budget.remainingSteps, iterations: renderer.budget.remainingIterations,
                    values: renderer.budget.remainingValues, depth: renderer.budget.activeDepth,
                    assigned: renderer.context.getVariable("value") as? String)
            }
            let expected = await snapshot(general: true)
            let actual = await snapshot(general: false)
            #expect(actual == expected)
            #expect(actual.depth == 0)
        }
    }

    @Test(arguments: ["{{ value }}", "A{{ value }}B", "{{ value }}B"], ["", "x", "xx"])
    func cancellationDuringImmediateStringificationPrecedesQuota(source: String, output: String) async throws {
        let template = try LiquidTemplate(source)
        let worker = Task {
            let renderer = Renderer(limits: .init(outputBytes: 1))
            return try await renderer.render(template.ast, with: ["value": CancellingDescription(output: output)])
        }
        defer { worker.cancel() }
        await #expect(throws: CancellationError.self) { try await worker.value }
    }
}
