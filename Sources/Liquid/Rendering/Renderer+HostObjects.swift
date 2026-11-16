// SPDX-License-Identifier: Apache-2.0
import Foundation

extension Renderer {
    @inline(__always)
    internal func canUseStaticPath(_ path: String) -> Bool {
        guard !systemContextEnabled else { return false }
        guard hostContextEnabled else { return true }
        let root = String(path.prefix { $0 != "." })
        let value = context.getLiteralVariable(root)
        return root != "self" && !(value is LiquidHostObject) && !(value is RuntimeSelf)
    }

    @inline(__always)
    internal func ordinaryHostValue(_ value: Any) throws -> Any {
        guard hostContextEnabled else { return value }
        guard !(value is LiquidHostObject) else {
            throw LiquidError.invalidValue("A host object must be accessed through an exposed property")
        }
        return value
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
        guard selected != nil || dynamic != nil else { return NSNull() }
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
}
