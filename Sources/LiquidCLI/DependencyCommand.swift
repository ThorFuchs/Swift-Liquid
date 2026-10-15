// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid

extension LiquidCommand {
    /// File discovery belongs to the CLI. Admit the complete bundle before parsing any partial.
    static func readDependencyPartials(_ path: String?, rootSourceBytes: Int) throws -> [String: String] {
        guard let path else { return [:] }
        let capacity = LiquidDependencyLimits.default
        var sourceRemaining = LiquidLimits.default.sourceBytes - rootSourceBytes
        var namesRemaining = capacity.nameBytes
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError("Partial directory does not exist")
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        var discoveryError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles], errorHandler: { _, error in discoveryError = error; return false }) else {
            throw CLIError("Cannot enumerate partial directory")
        }
        var partials: [String: String] = [:]
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let resource = try url.resourceValues(forKeys: keys)
            if resource.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard resource.isRegularFile == true, url.pathExtension == "liquid" else { continue }
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            let rootComponents = root.pathComponents
            guard normalized.pathComponents.starts(with: rootComponents) else { throw CLIError("Partial path escapes its directory") }
            let relative = normalized.pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
            let key = String(relative.dropLast(".liquid".count))
            guard partials[key] == nil else { throw CLIError("Ambiguous partial keys under Swift String equality") }
            guard partials.count < capacity.templates - 1 else { throw LiquidError.limitExceeded("dependencyTemplates") }
            guard key.utf8.count <= namesRemaining else { throw LiquidError.limitExceeded("dependencyNameBytes") }
            namesRemaining -= key.utf8.count
            let source = try readText(normalized.path, maximumBytes: sourceRemaining)
            sourceRemaining -= source.utf8.count
            partials[key] = source
        }
        if let discoveryError { throw discoveryError }
        try Task.checkCancellation()
        return partials
    }

    static func writeDependencies(_ result: LiquidDependencyInspection, format: String) throws {
        func id(_ value: LiquidDependencyNodeID) -> [String: Any] {
            switch value {
            case .root: ["kind": "root"]
            case .partial(let name): ["kind": "partial", "name": name]
            }
        }
        func edge(_ value: LiquidDependencyEdge) -> [String: Any] {
            ["origin": id(value.origin), "requestedName": value.requestedName,
             "resolvedName": value.resolvedName.map { $0 as Any } ?? NSNull()]
        }
        let object: [String: Any] = [
            "kind": "liquid.dependencies", "schemaVersion": 1,
            "nodes": result.nodes.map { node in
                ["id": id(node.id), "inspection": [
                    "variableRoots": node.inspection.variableRoots, "filterNames": node.inspection.filterNames,
                    "literalPartialNames": node.inspection.literalPartialNames,
                    "hasDynamicPartials": node.inspection.hasDynamicPartials]] as [String: Any]
            },
            "edges": result.edges.map(edge), "missingReferences": result.missingReferences.map(edge),
            "dynamicReferences": result.dynamicReferences.map(id), "cycles": result.cycles.map { $0.map(id) }
        ]
        let output: Data
        if format == "json" {
            output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        } else {
            // JSON notation keeps arbitrary supplied names unambiguous in text, too.
            func json(_ value: Any) throws -> String {
                String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
            }
            var lines = ["Partial dependencies:"]
            for node in result.nodes { lines.append("Node: " + (try json(id(node.id)))) }
            for value in result.edges { lines.append("Edge: " + (try json(edge(value)))) }
            lines.append("Dynamic references: " + (try json(result.dynamicReferences.map(id))))
            lines.append("Cycles: " + (try json(result.cycles.map { $0.map(id) })))
            output = Data(lines.joined(separator: "\n").utf8)
        }
        try FileHandle.standardOutput.write(contentsOf: output + Data([10]))
    }
}
