// SPDX-License-Identifier: Apache-2.0
import Foundation

extension Renderer {
    @inline(__always)
    internal func canUseStaticPath(_ path: String) -> Bool {
        guard !systemContextEnabled else { return false }
        guard hostContextEnabled else { return true }
        let root = String(path.prefix { $0 != "." })
        return root != "self" && !(context.getLiteralVariable(root) is LiquidHostObject)
    }

    @inline(__always)
    internal func ordinaryHostValue(_ value: Any) throws -> Any {
        guard hostContextEnabled else { return value }
        guard !(value is LiquidHostObject) else {
            throw LiquidError.invalidValue("A host object must be accessed through an exposed property")
        }
        return value
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
        guard let selected else { return NSNull() }
        let result: LiquidValue
        do {
            result = try await selected.body()
        } catch {
            try Task.checkCancellation()
            throw error
        }
        try budget.step()
        var bridge = FilterValueBridge(budget: budget)
        return try bridge.write(result)
    }
}
