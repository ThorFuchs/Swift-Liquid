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
    case exact(PreparedExactTemplates)

    init(templates: [String: ASTNode]) {
        self = .legacy(.init(templates: templates))
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
}
