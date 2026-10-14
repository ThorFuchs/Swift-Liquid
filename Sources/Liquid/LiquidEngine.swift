// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Renders standard Shopify Liquid using state owned by each invocation.
public struct LiquidEngine: Sendable {
    /// Finite operation capacities used by this engine.
    public let limits: LiquidLimits
    /// Whether unknown filters throw rather than leave the input unchanged.
    public let strictFilters: Bool
    /// Optional base clock for `now`, `today`, and dates with missing components.
    /// A nil value captures the current time at the start of each invocation.
    public let referenceTime: Date?
    private let filters: [ScalarKey: LiquidFilter]
    /// Creates a Liquid engine.
    public init(limits: LiquidLimits = .default, strictFilters: Bool = false, referenceTime: Date? = nil) {
        self.limits = limits; self.strictFilters = strictFilters; self.referenceTime = referenceTime
        self.filters = [:]
    }

    /// Creates an engine with immutable, explicitly scoped application filters.
    /// - Parameters:
    ///   - filters: Filters available to this engine and all its supplied partials.
    ///   - limits: Capacities shared by each invocation's evaluation and filter boundaries.
    ///   - strictFilters: Whether unregistered filters fail during rendering.
    ///   - referenceTime: An optional deterministic base clock.
    /// - Throws: `LiquidError.invalidValue` for invalid, duplicate, or protected names.
    public init(filters: [LiquidFilter], limits: LiquidLimits = .default,
                strictFilters: Bool = false, referenceTime: Date? = nil) throws {
        self.limits = limits; self.strictFilters = strictFilters; self.referenceTime = referenceTime
        self.filters = try LiquidFilter.validated(filters)
    }

    /// Parses and inspects one source without evaluating expressions or loading partials.
    /// - Parameters:
    ///   - template: Standard Liquid source.
    ///   - syntaxMode: The same parser mode used for rendering.
    /// - Returns: Unique syntactic references, ordered by their exact UTF-8 spelling.
    /// - Throws: Syntax, source/nesting capacity, invalid-limit, or cancellation errors.
    public func inspect(template: String, syntaxMode: LiquidSyntaxMode = .lax) throws -> LiquidTemplateInspection {
        try inspect(LiquidTemplate(template, syntaxMode: syntaxMode, limits: limits))
    }

    /// Inspects a reusable template under this engine's source and syntax-depth limits.
    /// Variable roots include local reads and unreachable branches, not just required inputs.
    /// Filters are reported regardless of registration; callbacks are never invoked.
    public func inspect(_ template: LiquidTemplate) throws -> LiquidTemplateInspection {
        try Task.checkCancellation()
        try checkSources(template.source, partials: [])
        return try inspectTemplate(template.ast, limits: limits)
    }

    /// Parses and renders a template with explicit variables and partial sources.
    /// - Parameters:
    ///   - template: Standard Liquid source.
    ///   - context: Values available to the template.
    ///   - templates: Partial sources addressed by `include` and `render`.
    ///   - syntaxMode: Shopify parsing mode applied to the root and all partials.
    /// - Returns: The complete rendered output.
    /// - Throws: Syntax, runtime, or cancellation errors.
    public func render(template: String, context: LiquidObject = [:], templates: [String: String] = [:], syntaxMode: LiquidSyntaxMode = .lax) async throws -> String {
        try checkSources(template, partials: Array(templates.values))
        return try await render(LiquidTemplate(template, syntaxMode: syntaxMode, limits: limits), context: context,
                                templates: templates.mapValues { try LiquidTemplate($0, syntaxMode: syntaxMode, limits: limits) })
    }

    /// Renders a parsed template without repeating its parsing work.
    /// - Parameters:
    ///   - template: An immutable parsed template.
    ///   - context: Values available to this invocation.
    ///   - templates: Parsed partials addressed by `include` and `render`.
    /// - Returns: The complete rendered output.
    /// - Throws: Runtime or cancellation errors.
    public func render(_ template: LiquidTemplate, context: LiquidObject = [:], templates: [String: LiquidTemplate] = [:]) async throws -> String {
        try await perform(template, context: context, templates: templates, recovering: false).output
    }

    /// Renders source while retaining recovered Liquid runtime diagnostics.
    /// Syntax errors, cancellation, unsupported values and quota failures still throw.
    public func renderWithDiagnostics(template: String, context: LiquidObject = [:], templates: [String: String] = [:], syntaxMode: LiquidSyntaxMode = .lax) async throws -> LiquidRenderResult {
        try checkSources(template, partials: Array(templates.values))
        return try await renderWithDiagnostics(LiquidTemplate(template, syntaxMode: syntaxMode, limits: limits), context: context,
            templates: templates.mapValues { try LiquidTemplate($0, syntaxMode: syntaxMode, limits: limits) })
    }

    /// Renders a reusable template and returns output together with recovered errors.
    public func renderWithDiagnostics(_ template: LiquidTemplate, context: LiquidObject = [:], templates: [String: LiquidTemplate] = [:]) async throws -> LiquidRenderResult {
        try await perform(template, context: context, templates: templates, recovering: true)
    }

    private func perform(_ template: LiquidTemplate, context: LiquidObject, templates: [String: LiquidTemplate], recovering: Bool) async throws -> LiquidRenderResult {
        try Task.checkCancellation()
        try limits.validate()
        try checkSources(template.source, partials: templates.values.map(\.source))
        let renderer = Renderer(configuration: .init(strictMode: strictFilters), limits: limits,
            recoveryEnabled: recovering, referenceTime: referenceTime ?? Date(), filters: filters)
        try admit(context, budget: renderer.budget)
        renderer.setTemplateLoader(TemplateLoader(templates: templates.mapValues(\.ast)))
        let values = RuntimeVariables(context.entries.map { ($0.key, $0.value.runtimeValue) })
        do {
            let output = try await renderer.render(template.ast, with: values)
            try renderer.budget.output(output)
            return LiquidRenderResult(output: output, diagnostics: renderer.diagnostics)
        } catch { throw publicError(error) }
    }

    private func checkSources(_ root: String, partials: [String]) throws {
        try limits.validate()
        var remaining = limits.sourceBytes
        for source in [root] + partials {
            let count = source.utf8.count
            guard count <= remaining else { throw LiquidError.limitExceeded("sourceBytes") }
            remaining -= count
        }
    }

    private func admit(_ object: LiquidObject, budget: RuntimeBudget) throws {
        var stack = object.entries.map { ($0.value, 1) }
        while let (value, depth) = stack.popLast() {
            try Task.checkCancellation()
            guard budget.remainingValues > 0 else { throw LiquidError.limitExceeded("contextValues") }
            guard depth <= limits.nestingDepth else { throw LiquidError.limitExceeded("nestingDepth") }
            budget.remainingValues -= 1
            switch value {
            case .number(let number):
                guard number.isFinite else { throw LiquidError.invalidValue("Numbers must be finite") }
            case .array(let values): stack.append(contentsOf: values.map { ($0, depth + 1) })
            case .object(let object): stack.append(contentsOf: object.entries.map { ($0.value, depth + 1) })
            default: break
            }
        }
    }
}
