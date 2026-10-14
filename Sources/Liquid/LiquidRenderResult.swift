// SPDX-License-Identifier: Apache-2.0

/// A runtime failure recovered by an explicitly diagnostic render operation.
public struct LiquidDiagnostic: Sendable, Equatable {
    /// The underlying runtime error without rendered decoration.
    public let message: String
    /// The template line when available.
    public let line: Int?
    /// The partial name when the failure occurred in a supplied partial.
    public let templateName: String?
    internal init(message: String, line: Int?, templateName: String? = nil) {
        self.message = message; self.line = line; self.templateName = templateName
    }
}

/// Rendered output and all recovered errors, in encounter order.
public struct LiquidRenderResult: Sendable {
    /// Complete output, including error text where the language emits it.
    public let output: String
    /// Recovered runtime failures. A nonempty collection is not an error-free render.
    public let diagnostics: [LiquidDiagnostic]
    internal init(output: String, diagnostics: [LiquidDiagnostic]) {
        self.output = output; self.diagnostics = diagnostics
    }
}
