// SPDX-License-Identifier: Apache-2.0

/// Observations from one completed render, including all nested partial work.
/// Counts describe logical budget consumption, not memory or CPU instructions.
public struct LiquidRenderMetrics: Sendable, Equatable {
    /// Monotonic elapsed time through final output admission, including host suspension.
    public let totalDuration: Duration
    /// Root/partial parsing time for source calls; nil when templates were already parsed.
    public let parseDuration: Duration?
    /// Admitted UTF-8 bytes of the root and every supplied partial, including unused ones.
    public let sourceBytes: Int
    /// UTF-8 bytes of the final returned output, excluding intermediate buffers.
    public let outputBytes: Int
    /// Cumulative evaluator-step capacity consumed by this library version.
    public let renderSteps: Int
    /// Cumulative loop-iteration capacity consumed across nested work.
    public let loopIterations: Int
    /// Cumulative context/custom-filter value visits charged to the invocation.
    public let admittedValues: Int

    internal init(totalDuration: Duration, parseDuration: Duration?, sourceBytes: Int,
                  outputBytes: Int, renderSteps: Int, loopIterations: Int, admittedValues: Int) {
        self.totalDuration = totalDuration; self.parseDuration = parseDuration
        self.sourceBytes = sourceBytes; self.outputBytes = outputBytes
        self.renderSteps = renderSteps; self.loopIterations = loopIterations
        self.admittedValues = admittedValues
    }
}

/// Complete output, explicit recovered diagnostics and metrics from one invocation.
public struct LiquidMeasuredRenderResult: Sendable {
    /// Complete rendered output, including any explicitly recovered error text.
    public let output: String
    /// Recovered errors in encounter order; empty for throwing renders.
    public let diagnostics: [LiquidDiagnostic]
    /// Durations and logical budget consumption of this completed invocation.
    public let metrics: LiquidRenderMetrics

    internal init(result: LiquidRenderResult, metrics: LiquidRenderMetrics) {
        self.output = result.output; self.diagnostics = result.diagnostics; self.metrics = metrics
    }
}
