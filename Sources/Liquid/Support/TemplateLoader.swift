// SPDX-License-Identifier: Apache-2.0
import Foundation

// Explicit source maps keep the runtime independent of filesystems and networks.
internal struct TemplateLoader: Sendable {
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

internal enum TemplateLoaderError: Error {
    case templateNotFound(String), pathTraversal(String), absolutePathNotAllowed(String)
    case invalidPath(String), invalidExtension(String), ioError(String)
}
