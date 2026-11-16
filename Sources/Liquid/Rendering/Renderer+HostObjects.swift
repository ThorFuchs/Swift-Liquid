// SPDX-License-Identifier: Apache-2.0
import Foundation

// Invocation-local representation; do not expose the host object through
// reflection or silently replace it in the caller's input.
internal struct RuntimeHostBoolean: Sendable {
    let value: Bool
}

internal struct RuntimeHostNumber: Sendable {
    let value: Int
}

internal struct RuntimeHostString: Sendable {
    let value: String?
    let identity: RuntimeHostStringIdentity
}

internal struct RuntimeHostNode: Sendable {
    let node: LiquidHostNode
    let depth: Int
}

internal final class RuntimeHostSequenceIdentity {}

// Contents are admitted and owned by a single renderer invocation.
internal struct RuntimeHostSequence {
    let values: [Any]
    let displayName: String
    let identity = RuntimeHostSequenceIdentity()
}

extension Renderer {
    @inline(__always)
    internal func canUseStaticPath(_ path: String) -> Bool {
        guard !systemContextEnabled else { return false }
        guard hostContextEnabled else { return true }
        let root = String(path.prefix { $0 != "." })
        let value = context.getLiteralVariable(root)
        return root != "self" && !(value is LiquidHostObject) && !(value is RuntimeHostBoolean) && !(value is RuntimeHostNumber) && !(boxedStringContextEnabled && (value is RuntimeHostString || value is [Any])) && !(hostSequenceContextEnabled && value is RuntimeHostSequence) && !(hostNodeContextEnabled && value is RuntimeHostNode) && !(value is RuntimeSelf)
    }

    @inline(__always)
    internal func ordinaryHostValue(_ value: Any) throws -> Any {
        guard hostContextEnabled else { return value }
        if let host = value as? LiquidHostObject {
            if let boolean = host.booleanValue { return RuntimeHostBoolean(value: boolean) }
            if let number = host.numberValue { return RuntimeHostNumber(value: number) }
            if let string = host.stringValue { return RuntimeHostString(value: string.value, identity: string.identity) }
            throw LiquidError.invalidValue("A host object must be accessed through an exposed property")
        }
        return value
    }

    internal func admitHostNode(_ node: LiquidHostNode, depth: Int, chargeRoot: Bool = true) throws -> RuntimeHostNode {
        if chargeRoot { try budget.filterValue(depth: depth) }
        guard budget.remainingValues > 0, node.properties.count < budget.remainingValues else {
            throw LiquidError.limitExceeded("contextValues")
        }
        try budget.filterValue(depth: depth + 1)
        var names = Set<ScalarKey>()
        for property in node.properties {
            try budget.filterValue(depth: depth + 1)
            guard !property.name.isEmpty, property.name.utf8.count <= budget.limits.outputBytes,
                  names.insert(ScalarKey(property.name)).inserted else {
                throw LiquidError.invalidValue("Invalid or duplicate host node property")
            }
        }
        return RuntimeHostNode(node: node, depth: depth)
    }

    internal func hostNodeAccess(_ runtime: RuntimeHostNode, key: Any) async throws -> Any {
        try budget.step()
        guard let key = systemPrimary(key) as? String else { return NSNull() }
        guard key.utf8.count <= budget.limits.outputBytes else { throw LiquidError.limitExceeded("outputBytes") }
        let wanted = ScalarKey(key)
        var found: LiquidHostNodeProperty?
        for property in runtime.node.properties {
            try budget.step()
            if ScalarKey(property.name) == wanted { found = property; break }
        }
        guard let found else { return NSNull() }
        let result: LiquidHostNodeResult
        do { result = try await found.body() }
        catch { try Task.checkCancellation(); throw error }
        try budget.step()
        let nextDepth = runtime.depth + 1
        switch result {
        case .missing: return NSNull()
        case .current:
            try budget.filterValue(depth: nextDepth)
            return RuntimeHostNode(node: runtime.node, depth: nextDepth)
        case .node(let node): return try admitHostNode(node, depth: nextDepth)
        case .value(let value):
            var bridge = FilterValueBridge(budget: budget)
            return try bridge.write(value, depth: nextDepth)
        }
    }

    internal func hostSequenceAccess(_ sequence: RuntimeHostSequence, key: Any) throws -> Any {
        try budget.step()
        guard let key = systemPrimary(key) as? String else { return NSNull() }
        switch key {
        case "size", "count": return sequence.values.count
        case "first": return sequence.values.first ?? NSNull()
        case "last": return sequence.values.last ?? NSNull()
        case "to_liquid": return sequence
        case "sort":
            return try sequence.values.sorted { left, right in
                try budget.step()
                return try compareValues(left, right) < 0
            }
        case "min", "max":
            guard var selected = sequence.values.first else { return NSNull() }
            for value in sequence.values.dropFirst() {
                try budget.step()
                let comparison = try compareValues(value, selected)
                if key == "min" ? comparison < 0 : comparison > 0 { selected = value }
            }
            return selected
        default: return NSNull()
        }
    }

    private func hasExactPrefix(_ key: String, _ prefix: String) throws -> Bool {
        var input = key.utf8.makeIterator()
        var count = 0
        for byte in prefix.utf8 {
            if count & 255 == 0 { try Task.checkCancellation() }
            guard input.next() == byte else { return false }
            count += 1
        }
        return true
    }

    internal func hostProperty(_ object: LiquidHostObject, key: String) async throws -> Any {
        try budget.step()
        guard key.utf8.count <= budget.limits.outputBytes else { throw LiquidError.limitExceeded("outputBytes") }
        let wanted = ScalarKey(key)
        var selected: LiquidHostProperty?
        for property in object.properties {
            try budget.step()
            if ScalarKey(property.name) == wanted { selected = property; break }
        }
        var dynamic: LiquidHostDynamicProperty?
        if selected == nil {
            for property in object.dynamicProperties {
                try budget.step()
                if try hasExactPrefix(key, property.prefix),
                   property.prefix.utf8.count > (dynamic?.prefix.utf8.count ?? 0) {
                    dynamic = property
                }
            }
        }
        guard selected != nil || dynamic != nil else {
            guard object.indexer != nil else { return NSNull() }
            return try await hostIndex(object, key: .string(key), missingIndexerIsError: false)
        }
        let result: LiquidValue?
        do {
            if let selected { result = try await selected.body() }
            else if let dynamic { result = try await dynamic.body(key) }
            else { return NSNull() }
        } catch {
            try Task.checkCancellation()
            throw error
        }
        try budget.step()
        guard let result else { return NSNull() }
        var bridge = FilterValueBridge(budget: budget)
        return try bridge.write(result)
    }

    internal func hostIndex(_ object: LiquidHostObject, key: LiquidHostIndexKey,
                            missingIndexerIsError: Bool = true) async throws -> Any {
        try budget.step()
        guard let indexer = object.indexer else {
            if missingIndexerIsError { throw LiquidError.invalidValue("Host properties require a string key") }
            return NSNull()
        }
        if case .string(let value) = key, value.utf8.count > budget.limits.outputBytes {
            throw LiquidError.limitExceeded("outputBytes")
        }
        let result: LiquidValue?
        do { result = try await indexer.body(key) }
        catch { try Task.checkCancellation(); throw error }
        try budget.step()
        guard let result else { return NSNull() }
        var bridge = FilterValueBridge(budget: budget)
        return try bridge.write(result)
    }
}
