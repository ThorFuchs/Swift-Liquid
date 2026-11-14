// SPDX-License-Identifier: Apache-2.0
import Foundation

// Explicit source maps keep the runtime independent of filesystems and networks.
internal struct LegacyTemplates: Sendable {
    let templates: [String: ASTNode]
    func resolvedTemplatePath(for path: String, relativeTo: String?) throws -> String {
        if templates[path] != nil { return path }
        if templates[path + ".liquid"] != nil { return path + ".liquid" }
        throw TemplateLoaderError.templateNotFound(path)
    }
    func loadTemplateAST(_ path: String, relativeTo: String?) throws -> ASTNode {
        let key = try resolvedTemplatePath(for: path, relativeTo: relativeTo)
        guard let template = templates[key] else { throw TemplateLoaderError.templateNotFound(path) }
        return template
    }
}

// The tag prevents exact selection from entering the legacy catch/relookup path.
internal enum TemplateLoader: Sendable {
    case legacy(LegacyTemplates)
    case sources(LegacySources)
    case exact(PreparedExactTemplates)

    init(templates: [String: ASTNode]) {
        self = .legacy(.init(templates: templates))
    }
}

// Source admission remains eager, but each selected source is parsed at most
// once per render invocation by Renderer. No mutable cache lives in the engine.
internal struct LegacySources: Sendable {
    let sources: [String: String]
    let syntaxMode: LiquidSyntaxMode
    let extensionProfile: LiquidExtensionProfile
    let limits: LiquidLimits
    let resolver: LiquidTemplateNameResolver?

    init(sources: [String: String], syntaxMode: LiquidSyntaxMode,
         extensionProfile: LiquidExtensionProfile, limits: LiquidLimits,
         resolver: LiquidTemplateNameResolver? = nil) {
        self.sources = sources
        self.syntaxMode = syntaxMode
        self.extensionProfile = extensionProfile
        self.limits = limits
        self.resolver = resolver
    }

    func resolvedTemplatePath(for name: String) throws -> String {
        if let resolver {
            try Task.checkCancellation()
            let selected = resolver.select(name)
            try Task.checkCancellation()
            if let selected, sources[selected] != nil { return selected }
            let message = resolver.missing(name)
            try Task.checkCancellation()
            throw TemplateLoaderError.hostMissing(message)
        }
        if sources[name] != nil { return name }
        if sources[name + ".liquid"] != nil { return name + ".liquid" }
        throw TemplateLoaderError.templateNotFound(name)
    }
}

// One immutable AST per registry slot. The engine prepares/validates all slots
// before creating a renderer; lookup never reconstructs a String-keyed map.
internal struct PreparedExactTemplates: Sendable {
    let registry: LiquidTemplateRegistry
    let asts: [ASTNode]

    struct Selected: Sendable {
        let entryIndex: Int
        let storedName: String
        let ast: ASTNode
    }

    func select(_ requestedName: String) throws -> Selected? {
        guard let match = try registry.resolve(requestedName) else { return nil }
        return Selected(entryIndex: match.entryIndex, storedName: match.name, ast: asts[match.entryIndex])
    }
}

internal enum TemplateLoaderError: Error {
    case templateNotFound(String), pathTraversal(String), absolutePathNotAllowed(String)
    case invalidPath(String), invalidExtension(String), ioError(String)
    case hostMissing(String)
}
