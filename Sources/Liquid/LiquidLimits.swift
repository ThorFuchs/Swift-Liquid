// SPDX-License-Identifier: Apache-2.0

/// Finite capacities for an operation. These are not process-memory or time guarantees.
public struct LiquidLimits: Sendable, Equatable {
    /// Cumulative UTF-8 bytes of the root template and supplied partials.
    public var sourceBytes: Int
    /// Maximum UTF-8 bytes of any completed rendered intermediate or final output.
    public var outputBytes: Int
    /// Cumulative loop iterations, including partial renders.
    public var loopIterations: Int
    /// Maximum syntax and active rendering depth.
    public var nestingDepth: Int
    /// Cumulative evaluator steps, independent of wall-clock time.
    public var renderSteps: Int
    /// Cumulative values admitted from context and across custom-filter boundaries.
    public var contextValues: Int
    /// Creates a finite limit profile, validated when an operation begins.
    /// Every capacity must be positive; nesting depth must not exceed 128.
    /// - Parameters:
    ///   - sourceBytes: Cumulative UTF-8 capacity of the root and all supplied partials.
    ///   - outputBytes: UTF-8 capacity of a completed intermediate or final output.
    ///   - loopIterations: Cumulative iterations across the root and its partial calls.
    ///   - nestingDepth: Maximum syntax and active rendering depth.
    ///   - renderSteps: Cumulative evaluator-work allowance for one invocation.
    ///   - contextValues: Cumulative admitted context and custom-filter value visits.
    public init(sourceBytes: Int = 1_048_576, outputBytes: Int = 8_388_608,
                loopIterations: Int = 100_000, nestingDepth: Int = 64,
                renderSteps: Int = 1_000_000, contextValues: Int = 100_000) {
        self.sourceBytes = sourceBytes; self.outputBytes = outputBytes
        self.loopIterations = loopIterations; self.nestingDepth = nestingDepth
        self.renderSteps = renderSteps; self.contextValues = contextValues
    }
    /// Default finite capacities.
    public static let `default` = LiquidLimits()
    internal func validate() throws {
        guard sourceBytes > 0, outputBytes > 0, loopIterations > 0, nestingDepth > 0,
              nestingDepth <= 128, renderSteps > 0, contextValues > 0 else {
            throw LiquidError.invalidValue("Limits must be positive; nesting depth must not exceed 128")
        }
    }
}

internal final class RuntimeBudget {
    let limits: LiquidLimits
    var remainingSteps: Int
    var remainingIterations: Int
    var remainingValues: Int
    var activeDepth = 0
    init(_ limits: LiquidLimits) {
        self.limits = limits; remainingSteps = limits.renderSteps; remainingIterations = limits.loopIterations
        remainingValues = limits.contextValues
    }
    func step() throws {
        try Task.checkCancellation()
        guard remainingSteps > 0 else { throw LiquidError.limitExceeded("renderSteps") }
        remainingSteps -= 1
    }
    func filterValue(depth: Int) throws {
        try step()
        guard depth <= limits.nestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
        guard remainingValues > 0 else { throw LiquidError.limitExceeded("contextValues") }
        remainingValues -= 1
    }
    func enter() throws {
        try step()
        guard activeDepth < limits.nestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
        activeDepth += 1
    }
    func iterate() throws {
        try step()
        guard remainingIterations > 0 else { throw LiquidError.limitExceeded("loopIterations") }
        remainingIterations -= 1
    }
    func output(_ text: String) throws {
        guard text.utf8.count <= limits.outputBytes else { throw LiquidError.limitExceeded("outputBytes") }
    }
    func capacity(_ bytes: Int, count: Int) throws -> Int {
        let (total, overflow) = bytes.multipliedReportingOverflow(by: count)
        guard !overflow, total <= limits.outputBytes else { throw LiquidError.limitExceeded("outputBytes") }
        return total
    }
}
